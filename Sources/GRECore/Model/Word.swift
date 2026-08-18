import Foundation

public enum PartOfSpeech: String, Codable, Sendable, CaseIterable {
    case noun, verb, adjective, adverb
}

/// How widely a word appears across the source GRE lists. Words on more lists
/// are taught first, so the ordering here is "teach this sooner".
public enum WordTier: String, Codable, Sendable, CaseIterable, Comparable {
    /// On three or more source lists.
    case core
    /// On exactly two.
    case common
    /// On one.
    case extended

    private var teachingPriority: Int {
        switch self {
        case .core: 0
        case .common: 1
        case .extended: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.teachingPriority < rhs.teachingPriority
    }
}

/// One WordNet sense of a word.
public struct Sense: Codable, Hashable, Sendable {
    public let pos: PartOfSpeech
    public let definition: String
    public let examples: [String]
    public let synonyms: [String]
    public let antonyms: [String]
}

/// A vocabulary entry as shipped in `words.json`.
public struct Word: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let word: String
    /// Empty when the word isn't in CMUdict; roughly one word in ten.
    public let ipa: String
    public let senses: [Sense]
    public let sourceLists: [String]
    public let listCount: Int
    public let tier: WordTier

    /// WordNet orders senses by frequency, so the first one is the sense a
    /// learner is most likely to meet.
    public var primarySense: Sense { senses[0] }
    public var primaryPartOfSpeech: PartOfSpeech { primarySense.pos }
}
