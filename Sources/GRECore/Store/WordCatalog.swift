import Foundation

/// The bundled vocabulary, indexed for the lookups the app actually makes.
public struct WordCatalog: Sendable {

    public enum LoadError: Error, CustomStringConvertible {
        case resourceMissing
        case empty

        public var description: String {
            switch self {
            case .resourceMissing: "words.json is missing from the GRECore bundle"
            case .empty: "words.json decoded to zero words"
            }
        }
    }

    public static let empty = WordCatalog(words: [])

    public let words: [Word]
    private let byID: [String: Word]
    private let byPartOfSpeech: [PartOfSpeech: [Word]]

    /// Non-throwing: an empty catalog is a legitimate value (it is the
    /// placeholder the app holds before the dataset finishes loading). Rejecting
    /// an empty *dataset* is `bundled()`'s job, where it means a broken build.
    public init(words: [Word]) {
        self.words = words
        self.byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.byPartOfSpeech = Dictionary(grouping: words, by: \.primaryPartOfSpeech)
    }

    /// Load the dataset shipped inside GRECore.
    public static func bundled() throws -> WordCatalog {
        guard let url = Bundle.module.url(forResource: "words", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        let words = try JSONDecoder().decode([Word].self, from: Data(contentsOf: url))
        guard !words.isEmpty else { throw LoadError.empty }
        return WordCatalog(words: words)
    }

    public subscript(id: String) -> Word? { byID[id] }

    /// Words whose *primary* sense has this part of speech -- the grouping
    /// multiple-choice distractors are drawn from.
    public func words(withPartOfSpeech pos: PartOfSpeech) -> [Word] {
        byPartOfSpeech[pos] ?? []
    }

    public func words(inTier tier: WordTier) -> [Word] {
        words.filter { $0.tier == tier }
    }
}
