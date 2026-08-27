import Foundation

/// Picks the next thing to study. Called after every answer with fresh card
/// state, so a word rated Again a minute ago is back in the queue immediately.
public enum SessionPlanner {

    /// How far ahead a learning card counts as "in flight".
    static let loadWindow: TimeInterval = 15 * 60
    /// How many just-shown words to keep out of the way.
    public static let repeatWindow = 3

    /// The next item, or nil when nothing is due and there are no new words
    /// left (pass `allowEarly` to review the weakest memory ahead of time).
    ///
    /// - Parameters:
    ///   - recentAccuracy: mean score (0...100) over the learner's recent answers;
    ///     drives how many new words they can juggle at once. Nil means no history.
    ///   - recentWordIDs: words just shown, newest last. Avoided unless nothing else qualifies.
    public static func next(
        cards: [StudyCard], catalog: WordCatalog, settings: SessionSettings,
        scheduler: FSRS, recentAccuracy: Double?, recentWordIDs: [String],
        allowEarly: Bool = false, now: Date
    ) -> SessionItem? {
        let recent = Set(recentWordIDs.suffix(repeatWindow))
        let known = cards.filter { catalog[$0.wordID] != nil }
        let fresh = known.filter { !recent.contains($0.wordID) }

        func item(_ card: StudyCard) -> SessionItem? {
            catalog[card.wordID].map {
                SessionItem(card: card, word: $0, mode: mode(for: card, word: $0, settings: settings))
            }
        }

        // 1. Due now, most likely forgotten first.
        if let due = mostAtRisk(fresh.filter { $0.fsrs.due <= now }, scheduler: scheduler, now: now) {
            return item(due)
        }

        // 2. Too many words half-learned: serve the soonest of them early rather
        //    than piling on another. The cap follows how the learner is doing.
        let inFlight = fresh.filter {
            $0.fsrs.state != .review && $0.fsrs.due <= now.addingTimeInterval(loadWindow)
        }
        if inFlight.count >= learningLoadCap(forAccuracy: recentAccuracy),
           let soonest = inFlight.min(by: { $0.fsrs.due < $1.fsrs.due }) {
            return item(soonest)
        }

        // 3. A new word from the current deck, then the decks after it.
        let studied = Set(known.map(\.wordID))
        if let word = nextNewWord(catalog: catalog, from: settings.currentDeckID, excluding: studied) {
            return item(StudyCard(wordID: word.id))
        }

        // 4. Only the just-shown words are due: repeating beats stalling.
        if let due = mostAtRisk(known.filter { $0.fsrs.due <= now }, scheduler: scheduler, now: now) {
            return item(due)
        }

        // 5. Caught up. Early review only on request.
        guard allowEarly else { return nil }
        let pool = fresh.isEmpty ? known : fresh
        return mostAtRisk(pool, scheduler: scheduler, now: now).flatMap(item)
    }

    /// When the next card falls due, for the caught-up screen.
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
    private static func nextNewWord(catalog: WordCatalog, from deckID: String?, excluding studied: Set<String>) -> Word? {
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

    /// Modes get harder as the memory gets stronger: recognise it, recall it,
    /// spell it, then actually use it.
    ///
    /// Writing is the exercise the app exists for, so how soon a word reaches it
    /// is a setting rather than a constant -- the default eases in, zero starts
    /// there. A lapsed word drops back to recognition whatever the setting.
    static func mode(for card: StudyCard, word: Word, settings: SessionSettings) -> StudyMode {
        // A forced mode drills one skill and overrides the ladder entirely --
        // except that it cannot conjure an API key, so writing without one
        // still falls back rather than stranding the learner on a locked mode,
        // and "which meaning" only exists for words that have two.
        if let forced = settings.forcedMode,
           !forced.needsAI || settings.aiEnabled,
           !forced.needsTrapWord || word.isTrap {
            return forced
        }
        if card.fsrs.state == .relearning { return .multipleChoice }

        // A trap word's whole difficulty is that the familiar meaning is the
        // wrong one, so meet it head on the second time the word comes round --
        // early enough to correct the assumption before it sets.
        if word.isTrap, card.reviewCount == 1 { return .senseInContext }

        if settings.aiEnabled, card.reviewCount >= settings.writingModeAfterReviews {
            return .defineAndUse
        }
        if card.fsrs.state != .review || Mastery(card: card) <= .learning { return .multipleChoice }

        // Recognise it, then use it in a sentence, then produce it, then spell it.
        let ladder: [StudyMode] = [.contextCloze, .reverseRecall, .spelling]
        return ladder[card.reviewCount % ladder.count]
    }
    // ponytail: FSRS parameters stay at the defaults. Fitting them to the
    // learner's own review log needs an optimiser and ~1000 reviews; add when
    // someone has that many.
}
