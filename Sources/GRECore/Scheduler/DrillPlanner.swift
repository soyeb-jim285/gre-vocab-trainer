import Foundation

/// Picks the exam questions for one run of the drill.
///
/// Questions are not scheduled the way words are. A word comes back when its
/// memory is due; a question is a way of exercising several words at once, and
/// the same question asked twice is worth much less the second time because the
/// sentence itself is remembered. So this weights by what the learner is
/// shakiest on and avoids what they have just seen, rather than tracking a
/// stability per question.
public enum DrillPlanner {

    /// - Parameters:
    ///   - recentItemIDs: questions answered recently, which drop to the back.
    ///     A remembered sentence tests recall of the sentence.
    ///   - allowUnmet: include questions on words never taught. Off by default:
    ///     a blank whose answer has never been met is a guess, and the drill is
    ///     meant to be the payoff for the words already learned.
    public static func session(
        from catalog: ItemCatalog, cards: [StudyCard], scheduler: FSRS,
        count: Int = 10, recentItemIDs: Set<String> = [], allowUnmet: Bool = false,
        seed: UInt64, now: Date
    ) -> [GREItem] {
        let byWord = Dictionary(cards.map { ($0.wordID, $0) }, uniquingKeysWith: { a, _ in a })
        var pool = catalog.items.filter { item in
            allowUnmet || item.testedWordIDs.allSatisfy { byWord[$0]?.isIntroduced == true }
        }
        guard !pool.isEmpty else { return [] }

        // Seen recently only matters while there is anything else to ask.
        let fresh = pool.filter { !recentItemIDs.contains($0.id) }
        if fresh.count >= count { pool = fresh }

        func need(_ item: GREItem) -> Double {
            // The weakest word in the question decides: a sentence is only as
            // answerable as the answer the learner is least sure of.
            let scores = item.testedWordIDs.map { id -> Double in
                guard let card = byWord[id], card.isIntroduced else { return 1 }
                return 1 - scheduler.retrievability(card.fsrs, at: now)
            }
            return (scores.min() ?? 1) + 0.05
        }

        var rng = SeededGenerator(seed: seed)
        var chosen: [GREItem] = []
        // Weighted sampling without replacement. ponytail: O(n·k) scan, and n is
        // a few hundred questions.
        while chosen.count < count, !pool.isEmpty {
            let weights = pool.map(need)
            var pick = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
            var index = 0
            while index < weights.count - 1, pick >= weights[index] {
                pick -= weights[index]
                index += 1
            }
            chosen.append(pool.remove(at: index))
        }
        return chosen
    }
}
