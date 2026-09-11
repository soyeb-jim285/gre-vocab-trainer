import Foundation

/// Builds a fixed test over words the learner has already studied. Answers
/// still go through the scheduler -- a test is evidence like any review.
public enum QuizPlanner {

    /// Fewer than this and a percentage is noise.
    public static let minimumWords = 5

    /// The day's fixed challenge: the same set however many times it is opened,
    /// a new one tomorrow.
    ///
    /// Seeded from the day rather than the clock so the challenge is a thing you
    /// either did or did not do today, which is what makes it worth coming back
    /// to. Re-rolling it on every open would make it just another session.
    public static func dailyChallenge(
        cards: [StudyCard], catalog: WordCatalog, scheduler: FSRS,
        dayStart: Date, count: Int = 20, now: Date
    ) -> [SessionItem] {
        globalTest(cards: cards, catalog: catalog, scheduler: scheduler, count: count,
                   seed: UInt64(bitPattern: Int64(dayStart.timeIntervalSince1970.rounded())),
                   now: now)
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
        // "Which meaning" needs a trap word, so it is not part of the rotation;
        // a test should ask every word the same kind of question.
        let modes: [StudyMode] = [.multipleChoice, .contextCloze, .reverseRecall, .spelling]
        return cards.shuffled(using: &rng).enumerated().compactMap { n, card in
            catalog[card.wordID].map { SessionItem(card: card, word: $0, mode: modes[n % modes.count]) }
        }
    }
}
