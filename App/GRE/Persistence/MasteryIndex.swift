import Foundation
import GRECore
import Observation
import SwiftData

/// Every card's scheduling state, keyed by word, held once for the whole app.
///
/// The decks grid, a deck's header and the progress screen all need mastery
/// across the catalog. Each used to build this dictionary inside its own `body`,
/// so it was rebuilt on every render, three separate fetches of every record. A
/// ring does not need to re-read the store because a search field gained focus.
///
/// Kept fresh by ``ReviewRecorder``, which is the only thing that writes cards.
@Observable
@MainActor
final class MasteryIndex {
    private(set) var cards: [String: StudyCard] = [:]

    subscript(wordID: String) -> StudyCard? { cards[wordID] }

    func reload(from context: ModelContext) {
        cards = ReviewRecorder.cardsByID(in: context)
    }

    func progress(for deck: Deck) -> DeckProgress {
        DeckProgress(deck: deck, cards: cards)
    }
}
