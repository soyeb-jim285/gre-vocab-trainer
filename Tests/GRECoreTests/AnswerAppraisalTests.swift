import Foundation
import Testing
@testable import GRECore

/// The one derivation from an answer to a rating.
@Suite struct AnswerAppraisalTests {

    private static let catalog = try! WordCatalog.bundled()
    private let on = ConfidenceSettings(isEnabled: true, scale: 1)

    private func rate(
        score: Int, report: SelfReport? = nil, hints: HintLevel = .none,
        mode: StudyMode = .typeMeaning, latency: Duration? = nil,
        settings: ConfidenceSettings = ConfidenceSettings()
    ) -> FSRSRating {
        AnswerAppraisal.rate(
            grade: Grade(score: score), selfReport: report, hints: hints,
            mode: mode, latency: latency, settings: settings
        )
    }

    // MARK: - Narrowing only

    @Test func aPerfectAnswerWithNoCaveatsKeepsWhatItEarned() {
        #expect(rate(score: 100) == .easy)
    }

    @Test func noInputCanRaiseTheRatingTheScoreEarned() {
        // The whole schedule depends on this. A fast confident answer to a
        // half-right question is still a half-right answer.
        for report in SelfReport.allCases {
            for hint in HintLevel.allCases {
                let rating = rate(score: 75, report: report, hints: hint,
                                  mode: .multipleChoice, latency: .seconds(1), settings: on)
                #expect(rating.rawValue <= FSRSRating.good.rawValue,
                        "\(report)/\(hint) raised a Good answer")
            }
        }
    }

    // MARK: - Confidence

    @Test func aRightAnswerCalledAGuessDoesNotStretchTheInterval() {
        // Heads on a coin toss is not a memory, and rating it Easy would put the
        // word out of sight for weeks.
        #expect(rate(score: 100, report: .guess) == .hard)
        #expect(rate(score: 100, report: .unsure) == .good)
        #expect(rate(score: 100, report: .confident) == .easy)
    }

    @Test func confidentlyWrongComesBackAtOnce() {
        // Worse than never seen: there is a wrong memory to unlearn before the
        // right one can take hold.
        #expect(rate(score: 0, report: .confident) == .again)
        #expect(rate(score: 20, report: .confident) == .again)
    }

    // MARK: - Hints

    @Test func eachRungOfTheLadderLowersTheCeiling() {
        #expect(rate(score: 100, hints: .none) == .easy)
        #expect(rate(score: 100, hints: .semantic) == .good)
        #expect(rate(score: 100, hints: .example) == .hard)
        #expect(rate(score: 100, hints: .reveal) == .again)
    }

    @Test func aHintCannotRescueAWrongAnswer() {
        #expect(rate(score: 10, hints: .none) == .again)
        #expect(rate(score: 10, hints: .semantic) == .again)
    }

    // MARK: - Latency, now one input among several

    @Test func latencyStillNarrowsTheTapModes() {
        #expect(rate(score: 100, mode: .multipleChoice, latency: .seconds(2), settings: on) == .easy)
        #expect(rate(score: 100, mode: .multipleChoice, latency: .seconds(30), settings: on) == .hard)
    }

    @Test func latencyIsIgnoredWhereTheScoreAlreadyDiscriminates() {
        // Writing and typed meanings are graded on a fine scale already; folding
        // time in on top would count the same hesitation twice.
        #expect(rate(score: 100, mode: .typeMeaning, latency: .seconds(90), settings: on) == .easy)
        #expect(rate(score: 100, mode: .defineAndUse, latency: .seconds(90), settings: on) == .easy)
    }

    @Test func theStrictestSignalWins() {
        // Confident, fast, and one hint in: the hint is what the rating follows.
        let rating = rate(score: 100, report: .confident, hints: .semantic,
                          mode: .multipleChoice, latency: .seconds(1), settings: on)
        #expect(rating == .good)
    }

    // MARK: - The ladder's content

    @Test func theLadderClimbsFromNudgeToAnswer() throws {
        let word = try #require(Self.catalog["abate"])
        #expect(HintLadder.hint(.none, for: word) == nil)
        let semantic = try #require(HintLadder.hint(.semantic, for: word))
        #expect(semantic == word.grounding?.semanticHint)
        let example = try #require(HintLadder.hint(.example, for: word))
        #expect(example.contains("____"))
        #expect(HintLadder.hint(.reveal, for: word) == word.teachingDefinition)
    }

    @Test func aWordWithNoExampleSkipsThatRung() throws {
        let word = try #require(Self.catalog["abate"])
        #expect(HintLadder.available(for: word) == [.semantic, .example, .reveal])
        #expect(HintLadder.next(after: .none, for: word) == .semantic)
        #expect(HintLadder.next(after: .example, for: word) == .reveal)
        #expect(HintLadder.next(after: .reveal, for: word) == nil)
    }

    @Test func everyShippedWordCanOfferAtLeastANudgeAndAnAnswer() {
        // An empty ladder would leave a stuck learner with nothing between
        // staring and giving up.
        for word in Self.catalog.words {
            let rungs = HintLadder.available(for: word)
            #expect(rungs.contains(.semantic), "\(word.id) has no semantic hint")
            #expect(rungs.contains(.reveal), "\(word.id) cannot be revealed")
        }
    }
}
