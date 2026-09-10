import Foundation
import Testing
@testable import GRECore

/// How the planner picks *which question* to ask about a word, as opposed to
/// which word to ask about — that half lives in `SessionPlannerTests`.
@Suite struct ModeLadderTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func seen(
        _ id: String, dueIn days: Double, reviews: Int = 3, stability: Double = 10,
        lastReviewDaysAgo: Double = 1, state: FSRSState = .review
    ) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: stability, difficulty: 5,
                           due: now.addingTimeInterval(days * 86_400),
                           lastReview: now.addingTimeInterval(-lastReviewDaysAgo * 86_400),
                           state: state, step: state == .review ? nil : 0),
            reviewCount: reviews
        )
    }

    /// A card still inside the learning steps, due `minutes` from now.
    private func learning(_ id: String, dueInMinutes minutes: Double) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: 1, difficulty: 5, due: now.addingTimeInterval(minutes * 60),
                           lastReview: now.addingTimeInterval(-60), state: .learning, step: 1),
            reviewCount: 1
        )
    }

    /// Defaults to a non-trap word, so the ladder rather than the trap drill is
    /// what these assertions are looking at.
    private func mode(
        _ card: StudyCard, ai: Bool = true, writingAfter: Int = 3, wordID: String = "laconic"
    ) -> StudyMode {
        let word = Self.catalog[wordID]!
        return SessionPlanner.mode(
            for: card, word: word,
            settings: SessionSettings(aiEnabled: ai, writingModeAfterReviews: writingAfter)
        )
    }

    @Test func aBrandNewWordStartsWithMultipleChoice() {
        #expect(mode(StudyCard(wordID: "abate")) == .multipleChoice)
    }

    @Test func modesFollowMemoryStrength() {
        #expect(mode(seen("abate", dueIn: 0, reviews: 1, stability: 2), ai: false) == .multipleChoice)
        // Then the ladder: use it in context, produce it, spell it.
        #expect(mode(seen("abate", dueIn: 0, reviews: 3, stability: 10), ai: false) == .contextCloze)
        #expect(mode(seen("abate", dueIn: 0, reviews: 4, stability: 10), ai: false) == .reverseRecall)
        #expect(mode(seen("abate", dueIn: 0, reviews: 5, stability: 10), ai: false) == .spelling)
        #expect(mode(seen("abate", dueIn: 0, reviews: 3, stability: 10)) == .defineAndUse)
    }

    @Test func aTrapWordIsChallengedOnItsSecondOuting() throws {
        let flag = try #require(Self.catalog["flag"])
        #expect(flag.isTrap)
        let card = seen("flag", dueIn: 0, reviews: 1, stability: 10)
        #expect(SessionPlanner.mode(for: card, word: flag, settings: SessionSettings(aiEnabled: false))
                == .senseInContext)
    }

    @Test func anOrdinaryWordIsNeverAskedWhichMeaning() throws {
        let laconic = try #require(Self.catalog["laconic"])
        #expect(laconic.isTrap == false)
        for reviews in 0..<12 {
            let card = seen("laconic", dueIn: 0, reviews: reviews, stability: 10)
            let m = SessionPlanner.mode(for: card, word: laconic,
                                        settings: SessionSettings(aiEnabled: false))
            #expect(m != .senseInContext, "asked which meaning about a single-sense word")
        }
    }

    @Test func aLapsedWordDropsBackToMultipleChoice() {
        let lapsed = seen("abate", dueIn: 0, reviews: 9, stability: 30, state: .relearning)
        #expect(mode(lapsed) == .multipleChoice)
        #expect(mode(lapsed, writingAfter: 0) == .multipleChoice)
    }

    @Test func aCardStillInLearningStepsStaysOnMultipleChoice() {
        #expect(mode(learning("abate", dueInMinutes: 0), ai: false) == .multipleChoice)
    }

    @Test func withoutAnApiKeyTheAiModeIsNeverScheduled() {
        for reviews in 0..<12 {
            #expect(mode(seen("abate", dueIn: 0, reviews: reviews), ai: false) != .defineAndUse)
        }
    }
}

@Suite struct WritingModeThresholdTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(reviews: Int) -> StudyCard {
        StudyCard(
            wordID: "abate",
            fsrs: FSRSCard(stability: 10, difficulty: 5, due: now.addingTimeInterval(-86_400),
                           lastReview: now.addingTimeInterval(-172_800), state: .review, step: nil),
            reviewCount: reviews
        )
    }

    private static let catalog = try! WordCatalog.bundled()

    private func mode(reviews: Int, writingAfter: Int, ai: Bool = true) -> StudyMode {
        SessionPlanner.mode(
            for: card(reviews: reviews), word: Self.catalog["laconic"]!,
            settings: SessionSettings(aiEnabled: ai, writingModeAfterReviews: writingAfter)
        )
    }

    @Test func theDefaultThresholdKeepsTheExistingLadder() {
        #expect(SessionSettings().writingModeAfterReviews == 3)
        #expect(mode(reviews: 1, writingAfter: 3) == .reverseRecall)
        #expect(mode(reviews: 2, writingAfter: 3) == .spelling)
        #expect(mode(reviews: 3, writingAfter: 3) == .defineAndUse)
    }

    @Test func aThresholdOfZeroGoesStraightToWriting() {
        #expect(mode(reviews: 0, writingAfter: 0) == .defineAndUse)
        #expect(mode(reviews: 7, writingAfter: 0) == .defineAndUse)
    }

    @Test func aThresholdOfOneMeetsTheWordThenWritesAboutIt() {
        #expect(mode(reviews: 0, writingAfter: 1) == .multipleChoice)
        #expect(mode(reviews: 1, writingAfter: 1) == .defineAndUse)
    }

    @Test func aHighThresholdDelaysWritingAndKeepsCyclingLocalModes() {
        #expect(mode(reviews: 5, writingAfter: 99) != .defineAndUse)
        #expect(mode(reviews: 40, writingAfter: 99) != .defineAndUse)
    }

    @Test func noApiKeyOverridesEvenAZeroThreshold() {
        #expect(mode(reviews: 0, writingAfter: 0, ai: false) != .defineAndUse)
        #expect(mode(reviews: 9, writingAfter: 0, ai: false) != .defineAndUse)
    }

    @Test(arguments: 0...6)
    func belowTheThresholdEveryModeIsLocallyGraded(reviews: Int) {
        let mode = mode(reviews: reviews, writingAfter: 99)
        #expect(StudyMode.locallyGraded.contains(mode))
    }
}
