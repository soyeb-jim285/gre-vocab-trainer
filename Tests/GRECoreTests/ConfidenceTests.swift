import Foundation
import Testing
@testable import GRECore

@Suite struct ConfidenceTests {

    private let on = ConfidenceSettings(isEnabled: true)

    private func adjust(
        _ rating: FSRSRating, _ mode: StudyMode, _ latency: Duration?,
        settings: ConfidenceSettings? = nil
    ) -> FSRSRating {
        Confidence.adjust(rating, mode: mode, latency: latency, settings: settings ?? on)
    }

    // MARK: - The invariant everything else depends on

    @Test func itNeverRaisesARating() {
        // Exhaustive: no mode, rating or answer time may produce something better
        // than the score earned. A fast guess must not inflate an interval.
        for mode in StudyMode.allCases {
            for rating in FSRSRating.allCases {
                for seconds in [0, 1, 2, 3, 5, 8, 11, 15, 20, 30, 90, 600] {
                    let out = adjust(rating, mode, .seconds(seconds))
                    #expect(out.rawValue <= rating.rawValue,
                            "\(mode) \(rating) at \(seconds)s rose to \(out)")
                }
            }
        }
    }

    @Test func aFailedAnswerIsNeverSoftened() {
        for mode in StudyMode.allCases {
            #expect(adjust(.again, mode, .seconds(1)) == .again)
        }
    }

    // MARK: - What it actually does

    @Test func aQuickCorrectTapKeepsTheFullRating() {
        #expect(adjust(.easy, .multipleChoice, .seconds(2)) == .easy)
    }

    @Test func aHesitantCorrectTapDropsToGood() {
        #expect(adjust(.easy, .multipleChoice, .seconds(8)) == .good)
    }

    @Test func aVerySlowCorrectTapDropsToHard() {
        #expect(adjust(.easy, .multipleChoice, .seconds(30)) == .hard)
    }

    @Test func clozeIsGivenLongerBecauseTheSentenceHasToBeReadFirst() {
        // Eight seconds is hesitant on four short definitions and brisk on a
        // sentence. One global threshold would call every cloze answer hesitant.
        #expect(adjust(.easy, .multipleChoice, .seconds(8)) == .good)
        #expect(adjust(.easy, .contextCloze, .seconds(8)) == .easy)
    }

    // MARK: - When it stays out of the way

    @Test func itIsOffByDefault() {
        #expect(ConfidenceSettings().isEnabled == false)
        #expect(Confidence.adjust(.easy, mode: .multipleChoice, latency: .seconds(60),
                                  settings: ConfidenceSettings()) == .easy)
    }

    @Test func theTypedAndWrittenModesAreLeftAlone() {
        // Their scores already discriminate; folding latency in would count the
        // same hesitation twice.
        for mode in [StudyMode.reverseRecall, .spelling, .defineAndUse] {
            #expect(adjust(.easy, mode, .seconds(120)) == .easy)
        }
    }

    @Test func aMissingOrImpossibleTimeChangesNothing() {
        #expect(adjust(.easy, .multipleChoice, nil) == .easy)
        #expect(adjust(.easy, .multipleChoice, .seconds(0)) == .easy)
        #expect(adjust(.easy, .multipleChoice, .seconds(-5)) == .easy)
    }

    @Test func aNonsenseScaleIsIgnoredRatherThanDividingTheBands() {
        #expect(adjust(.easy, .multipleChoice, .seconds(30),
                       settings: ConfidenceSettings(isEnabled: true, scale: 0)) == .easy)
    }

    @Test func theScaleWidensTheBands() {
        // Thirty seconds is Hard at the default and merely Good at triple.
        #expect(adjust(.easy, .multipleChoice, .seconds(30)) == .hard)
        #expect(adjust(.easy, .multipleChoice, .seconds(30),
                       settings: ConfidenceSettings(isEnabled: true, scale: 3)) == .good)
    }

    // MARK: - What it does to the schedule over a long history

    /// Ninety days of daily reviews, all correct, with a fixed answer time.
    private func stabilityAfterNinetyDays(latency: Duration?, settings: ConfidenceSettings) -> Double {
        let fsrs = FSRS(enableFuzzing: false)
        var card = FSRSCard()
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        for _ in 0..<90 {
            let rating = Confidence.adjust(.easy, mode: .multipleChoice,
                                           latency: latency, settings: settings)
            card = fsrs.review(card, rating: rating, at: date)
            date = max(card.due, date.addingTimeInterval(86_400))
        }
        return card.stability ?? 0
    }

    @Test func aQuickLearnerSchedulesExactlyAsTheyDidBefore() {
        // The upgrade path for anyone already answering fast has to be a no-op,
        // or switching this on silently reschedules their whole deck.
        let baseline = stabilityAfterNinetyDays(latency: nil, settings: ConfidenceSettings())
        #expect(stabilityAfterNinetyDays(latency: .seconds(2), settings: on) == baseline)
    }

    @Test func hesitationShortensIntervalsRatherThanLengtheningThem() {
        // The failure that would go unnoticed for weeks is intervals inflating.
        // Assert the direction over a long history, not just one review.
        let baseline = stabilityAfterNinetyDays(latency: nil, settings: ConfidenceSettings())
        for seconds in [8, 15, 30, 120] {
            let adjusted = stabilityAfterNinetyDays(latency: .seconds(seconds), settings: on)
            #expect(adjusted <= baseline,
                    "answering in \(seconds)s stretched stability to \(adjusted) over \(baseline)")
        }
    }

    @Test func everyModeHasABandAndTheFastEdgeComesFirst() {
        for mode in StudyMode.allCases {
            let band = Confidence.band(for: mode)
            #expect(band.fast < band.slow, "\(mode) has an inverted band")
            #expect(band.fast > .zero)
        }
    }
}
