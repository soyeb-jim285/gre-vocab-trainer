import Foundation
import Testing
@testable import GRECore

/// A forced mode drills one skill for a whole session. It overrides the
/// evidence, but not the API key and not a word's own data -- those are hard
/// constraints, not preferences. It does not override meeting a word for the
/// first time either.
@Suite struct ForcedModeTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(reviews: Int, state: FSRSState = .review) -> StudyCard {
        StudyCard(
            wordID: "abate",
            fsrs: FSRSCard(stability: 10, difficulty: 5, due: now.addingTimeInterval(-86_400),
                           lastReview: now.addingTimeInterval(-172_800), state: state, step: nil),
            reviewCount: reviews, isIntroduced: true
        )
    }

    /// "abate" is deliberately not a trap word: forcing "which meaning" on it
    /// must fall back, exactly as forcing writing without a key does.
    private func mode(
        forced: StudyMode?, reviews: Int, ai: Bool = true, writingAfter: Int = 3,
        wordID: String = "abate"
    ) -> StudyMode? {
        Curriculum.step(
            for: card(reviews: reviews), word: Self.catalog[wordID]!,
            competence: CardCompetence([]),
            settings: SessionSettings(aiEnabled: ai, writingModeAfterReviews: writingAfter,
                                      forcedMode: forced)
        ).mode
    }

    @Test func autoIsTheDefault() {
        #expect(SessionSettings().forcedMode == nil)
    }

    @Test(arguments: StudyMode.allCases)
    func forcingAModeAppliesItWhateverTheHistory(forced: StudyMode) {
        // "flag" is a trap word, so every mode including "which meaning" applies.
        for reviews in [1, 2, 3, 9] {
            #expect(mode(forced: forced, reviews: reviews, wordID: "flag") == forced)
        }
        #expect(Curriculum.step(for: card(reviews: 4, state: .relearning),
                                word: Self.catalog["flag"]!, competence: CardCompetence([]),
                                settings: SessionSettings(forcedMode: forced)).mode == forced)
    }

    @Test func evenAForcedModeMeetsAWordBeforeTestingIt() {
        // A forced drill says which skill to practise. It does not say that a
        // word the learner has never seen should be guessed at.
        let step = Curriculum.step(
            for: StudyCard(wordID: "abate"), word: Self.catalog["abate"]!,
            competence: CardCompetence([]),
            settings: SessionSettings(aiEnabled: false, forcedMode: .spelling)
        )
        #expect(step == .introduce)
        // And from the next outing onward the forced mode applies.
        #expect(mode(forced: .spelling, reviews: 1, ai: false) == .spelling)
    }

    @Test func forcingWritingWithoutAKeyFallsBackToLocalModes() throws {
        for reviews in [1, 2, 5] {
            let m = try #require(mode(forced: .defineAndUse, reviews: reviews, ai: false))
            #expect(m != .defineAndUse)
            #expect(StudyMode.locallyGraded.contains(m))
        }
    }

    @Test func forcingWhichMeaningOnAnOrdinaryWordFallsBack() throws {
        // The mode only makes sense where a competing everyday sense exists.
        let m = try #require(mode(forced: .senseInContext, reviews: 3, ai: false, wordID: "laconic"))
        #expect(m != .senseInContext)
        #expect(StudyMode.locallyGraded.contains(m))
    }

    @Test func forcingALocalModeWorksWithoutAKey() {
        #expect(mode(forced: .spelling, reviews: 1, ai: false) == .spelling)
        #expect(mode(forced: .spelling, reviews: 4, ai: false) == .spelling)
    }

    @Test func theWritingThresholdIsIgnoredWhileAModeIsForced() {
        #expect(mode(forced: .defineAndUse, reviews: 1, writingAfter: 99) == .defineAndUse)
    }
}
