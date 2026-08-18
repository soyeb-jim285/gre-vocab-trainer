import Foundation

/// Builds the study queue: what to show, in what order, tested which way.
public enum SessionPlanner {

    public static func plan(
        cards: [StudyCard], catalog: WordCatalog, settings: SessionSettings, now: Date
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
            limit: settings.dailyNewWordLimit, settings: settings
        )

        // Reviews lead, so truncating here can only ever drop new words --
        // falling behind on words you already half-know is the worse failure.
        return Array((due + newItems).prefix(settings.sessionLength))
    }

    /// Fresh words, most widely-listed tier first, in a stable order.
    private static func introductions(
        catalog: WordCatalog, excluding studied: Set<String>, limit: Int, settings: SessionSettings
    ) -> [SessionItem] {
        guard limit > 0 else { return [] }
        var picked: [SessionItem] = []

        for tier in WordTier.allCases.sorted() {
            for word in catalog.words(inTier: tier) where !studied.contains(word.id) {
                let card = StudyCard(wordID: word.id, fsrs: FSRSCard(), reviewCount: 0)
                picked.append(SessionItem(card: card, word: word, mode: mode(for: card, settings: settings)))
                if picked.count == limit { return picked }
            }
        }
        return picked
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
        if settings.aiEnabled && card.reviewCount >= settings.writingModeAfterReviews {
            return .defineAndUse
        }
        let local = StudyMode.locallyGraded
        return local[card.reviewCount % local.count]
    }
}
