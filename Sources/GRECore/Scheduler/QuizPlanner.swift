import Foundation

/// Builds a fixed test over words the learner has already studied. Answers
/// still go through the scheduler -- a test is evidence like any review.
public enum QuizPlanner {

    /// Fewer than this and a percentage is noise.
    public static let minimumWords = 5

    /// Every studied word in the deck, shuffled, local modes only.
    public static func deckTest(deck: Deck, cards: [StudyCard], catalog: WordCatalog, seed: UInt64) -> [SessionItem] {
        let inDeck = Set(deck.wordIDs)
        let studied = cards.filter { $0.reviewCount > 0 && inDeck.contains($0.wordID) }
        return items(from: studied, catalog: catalog, seed: seed)
    }

    /// `count` studied words, weighted toward the ones most likely forgotten.
    public static func globalTest(
        cards: [StudyCard], catalog: WordCatalog, scheduler: FSRS,
        count: Int = 20, seed: UInt64, now: Date
    ) -> [SessionItem] {
        var pool = cards.filter { $0.reviewCount > 0 && catalog[$0.wordID] != nil }
        guard pool.count >= minimumWords else { return [] }
        var rng = SeededGenerator(seed: seed)
        var chosen: [StudyCard] = []
        // Weighted sampling without replacement. ponytail: O(n·k) scan; fine for
        // a few thousand cards and k = 20.
        while chosen.count < count, !pool.isEmpty {
            let weights = pool.map { 1 - scheduler.retrievability($0.fsrs, at: now) + 0.05 }
            var pick = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
            var index = 0
            while index < weights.count - 1, pick >= weights[index] {
                pick -= weights[index]
                index += 1
            }
            chosen.append(pool.remove(at: index))
        }
        return items(from: chosen, catalog: catalog, seed: seed)
    }

    private static func items(from cards: [StudyCard], catalog: WordCatalog, seed: UInt64) -> [SessionItem] {
        guard cards.count >= minimumWords else { return [] }
        var rng = SeededGenerator(seed: seed)
        let local = StudyMode.locallyGraded
        return cards.shuffled(using: &rng).enumerated().compactMap { n, card in
            catalog[card.wordID].map { SessionItem(card: card, word: $0, mode: local[n % local.count]) }
        }
    }
}
