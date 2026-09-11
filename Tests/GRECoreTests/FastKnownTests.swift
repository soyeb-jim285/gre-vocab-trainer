import Foundation
import Testing
@testable import GRECore

/// The pathway for words the learner already owns.
///
/// Three thousand words is only tractable if the ones already known can be
/// proved and set aside. This is what stops a strong learner grinding through
/// teaching cards for vocabulary they have used for years.
@Suite struct FastKnownTests {

    private static let catalog = try! WordCatalog.bundled()

    private func known(
        score: Int = 100, report: SelfReport? = .confident, hints: HintLevel = .none,
        latency: Duration? = .seconds(5), mode: StudyMode = .typeMeaning
    ) -> Bool {
        AnswerAppraisal.isFastKnown(
            grade: Grade(score: score), selfReport: report, hints: hints,
            mode: mode, latency: latency
        )
    }

    @Test func aPreciseConfidentUnaidedFastAnswerQualifies() {
        #expect(known())
    }

    @Test func everyConditionIsNecessary() {
        // Each of these is a different way of being right without knowing.
        #expect(!known(score: 75), "approximately right is not knowing")
        #expect(!known(report: .unsure), "hoping is not knowing")
        #expect(!known(report: nil), "an unasked learner has not claimed anything")
        #expect(!known(hints: .semantic), "nudged is not unaided")
        #expect(!known(latency: .seconds(60)), "reconstructed is not recalled")
    }

    @Test func anUnmeasuredAnswerDoesNotQualify() {
        // The clock is tainted when audio played or the app was backgrounded.
        // This pathway skips teaching, so it asks for evidence rather than
        // assuming it.
        #expect(!known(latency: nil))
        #expect(!known(latency: .zero))
    }

    @Test func theClockAllowedDependsOnWhatTheModeAsksFor() {
        // Ten seconds is fast for composing a definition and slow for tapping
        // one of four options.
        #expect(known(latency: .seconds(7), mode: .typeMeaning))
        #expect(!known(latency: .seconds(7), mode: .multipleChoice))
    }

    @Test func aKnownWordIsRatedEasyAndNeedsNoTeaching() {
        // The two consequences that make the pathway worth having.
        let rating = AnswerAppraisal.rate(
            grade: Grade(score: 100), selfReport: .confident, hints: .none,
            mode: .typeMeaning, latency: .seconds(5)
        )
        #expect(rating == .easy)
        #expect(!Curriculum.teaches(afterMeaningScore: 4))
    }

    @Test func itComesBackDaysLaterRatherThanInTheSameSession() throws {
        // FSRS already does this: an Easy first review sets a long initial
        // stability. The pathway needs no scheduling machinery of its own, which
        // is the point of rating it rather than flagging it.
        let card = FSRS(enableFuzzing: false).review(FSRSCard(), rating: .easy, at: .now)
        let interval = card.due.timeIntervalSinceNow
        #expect(interval > 2 * 86_400, "came back after \(interval / 86_400) days")
        #expect(card.state == .review)
    }

    @Test func aConfirmedWordIsNotSentBackToRecognition() throws {
        // Having proved the word, the next question should test it rather than
        // start the ladder again at multiple choice.
        let word = try #require(Self.catalog["laconic"])
        let fsrs = FSRS(enableFuzzing: false)
        let reviewed = fsrs.review(FSRSCard(), rating: .easy, at: .now)
        let card = StudyCard(wordID: word.id, fsrs: reviewed, reviewCount: 1, isIntroduced: true)
        let step = Curriculum.step(
            for: card, word: word, competence: CardCompetence([]),
            settings: SessionSettings(aiEnabled: true)
        )
        #expect(step != .pretest)
        #expect(step != .introduce)
    }
}
