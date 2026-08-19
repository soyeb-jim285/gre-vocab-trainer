import Foundation

/// Builds the study queue: what to show, in what order, tested which way.
public enum SessionPlanner {

    /// - Parameter recentAccuracy: mean score (0...100) over the learner's recent
    ///   answers, used only by ``NewWordOrder/adaptive``. Nil means no history.
    public static func plan(
        cards: [StudyCard], catalog: WordCatalog, settings: SessionSettings,
        recentAccuracy: Double? = nil, now: Date
    ) -> [SessionItem] {
        let studied = Set(cards.map(\.wordID))

        // Due reviews first, most overdue leading -- forgetting is the thing
        // worth spending the session on.
        let due = cards
            .filter { $0.fsrs.due <= now }
            .sorted { $0.fsrs.due < $1.fsrs.due }
            .compactMap { card in
                catalog[card.wordID].map { SessionItem(card: card, word: $0, mode: mode(for: card, settings: settings)) }
            }

        let newItems = introductions(
            catalog: catalog, excluding: studied,
            limit: settings.dailyNewWordLimit, settings: settings,
            recentAccuracy: recentAccuracy
        )

        // Reviews lead, so truncating here can only ever drop new words --
        // falling behind on words you already half-know is the worse failure.
        return Array((due + newItems).prefix(settings.sessionLength))
    }

    /// Fresh words, in whichever order the learner asked for, stable across calls.
    private static func introductions(
        catalog: WordCatalog, excluding studied: Set<String>, limit: Int,
        settings: SessionSettings, recentAccuracy: Double?
    ) -> [SessionItem] {
        guard limit > 0 else { return [] }

        let candidates: [Word]
        switch settings.newWordOrder {
        case .mostTested:
            // Tier first, which is exam value rather than ease.
            candidates = catalog.words.sorted {
                $0.tier != $1.tier ? $0.tier < $1.tier : $0.id < $1.id
            }
        case .easiestFirst:
            candidates = byRisingDifficulty(catalog.words)
        case .adaptive:
            // Still easiest-first; the ceiling only decides how far up to reach.
            let ceiling = SessionSettings.difficultyCeiling(forAccuracy: recentAccuracy)
            candidates = byRisingDifficulty(catalog.words.filter { $0.difficulty <= ceiling })
        }

        return candidates
            .lazy
            .filter { !studied.contains($0.id) }
            .prefix(limit)
            .map { word in
                let card = StudyCard(wordID: word.id, fsrs: FSRSCard(), reviewCount: 0)
                return SessionItem(card: card, word: word, mode: mode(for: card, settings: settings))
            }
    }

    /// Most common in ordinary English first; id breaks ties so the order is stable.
    private static func byRisingDifficulty(_ words: [Word]) -> [Word] {
        words.sorted { $0.zipf != $1.zipf ? $0.zipf > $1.zipf : $0.id < $1.id }
    }

    /// Modes get harder as a word becomes familiar: recognise it, recall it,
    /// spell it, then actually use it.
    ///
    /// Writing is the exercise the app exists for, so how soon a word reaches it
    /// is a setting rather than a constant -- the default eases in, zero starts
    /// there. Below the threshold (or with no API key, which is a hard
    /// constraint rather than a preference) words cycle through the local modes.
    ///
    /// ponytail: progression keys off review count alone. If lapsed words turn
    /// out to need an easier re-entry, branch on `fsrs.state == .relearning` here.
    static func mode(for card: StudyCard, settings: SessionSettings) -> StudyMode {
        // A forced mode drills one skill and overrides the ladder entirely --
        // except that it cannot conjure an API key, so writing without one
        // still falls back rather than stranding the learner on a locked mode.
        if let forced = settings.forcedMode, !forced.needsAI || settings.aiEnabled {
            return forced
        }
        if settings.forcedMode == nil,
           settings.aiEnabled, card.reviewCount >= settings.writingModeAfterReviews {
            return .defineAndUse
        }
        let local = StudyMode.locallyGraded
        return local[card.reviewCount % local.count]
    }
}
