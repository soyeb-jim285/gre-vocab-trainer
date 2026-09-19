import Foundation
import GRECore
import Observation
import SwiftData

/// Every card's scheduling state, keyed by word, held once for the whole app.
///
/// The word list and the progress screen both need mastery across the catalog.
/// Each used to build this dictionary inside its own `body`, so it was rebuilt
/// on every render, separate fetches of every record. A row does not need to
/// re-read the store because a search field gained focus.
///
/// Kept fresh by ``ReviewRecorder``, which is the only thing that writes cards.
@Observable
@MainActor
final class MasteryIndex {
    private(set) var cards: [String: StudyCard] = [:]
    /// Words the learner proved they already knew on first contact, before the
    /// app taught them anything. Kept here so Progress can separate what was
    /// learned from what was merely confirmed.
    private(set) var alreadyKnownIDs: Set<String> = []

    subscript(wordID: String) -> StudyCard? { cards[wordID] }

    func reload(from context: ModelContext) {
        cards = ReviewRecorder.cardsByID(in: context)
        alreadyKnownIDs = ReviewRecorder.alreadyKnownWordIDs(in: context)
    }
}
