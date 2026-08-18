import Foundation
import Testing
@testable import GRECore

@Suite struct SessionPlannerTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func seen(_ id: String, dueIn days: Double, reviews: Int = 3) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: 10, difficulty: 5,
                           due: now.addingTimeInterval(days * 86_400),
                           lastReview: now.addingTimeInterval(-86_400), state: .review, step: nil),
            reviewCount: reviews
        )
    }

    private func settings(
        newLimit: Int = 10, length: Int = 20, ai: Bool = true, writingAfter: Int = 3
    ) -> SessionSettings {
        SessionSettings(dailyNewWordLimit: newLimit, sessionLength: length,
                        aiEnabled: ai, writingModeAfterReviews: writingAfter)
    }

    // MARK: - What goes in the queue

    @Test func emptyInputsProduceAnEmptySession() {
        let plan = SessionPlanner.plan(cards: [], catalog: Self.catalog,
                                       settings: settings(newLimit: 0), now: now)
        #expect(plan.isEmpty)
    }

    @Test func cardsNotYetDueAreLeftOut() {
        let plan = SessionPlanner.plan(cards: [seen("abate", dueIn: 5)], catalog: Self.catalog,
                                       settings: settings(newLimit: 0), now: now)
        #expect(plan.isEmpty)
    }

    @Test func dueCardsAreIncluded() {
        let plan = SessionPlanner.plan(cards: [seen("abate", dueIn: -1)], catalog: Self.catalog,
                                       settings: settings(newLimit: 0), now: now)
        #expect(plan.map(\.card.wordID) == ["abate"])
    }

    @Test func aCardDueAtThisExactMomentIsIncluded() {
        let card = StudyCard(
            wordID: "abate",
            fsrs: FSRSCard(stability: 10, difficulty: 5, due: now,
                           lastReview: now.addingTimeInterval(-86_400), state: .review, step: nil),
            reviewCount: 3
        )
        let plan = SessionPlanner.plan(cards: [card], catalog: Self.catalog,
                                       settings: settings(newLimit: 0), now: now)
        #expect(plan.map(\.card.wordID) == ["abate"])
    }

    @Test func theMostOverdueCardComesFirst() {
        let cards = [seen("abate", dueIn: -1), seen("laconic", dueIn: -9), seen("acumen", dueIn: -4)]
        let plan = SessionPlanner.plan(cards: cards, catalog: Self.catalog,
                                       settings: settings(newLimit: 0), now: now)
        #expect(plan.map(\.card.wordID) == ["laconic", "acumen", "abate"])
    }

    @Test func reviewsComeBeforeNewWords() {
        let plan = SessionPlanner.plan(cards: [seen("abate", dueIn: -1)], catalog: Self.catalog,
                                       settings: settings(newLimit: 5), now: now)
        #expect(plan.first?.card.wordID == "abate")
        #expect(plan.count > 1, "new words should follow the review")
        // Everything after the review must be a word with no history.
        #expect(plan.dropFirst().allSatisfy { $0.card.reviewCount == 0 })
    }

    // MARK: - Introducing new words

    @Test func newWordsAreCappedByTheDailyLimit() {
        let plan = SessionPlanner.plan(cards: [], catalog: Self.catalog,
                                       settings: settings(newLimit: 4, length: 50), now: now)
        #expect(plan.count == 4)
    }

    @Test func newWordsComeFromTheCoreTierFirst() {
        let plan = SessionPlanner.plan(cards: [], catalog: Self.catalog,
                                       settings: settings(newLimit: 8), now: now)
        let tiers = plan.compactMap { Self.catalog[$0.card.wordID]?.tier }
        #expect(tiers.allSatisfy { $0 == .core }, "got \(Set(tiers))")
    }

    @Test func wordsAlreadyBeingStudiedAreNotIntroducedAgain() {
        // Take whichever core words the planner would pick, then feed them back
        // as already-known and check it moves on to different ones.
        let first = SessionPlanner.plan(cards: [], catalog: Self.catalog,
                                        settings: settings(newLimit: 5), now: now)
        let known = first.map { seen($0.card.wordID, dueIn: 5) }
        let second = SessionPlanner.plan(cards: known, catalog: Self.catalog,
                                         settings: settings(newLimit: 5), now: now)
        #expect(Set(second.map(\.card.wordID)).isDisjoint(with: Set(first.map(\.card.wordID))))
    }

    @Test func introductionOrderIsStableAcrossCalls() {
        let a = SessionPlanner.plan(cards: [], catalog: Self.catalog, settings: settings(newLimit: 6), now: now)
        let b = SessionPlanner.plan(cards: [], catalog: Self.catalog, settings: settings(newLimit: 6), now: now)
        #expect(a.map(\.card.wordID) == b.map(\.card.wordID))
    }

    // MARK: - Length

    @Test func theSessionIsCappedAtItsConfiguredLength() {
        let cards = (0..<40).map { seen(Self.catalog.words[$0].id, dueIn: -Double($0) - 1) }
        let plan = SessionPlanner.plan(cards: cards, catalog: Self.catalog,
                                       settings: settings(newLimit: 10, length: 12), now: now)
        #expect(plan.count == 12)
    }

    @Test func reviewsAreNeverDroppedToMakeRoomForNewWords() {
        let cards = (0..<15).map { seen(Self.catalog.words[$0].id, dueIn: -Double($0) - 1) }
        let plan = SessionPlanner.plan(cards: cards, catalog: Self.catalog,
                                       settings: settings(newLimit: 10, length: 15), now: now)
        #expect(plan.count == 15)
        #expect(plan.allSatisfy { $0.card.reviewCount > 0 }, "new words crowded out due reviews")
    }

    // MARK: - Mode assignment

    @Test func aBrandNewWordStartsWithMultipleChoice() {
        let plan = SessionPlanner.plan(cards: [], catalog: Self.catalog,
                                       settings: settings(newLimit: 3), now: now)
        #expect(plan.allSatisfy { $0.mode == .multipleChoice })
    }

    @Test func modesGetHarderAsAWordIsSeenMoreOften() {
        func mode(afterReviews n: Int) -> StudyMode {
            SessionPlanner.plan(cards: [seen("abate", dueIn: -1, reviews: n)], catalog: Self.catalog,
                                settings: settings(newLimit: 0), now: now)[0].mode
        }
        #expect(mode(afterReviews: 0) == .multipleChoice)
        #expect(mode(afterReviews: 1) == .reverseRecall)
        #expect(mode(afterReviews: 2) == .spelling)
        #expect(mode(afterReviews: 3) == .defineAndUse)
        #expect(mode(afterReviews: 12) == .defineAndUse)
    }

    @Test func withoutAnApiKeyTheAiModeIsNeverScheduled() {
        let cards = (0..<12).map { seen(Self.catalog.words[$0].id, dueIn: -1, reviews: $0) }
        let plan = SessionPlanner.plan(cards: cards, catalog: Self.catalog,
                                       settings: settings(newLimit: 0, ai: false), now: now)
        #expect(plan.isEmpty == false)
        #expect(plan.allSatisfy { $0.mode != .defineAndUse })
    }

    @Test func withoutAnApiKeyMatureWordsStillRotateThroughTheLocalModes() {
        let cards = (0..<12).map { seen(Self.catalog.words[$0].id, dueIn: -1, reviews: 5 + $0) }
        let plan = SessionPlanner.plan(cards: cards, catalog: Self.catalog,
                                       settings: settings(newLimit: 0, ai: false), now: now)
        // All three local modes should appear rather than everything collapsing to one.
        #expect(Set(plan.map(\.mode)).count >= 2)
    }

    @Test func aWordMissingFromTheCatalogIsSkippedRatherThanCrashing() {
        let plan = SessionPlanner.plan(cards: [seen("thiswordwasremoved", dueIn: -1)],
                                       catalog: Self.catalog, settings: settings(newLimit: 0), now: now)
        #expect(plan.isEmpty)
    }
}


