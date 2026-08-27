import Foundation

/// How a word is being tested this time round.
public enum StudyMode: String, Codable, Sendable, CaseIterable {
    /// Meet the word: pick its definition from four options.
    case multipleChoice
    /// A real sentence with the word blanked out; pick the word that fits.
    case contextCloze
    /// A common word in a sentence using its uncommon tested sense; pick which
    /// meaning applies. Only ever offered for ``Word/isTrap`` words.
    case senseInContext
    /// Definition shown, recall the word.
    case reverseRecall
    /// Hear the word, type its spelling.
    case spelling
    /// Write a definition and a sentence; graded by a model.
    case defineAndUse

    /// The modes that work with no API key.
    public static let locallyGraded: [StudyMode] = [
        .multipleChoice, .contextCloze, .senseInContext, .reverseRecall, .spelling,
    ]

    /// Answered by tapping one of four options rather than by typing.
    public var isTapToAnswer: Bool {
        self == .multipleChoice || self == .contextCloze || self == .senseInContext
    }

    /// Only meaningful for a word whose everyday sense competes with the tested
    /// one; asking "which meaning?" about `laconic` has a single answer.
    public var needsTrapWord: Bool { self == .senseInContext }

    public var needsAI: Bool { self == .defineAndUse }

    /// Shown in the session's mode picker.
    public var label: String {
        switch self {
        case .multipleChoice: "Multiple choice"
        case .contextCloze: "In context"
        case .senseInContext: "Which meaning"
        case .reverseRecall: "Recall"
        case .spelling: "Spelling"
        case .defineAndUse: "Writing"
        }
    }

    public var systemImage: String {
        switch self {
        case .multipleChoice: "checklist"
        case .contextCloze: "text.insert"
        case .senseInContext: "arrow.triangle.branch"
        case .reverseRecall: "arrow.uturn.backward"
        case .spelling: "ear"
        case .defineAndUse: "square.and.pencil"
        }
    }
}

/// One word's scheduling state. The app persists this; GRECore only reads it.
public struct StudyCard: Equatable, Sendable {
    public let wordID: String
    public var fsrs: FSRSCard
    /// Completed reviews, which is what drives mode progression.
    public var reviewCount: Int

    public init(wordID: String, fsrs: FSRSCard = FSRSCard(), reviewCount: Int = 0) {
        self.wordID = wordID
        self.fsrs = fsrs
        self.reviewCount = reviewCount
    }
}

public struct SessionSettings: Equatable, Sendable {
    public var strictness: GradingStrictness
    /// False when no API key is configured, which locks the graded mode.
    public var aiEnabled: Bool
    /// Reviews a word must have before it graduates to writing practice.
    /// Zero starts there immediately; the default eases in through the local modes.
    public var writingModeAfterReviews: Int
    /// Drills one mode for the whole session. Nil follows the automatic ladder.
    public var forcedMode: StudyMode?
    /// Deck new words are drawn from. Nil means the first deck.
    public var currentDeckID: String?

    public init(
        strictness: GradingStrictness = .standard, aiEnabled: Bool = true,
        writingModeAfterReviews: Int = 3, forcedMode: StudyMode? = nil,
        currentDeckID: String? = nil
    ) {
        self.strictness = strictness
        self.aiEnabled = aiEnabled
        self.writingModeAfterReviews = writingModeAfterReviews
        self.forcedMode = forcedMode
        self.currentDeckID = currentDeckID
    }
}

public struct SessionItem: Equatable, Sendable {
    public let card: StudyCard
    public let word: Word
    public let mode: StudyMode

    public init(card: StudyCard, word: Word, mode: StudyMode) {
        self.card = card
        self.word = word
        self.mode = mode
    }
}
