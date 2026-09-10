import Foundation
import Testing
@testable import GRECore

/// Which *word* the planner serves next. Which question it asks about that
/// word lives in `ModeLadderTests`.
@Suite struct SessionPlannerTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let fsrs = FSRS(enableFuzzing: false)

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

    private func next(
        _ cards: [StudyCard], settings: SessionSettings = SessionSettings(aiEnabled: false),
        accuracy: Double? = nil, recent: [String] = [], early: Bool = false
    ) -> SessionItem? {
        SessionPlanner.next(
            cards: cards, catalog: Self.catalog, settings: settings, scheduler: fsrs,
            recentAccuracy: accuracy, recentWordIDs: recent, allowEarly: early, now: now
        )
    }

    // MARK: - Due reviews first

    @Test func aDueCardBeatsANewWord() {
        #expect(next([seen("abate", dueIn: -1)])?.card.wordID == "abate")
    }

    @Test func aCardDueAtThisExactMomentIsDue() {
        #expect(next([seen("abate", dueIn: 0)])?.card.wordID == "abate")
    }

    @Test func theMostLikelyForgottenCardComesFirst() {
        // Same overdue-ness; the weaker memory (lower stability, older review) is at more risk.
        let strong = seen("abate", dueIn: -1, stability: 60, lastReviewDaysAgo: 30)
        let weak = seen("laconic", dueIn: -1, stability: 5, lastReviewDaysAgo: 30)
        #expect(next([strong, weak])?.card.wordID == "laconic")
    }

    @Test func relearningBreaksTiesAheadOfReview() {
        let review = seen("abate", dueIn: -1, stability: 5, lastReviewDaysAgo: 3)
        let lapsed = seen("laconic", dueIn: -1, stability: 5, lastReviewDaysAgo: 3, state: .relearning)
        #expect(next([review, lapsed])?.card.wordID == "laconic")
    }

    @Test func aWordMissingFromTheCatalogIsSkippedRatherThanCrashing() {
        let item = next([seen("thiswordwasremoved", dueIn: -1), seen("abate", dueIn: -1)])
        #expect(item?.card.wordID == "abate")
    }

    // MARK: - Anti-repeat

    @Test func aJustShownWordIsNotShownAgainWhileOthersWait() {
        let cards = [seen("abate", dueIn: -2), seen("laconic", dueIn: -1)]
        #expect(next(cards, recent: ["abate"])?.card.wordID == "laconic")
    }

    @Test func aJustShownWordComesBackWhenNothingElseQualifies() {
        // Rated Again a minute ago, and nothing else is due: better to repeat than to stall.
        let cards = [learning("abate", dueInMinutes: 0)]
        let item = next(cards, recent: ["abate"])
        // A new word from the deck is still preferred over repeating...
        #expect(item?.card.reviewCount == 0)
        // ...but with the whole catalog studied, the repeat wins over nothing.
        let everything = Self.catalog.words.filter { $0.id != "abate" }.map { seen($0.id, dueIn: 5) } + cards
        #expect(next(everything, recent: ["abate"])?.card.wordID == "abate")
    }

    // MARK: - Learning-load cap

    @Test func theCapFollowsRecentAccuracy() {
        #expect(SessionPlanner.learningLoadCap(forAccuracy: nil) == 8)
        #expect(SessionPlanner.learningLoadCap(forAccuracy: 59) == 4)
        #expect(SessionPlanner.learningLoadCap(forAccuracy: 60) == 8)
        #expect(SessionPlanner.learningLoadCap(forAccuracy: 84.9) == 8)
        #expect(SessionPlanner.learningLoadCap(forAccuracy: 85) == 12)
    }

    @Test func atTheCapAnUpcomingLearningCardIsServedEarlyInsteadOfANewWord() {
        let inFlight = (0..<8).map { learning(Self.catalog.words[$0].id, dueInMinutes: Double($0) + 2) }
        let item = next(inFlight)
        #expect(item?.card.reviewCount == 1)
        #expect(item?.card.wordID == Self.catalog.words[0].id, "soonest due should be served")
    }

    @Test func belowTheCapANewWordIsIntroduced() {
        let inFlight = (0..<7).map { learning(Self.catalog.words[$0].id, dueInMinutes: Double($0) + 2) }
        #expect(next(inFlight)?.card.reviewCount == 0)
    }

    @Test func aStrugglingLearnerHitsTheCapSooner() {
        let inFlight = (0..<4).map { learning(Self.catalog.words[$0].id, dueInMinutes: Double($0) + 2) }
        #expect(next(inFlight, accuracy: 40)?.card.reviewCount == 1)
        #expect(next(inFlight, accuracy: 90)?.card.reviewCount == 0)
    }

    @Test func learningCardsDueBeyondTheWindowDoNotCountTowardTheCap() {
        let later = (0..<12).map { learning(Self.catalog.words[$0].id, dueInMinutes: 30) }
        #expect(next(later)?.card.reviewCount == 0)
    }

    // MARK: - New words from the current deck

    @Test func withNoDeckChosenNewWordsComeFromTheFirstDeck() throws {
        let item = try #require(next([]))
        #expect(item.card.reviewCount == 0)
        #expect(item.card.wordID == Self.catalog.decks[0].wordIDs[0])
        #expect(item.mode == .multipleChoice)
    }

    @Test func newWordsComeFromTheChosenDeckInOrder() throws {
        let deck = try #require(Self.catalog.deck(id: "common-3"))
        let settings = SessionSettings(aiEnabled: false, currentDeckID: deck.id)
        #expect(next([], settings: settings)?.card.wordID == deck.wordIDs[0])
        let studied = deck.wordIDs.prefix(2).map { seen($0, dueIn: 5) }
        #expect(next(studied, settings: settings)?.card.wordID == deck.wordIDs[2])
    }

    @Test func anExhaustedDeckAdvancesToTheNextOne() throws {
        let deck = try #require(Self.catalog.deck(id: "core-1"))
        let nextDeck = try #require(Self.catalog.deck(id: "core-2"))
        let studied = deck.wordIDs.map { seen($0, dueIn: 5) }
        let item = next(studied, settings: SessionSettings(aiEnabled: false, currentDeckID: deck.id))
        #expect(item?.card.wordID == nextDeck.wordIDs[0])
    }

    @Test func theLastDeckWrapsAroundToUnstudiedEarlierDecks() throws {
        let last = try #require(Self.catalog.decks.last)
        let studied = last.wordIDs.map { seen($0, dueIn: 5) }
        let item = next(studied, settings: SessionSettings(aiEnabled: false, currentDeckID: last.id))
        #expect(item?.card.wordID == Self.catalog.decks[0].wordIDs[0])
    }

    @Test func anUnknownDeckIDFallsBackToTheFirstDeck() {
        let item = next([], settings: SessionSettings(aiEnabled: false, currentDeckID: "gone-7"))
        #expect(item?.card.wordID == Self.catalog.decks[0].wordIDs[0])
    }

    // MARK: - Caught up

    @Test func nothingDueAndNothingNewReturnsNil() {
        let everything = Self.catalog.words.map { seen($0.id, dueIn: 5) }
        #expect(next(everything) == nil)
    }

    @Test func allowEarlyServesTheWeakestMemoryWhenCaughtUp() {
        var everything = Self.catalog.words.map { seen($0.id, dueIn: 5, stability: 100) }
        everything[7] = seen(everything[7].wordID, dueIn: 5, stability: 3, lastReviewDaysAgo: 2)
        let item = next(everything, early: true)
        #expect(item?.card.wordID == everything[7].wordID)
    }

    @Test func nextDueIsTheSoonestFutureDueDate() {
        let cards = [seen("abate", dueIn: 3), seen("laconic", dueIn: 1), seen("acumen", dueIn: -1)]
        #expect(SessionPlanner.nextDue(cards: cards, now: now) == now.addingTimeInterval(86_400))
        #expect(SessionPlanner.nextDue(cards: [], now: now) == nil)
    }
}