@Suite struct WritingModeThresholdTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(reviews: Int) -> StudyCard {
        StudyCard(
            wordID: "abate",
            fsrs: FSRSCard(stability: 10, difficulty: 5, due: now.addingTimeInterval(-86_400),
                           lastReview: now.addingTimeInterval(-172_800), state: .review, step: nil),
            reviewCount: reviews
        )
    }

    private func mode(reviews: Int, writingAfter: Int, ai: Bool = true) -> StudyMode {
        SessionPlanner.plan(
            cards: [card(reviews: reviews)], catalog: Self.catalog,
            settings: SessionSettings(dailyNewWordLimit: 0, aiEnabled: ai,
                                      writingModeAfterReviews: writingAfter),
            now: now
        )[0].mode
    }

    @Test func theDefaultThresholdKeepsTheExistingLadder() {
        let settings = SessionSettings()
        #expect(settings.writingModeAfterReviews == 3)
        #expect(mode(reviews: 0, writingAfter: 3) == .multipleChoice)
        #expect(mode(reviews: 1, writingAfter: 3) == .reverseRecall)
        #expect(mode(reviews: 2, writingAfter: 3) == .spelling)
        #expect(mode(reviews: 3, writingAfter: 3) == .defineAndUse)
    }

    @Test func aThresholdOfZeroGoesStraightToWriting() {
        // For someone who wants the real exercise from the very first word.
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
        // The threshold is a preference; having no key is a hard constraint.
        #expect(mode(reviews: 0, writingAfter: 0, ai: false) != .defineAndUse)
        #expect(mode(reviews: 9, writingAfter: 0, ai: false) != .defineAndUse)
    }

    @Test(arguments: 0...6)
    func belowTheThresholdEveryModeIsLocallyGraded(reviews: Int) {
        let mode = mode(reviews: reviews, writingAfter: 99)
        #expect(StudyMode.locallyGraded.contains(mode))
        #expect(mode.needsAI == false)
    }
}
