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
    /// Two per word; the first is the plainer of them.
    public let sentences: [String]
    /// Those sentences with the word blanked out, for fill-in-the-blank.
    /// Usually two; occasionally one, where the other sentence is about the
    /// word rather than a use of it.
    public let cloze: [String]
    /// Three hand-written wrong definitions for the multiple-choice mode.
    ///
    /// Near misses, not other words' meanings: "to postpone deliberately" for
    /// *abate*, not "a large sea mammal". Three unrelated definitions can be
    /// eliminated without knowing the word, which is the wrong lesson.
    public let distractors: [String]
}

/// A wrong answer learners actually give for a word, with the misunderstanding
/// it reveals.
///
/// The label is the point. "Dishonest" for *equivocal* is not merely wrong, it
/// is a learner confusing deliberate ambiguity with lying, and a grader that
/// can name that can correct it instead of marking a cross.
public struct IncorrectAssociation: Codable, Hashable, Sendable {
    public let answer: String
    public let misconception: String

    public init(answer: String, misconception: String) {
        self.answer = answer
        self.misconception = misconception
    }
}

/// What a grader needs in order to judge an answer against this word rather
/// than against the model's memory of it.
///
/// Every field here exists to make one decision cheaper or more reliable:
/// ``acceptedConcepts`` keeps grading strict about meaning and tolerant about
/// wording, ``incorrectAssociations`` makes confidently-wrong detectable,
/// ``requiredNuance`` decides the 2 versus 3 boundary, and ``mentalHook``
/// replaces a per-word network call at teaching time.
public struct Grounding: Codable, Hashable, Sendable {
    /// Four to eight short paraphrases that score full marks.
    public let acceptedConcepts: [String]
    /// Two to four wrong answers, each labelled with what it reveals.
    public let incorrectAssociations: [IncorrectAssociation]
    /// The one element a precise answer must contain.
    public let requiredNuance: String
    /// One short memorable hook, shown when teaching.
    public let mentalHook: String
    /// The first rung of the hint ladder. Never contains the word or its stem.
    public let semanticHint: String

    private enum CodingKeys: String, CodingKey {
        case acceptedConcepts = "accepted_concepts"
        case incorrectAssociations = "incorrect_associations"
        case requiredNuance = "required_nuance"
        case mentalHook = "mental_hook"
        case semanticHint = "semantic_hint"
    }

    public init(acceptedConcepts: [String],
                incorrectAssociations: [IncorrectAssociation],
                requiredNuance: String,
                mentalHook: String,
                semanticHint: String) {
        self.acceptedConcepts = acceptedConcepts
        self.incorrectAssociations = incorrectAssociations
        self.requiredNuance = requiredNuance
        self.mentalHook = mentalHook
        self.semanticHint = semanticHint
    }
}

/// Another word this one is mixed up with, and the line that tells them apart.
///
/// Stored on both halves of the pair, because either word can be the one on
/// screen when the confusion surfaces.
public struct ConfusionPair: Codable, Hashable, Sendable {
    /// The id of the word confused with this one.
    public let with: String
    /// One sentence naming both words and what separates them.
    public let distinction: String

    public init(with: String, distinction: String) {
        self.with = with
        self.distinction = distinction
    }
}

/// Whether the tested sense praises, blames, or does neither.
///
/// The cheapest thing to know about a word, and often enough: a Text Completion
/// blank is usually settled by whether the sentence needs something good or
/// something bad before any particular meaning matters.
public enum Charge: String, Codable, Sendable, CaseIterable {
    case positive, negative, neutral

    public var label: String {
        switch self {
        case .positive: "Positive"
        case .negative: "Negative"
        case .neutral: "Neutral"
        }
    }
}

/// Where a word came from, told so that its meaning can be worked out rather
/// than memorised.
public struct Etymology: Codable, Hashable, Sendable {
    public struct Part: Codable, Hashable, Sendable {
        /// The morpheme as it is usually cited: "sub-", "tela".
        public let piece: String
        /// The language it came from.
        public let origin: String
        public let meaning: String

        public init(piece: String, origin: String, meaning: String) {
            self.piece = piece
            self.origin = origin
            self.meaning = meaning
        }
    }

    public enum Confidence: String, Codable, Sendable {
        case high, medium, low
    }

    public let parts: [Part]
    /// What the parts literally say.
    public let literal: String
    /// How the literal picture became the tested meaning.
    public let path: String
    /// Everyday words sharing a root, which the learner already knows.
    public let cousins: [String]
    public let confidence: Confidence
    /// Whether the parts genuinely point at the tested meaning.
    ///
    /// When they do not, asking the learner to guess from them teaches the
    /// wrong answer, so the teaching card tells the history as a story instead.
    public let transparent: Bool

    public init(
        parts: [Part], literal: String, path: String, cousins: [String],
        confidence: Confidence, transparent: Bool
    ) {
        self.parts = parts
        self.literal = literal
        self.path = path
        self.cousins = cousins
        self.confidence = confidence
        self.transparent = transparent
    }

    /// Worth a guess before the answer: parts that mean something, a story that
    /// is attested, and a meaning they actually lead to.
    public var invitesGuess: Bool {
        transparent && confidence != .low && !parts.isEmpty
    }
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
    /// Zipf frequency of the word *form* in ordinary English. Kept for reference
    /// and tie-breaking; ``rating`` is what orders the teaching sequence.
    public let zipf: Double
    public let difficulty: WordDifficulty
    /// Present for every word in the shipped dataset; optional so a
    /// hand-built ``Word`` in a test or preview need not supply one.
    public let gre: GRESense?
    /// True when the everyday meaning of this word form is *not* the one the
    /// exam tests -- "flag" the verb, "august" the adjective. These are the
    /// words that look easy and are not.
    public let isTrap: Bool
    /// How hard this word is in the sense the exam tests, 1 (everyday) to
    /// 5 (obscure). Assigned by hand, because frequency measures the word form
    /// rather than the tested meaning: "august" is a common word and a hard one.
    public let rating: Int
    /// What a grader needs to judge an answer about this word.
    ///
    /// Optional for the same reason ``gre`` is: the shipped dataset carries one
    /// for every word, but a hand-built ``Word`` in a test need not.
    public let grounding: Grounding?
    /// Words this one is confused with. Absent where the dataset found no
    /// candidate, which is most of the vocabulary.
    public let confusion: [ConfusionPair]?
    /// Where the word came from. Optional like ``gre``.
    public let etymology: Etymology?
    /// The connotation of the tested sense.
    public let charge: Charge?
    /// Which of GregMat's 30-word groups carries this word, 1-based. Nil for the
    /// words not on his list.
    public let gregmatGroup: Int?

    /// WordNet orders senses by frequency, so the first one is the sense a
    /// learner is most likely to meet.
    public var primarySense: Sense { senses[0] }

    /// What to teach, grade, and show: the GRE sense where there is one,
    /// WordNet otherwise.
    public var teachingDefinition: String { gre?.definition ?? primarySense.definition }
    public var primaryPartOfSpeech: PartOfSpeech { gre?.pos ?? primarySense.pos }
}
