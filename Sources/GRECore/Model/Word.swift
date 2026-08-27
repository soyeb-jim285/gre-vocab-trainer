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

/// How hard a word is likely to be, from how often it appears in ordinary
/// English (wordfreq's Zipf scale).
///
/// This is a different axis from ``WordTier``, and the two run *opposite* ways:
/// words carried by many prep lists have a slightly lower median frequency,
/// because the lists compete on obscurity. Tier answers "how likely is this to
/// be on the test"; difficulty answers "how likely is the learner to know it".
public enum WordDifficulty: String, Codable, Sendable, CaseIterable, Comparable {
    case familiar   // zipf >= 3.5
    case moderate   // zipf >= 2.9
    case hard       // zipf >= 2.2
    case rare       // below that

    private var order: Int {
        switch self {
        case .familiar: 0
        case .moderate: 1
        case .hard: 2
        case .rare: 3
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

/// One WordNet sense of a word.
public struct Sense: Codable, Hashable, Sendable {
    public let pos: PartOfSpeech
    public let definition: String
    public let examples: [String]
    public let synonyms: [String]
    public let antonyms: [String]
}

/// The sense the GRE actually tests, written for a learner rather than a
/// lexicographer: plain-English definition, exam-register synonyms, and two
/// example sentences built to stick.
///
/// WordNet supplies ``Word/senses`` -- accurate, exhaustive, and ordered for
/// lexicographers, which is how "court" led with a tennis player. This is the
/// one meaning worth learning first.
public struct GRESense: Codable, Hashable, Sendable {
    public let pos: PartOfSpeech
    public let definition: String
    public let synonyms: [String]
    public let antonyms: [String]
    /// One or two; the first is the plainer of them.
    public let sentences: [String]
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
    /// Zipf frequency in ordinary English; higher means more familiar.
    public let zipf: Double
    public let difficulty: WordDifficulty
    /// Present for every word in the shipped dataset; optional so a
    /// hand-built ``Word`` in a test or preview need not supply one.
    public let gre: GRESense?

    /// WordNet orders senses by frequency, so the first one is the sense a
    /// learner is most likely to meet.
    public var primarySense: Sense { senses[0] }

    /// What to teach, grade, and show: the GRE sense where there is one,
    /// WordNet otherwise.
    public var teachingDefinition: String { gre?.definition ?? primarySense.definition }
    public var primaryPartOfSpeech: PartOfSpeech { gre?.pos ?? primarySense.pos }
}
