import Foundation
import GRECore
import SwiftData

/// Reading and writing what this learner has actually got wrong.
///
/// A separate store from `ReviewRecord` because a review says a score and this
/// says a belief. Scores age out of usefulness; a wrong idea does not, and the
/// drill that clears it needs to know which one it is chasing.
enum Misconceptions {

    static func record(
        wordID: String, kind: MisconceptionKind, text: String,
        at: Date = .now, in context: ModelContext
    ) {
        guard !text.isEmpty else { return }
        context.insert(MisconceptionRecord(wordID: wordID, kind: kind, text: text, at: at))
        try? context.save()
    }

    /// The neighbours this learner has picked instead of the word.
    ///
    /// Fed to the confusion drill so it returns to the pairs that have already
    /// caused trouble rather than sampling evenly across pairs that might.
    static func confusedPartners(for wordID: String, in context: ModelContext) -> Set<String> {
        let kind = MisconceptionKind.confusion.rawValue
        let descriptor = FetchDescriptor<MisconceptionRecord>(
            predicate: #Predicate { $0.wordID == wordID && $0.kindRaw == kind }
        )
        return Set((try? context.fetch(descriptor))?.map(\.text) ?? [])
    }

    /// Everything still on record for a word, newest first, for the word's
    /// detail screen.
    static func all(for wordID: String, in context: ModelContext) -> [MisconceptionRecord] {
        let descriptor = FetchDescriptor<MisconceptionRecord>(
            predicate: #Predicate { $0.wordID == wordID },
            sortBy: [SortDescriptor(\.at, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
