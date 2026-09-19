import Foundation

/// Which word to serve next. Which question to ask about it is ``Curriculum``.
///
/// Called after every answer against freshly read state, so a word rated Again a
/// minute ago is back in the queue immediately.
public enum SessionQueue {

    /// How far ahead a learning card counts as "in flight".
    static let loadWindow: TimeInterval = 15 * 60
    /// How many just-shown words to keep out of the way.
    public static let repeatWindow = 3

    /// The next card, or nil when nothing is due and no new word is allowed.
    ///
    /// - Parameters:
    ///   - newWordsAllowed: how many first meetings the day still has room for.
    ///     Zero means the learner has met their quota; reviews continue, but the
    ///     pile they will owe tomorrow stops growing.
    ///   - recentAccuracy: mean score (0...100) over recent answers; drives how
    ///     many half-learned words they can juggle. Nil means no history.
    ///   - recentWordIDs: words just shown, newest last. Avoided unless nothing
    ///     else qualifies.
    ///   - allowEarly: review the weakest memory ahead of schedule rather than
    ///     returning nil.
    ///   - belowCriterion: words met today that have not yet been answered
    ///     correctly often enough; see ``LearningCriterion``. They come back
    ///     before any new word does.
    public static func nextCard(
        cards: [StudyCard], catalog: WordCatalog, currentDeckID: String?,
        newWordsAllowed: Int, scheduler: FSRS, recentAccuracy: Double?,
        recentWordIDs: [String], allowEarly: Bool = false,
        belowCriterion: Set<String> = [], now: Date
    ) -> StudyCard? {
        let recent = Set(recentWordIDs.suffix(repeatWindow))
        let known = cards.filter { catalog[$0.wordID] != nil }
        let fresh = known.filter { !recent.contains($0.wordID) }

        // 1. Due now, most likely forgotten first.
        if let due = mostAtRisk(fresh.filter { $0.fsrs.due <= now }, scheduler: scheduler, now: now) {
            return due
        }

        // 2. Too many words half-learned: serve the soonest of them early rather
        //    than piling on another. The cap follows how the learner is doing.
        let inFlight = fresh.filter {
            $0.fsrs.state != .review && $0.fsrs.due <= now.addingTimeInterval(loadWindow)
        }
        if inFlight.count >= learningLoadCap(forAccuracy: recentAccuracy),
           let soonest = inFlight.min(by: { $0.fsrs.due < $1.fsrs.due }) {
            return soonest
        }

        // 3. A word met today that has not yet been got right enough times.
        //    Finishing today's words beats starting tomorrow's: retrieval to a
        //    criterion is the strongest lever there is, and a word left at one
        //    lucky answer is mostly forgotten by morning.
        if let owed = fresh
            .filter({ belowCriterion.contains($0.wordID) })
            .min(by: { $0.fsrs.due < $1.fsrs.due }) {
            return owed
        }

        // 4. A new word from the current deck, then the decks after it.
        let studied = Set(known.map(\.wordID))
        if newWordsAllowed > 0,
           let word = nextNewWord(catalog: catalog, from: currentDeckID, excluding: studied) {
            return StudyCard(wordID: word.id)
        }

        // 5. Only the just-shown words are due: repeating beats stalling.
        if let due = mostAtRisk(
            known.filter { $0.fsrs.due <= now || belowCriterion.contains($0.wordID) },
            scheduler: scheduler, now: now
        ) {
            return due
        }

        // 6. Caught up. Early review only on request.
        guard allowEarly else { return nil }
        let pool = fresh.isEmpty ? known : fresh
        return mostAtRisk(pool, scheduler: scheduler, now: now)
    }

    /// When the next card falls due, for a day that is finished.
    public static func nextDue(cards: [StudyCard], now: Date) -> Date? {
        cards.map(\.fsrs.due).filter { $0 > now }.min()
    }

    /// How many learning/relearning cards may be in flight before new words pause.
    public static func learningLoadCap(forAccuracy accuracy: Double?) -> Int {
        switch accuracy {
        case .some(..<60): 4
        case .some(85...): 12
        default: 8
        }
    }

    /// Lowest retrievability first; relearning, then earlier due, break ties.
    private static func mostAtRisk(_ cards: [StudyCard], scheduler: FSRS, now: Date) -> StudyCard? {
        cards.min { a, b in
            let ra = scheduler.retrievability(a.fsrs, at: now)
            let rb = scheduler.retrievability(b.fsrs, at: now)
            if ra != rb { return ra < rb }
            if (a.fsrs.state == .relearning) != (b.fsrs.state == .relearning) {
                return a.fsrs.state == .relearning
            }
            return a.fsrs.due < b.fsrs.due
        }
    }

    /// First unstudied word from the chosen deck onward, wrapping round so a
    /// learner who jumped ahead still gets the decks they skipped.
    private static func nextNewWord(
        catalog: WordCatalog, from deckID: String?, excluding studied: Set<String>
    ) -> Word? {
        let decks = catalog.decks
        guard !decks.isEmpty else { return nil }
        let start = decks.firstIndex { $0.id == deckID } ?? 0
        for offset in 0..<decks.count {
            let deck = decks[(start + offset) % decks.count]
            if let id = deck.wordIDs.first(where: { !studied.contains($0) }) {
                return catalog[id]
            }
        }
        return nil
    }
}
