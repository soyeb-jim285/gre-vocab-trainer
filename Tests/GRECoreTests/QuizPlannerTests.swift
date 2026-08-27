import Foundation
import Testing
@testable import GRECore

@Suite struct QuizPlannerTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let fsrs = FSRS(enableFuzzing: false)

    private func studied(_ id: String, stability: Double = 10, daysAgo: Double = 1) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: stability, difficulty: 5, due: now.addingTimeInterval(5 * 86_400),
                           lastReview: now.addingTimeInterval(-daysAgo * 86_400), state: .review, step: nil),
            reviewCount: 2
        )
    }

    private var deck: Deck { Self.catalog.decks[0] }

    @Test func aDeckTestCoversEveryStudiedWordOnce() {
        let cards = deck.wordIDs.prefix(9).map { studied($0) }
        let items = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 1)
        #expect(Set(items.map(\.card.wordID)) == Set(cards.map(\.wordID)))
        #expect(items.count == 9)
    }

    @Test func unstudiedAndForeignWordsAreLeftOut() {
        let cards = deck.wordIDs.prefix(6).map { studied($0) } + [studied("laconic")]
        let items = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 1)
        #expect(items.count == 6)
        #expect(items.allSatisfy { deck.wordIDs.contains($0.card.wordID) })
    }

    @Test func fewerThanFiveStudiedWordsIsNoTest() {
        let cards = deck.wordIDs.prefix(4).map { studied($0) }
        #expect(QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 1).isEmpty)
        let five = deck.wordIDs.prefix(5).map { studied($0) }
        #expect(QuizPlanner.deckTest(deck: deck, cards: five, catalog: Self.catalog, seed: 1).count == 5)
    }

    @Test func onlyLocalModesAreUsedAndTheyAreMixed() {
        let cards = deck.wordIDs.map { studied($0) }
        let items = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 3)
        #expect(items.allSatisfy { StudyMode.locallyGraded.contains($0.mode) })
        #expect(Set(items.map(\.mode)).count == 3)
    }

    @Test func theSameSeedGivesTheSameOrderAndADifferentSeedShufflesIt() {
        let cards = deck.wordIDs.map { studied($0) }
        let a = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 7).map(\.card.wordID)
        let b = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 7).map(\.card.wordID)
        let c = QuizPlanner.deckTest(deck: deck, cards: cards, catalog: Self.catalog, seed: 8).map(\.card.wordID)
        #expect(a == b)
        #expect(a != c)
        #expect(a != deck.wordIDs, "should not come out in deck order")
    }

    @Test func aGlobalTestSamplesTheRequestedCountFromStudiedWords() {
        let cards = Self.catalog.words.prefix(60).map { studied($0.id) }
        let items = QuizPlanner.globalTest(cards: cards, catalog: Self.catalog, scheduler: fsrs, count: 20, seed: 1, now: now)
        #expect(items.count == 20)
        #expect(Set(items.map(\.card.wordID)).count == 20)
    }

    @Test func aGlobalTestFavoursTheWordsMostLikelyForgotten() {
        // 40 rock-solid words and 10 shaky ones; the shaky ones should dominate.
        let solid = Self.catalog.words.prefix(40).map { studied($0.id, stability: 400, daysAgo: 0) }
        let shaky = Self.catalog.words.dropFirst(40).prefix(10).map { studied($0.id, stability: 0.5, daysAgo: 10) }
        var hits = 0
        for seed in 0..<20 {
            let items = QuizPlanner.globalTest(cards: solid + shaky, catalog: Self.catalog, scheduler: fsrs,
                                               count: 10, seed: UInt64(seed), now: now)
            hits += items.filter { shaky.map(\.wordID).contains($0.card.wordID) }.count
        }
        // Uniform sampling would give ~2 of 10 per run (40 of 200); weighting must beat that clearly.
        #expect(hits > 100, "only \(hits)/200 picks were shaky words")
    }

    @Test func aGlobalTestWithTooFewWordsIsEmpty() {
        let cards = Self.catalog.words.prefix(4).map { studied($0.id) }
        #expect(QuizPlanner.globalTest(cards: cards, catalog: Self.catalog, scheduler: fsrs, seed: 1, now: now).isEmpty)
    }
}
