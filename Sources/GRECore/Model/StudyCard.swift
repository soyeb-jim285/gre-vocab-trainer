import Foundation

/// How a word is being tested this time round.
public enum StudyMode: String, Codable, Sendable, CaseIterable {
    /// Meet the word: pick its definition from four options.
    case multipleChoice
    /// Definition shown, recall the word.
    case reverseRecall
    /// Hear the word, type its spelling.
    case spelling
    /// Write a definition and a sentence; graded by a model.
    case defineAndUse

    /// The modes that work with no API key.
    public static let locallyGraded: [StudyMode] = [.multipleChoice, .reverseRecall, .spelling]

    public var needsAI: Bool { self == .defineAndUse }

    /// Shown in the session's mode picker.
    public var label: String {
        switch self {
        case .multipleChoice: "Multiple choice"
        case .reverseRecall: "Recall"
        case .spelling: "Spelling"
        case .defineAndUse: "Writing"
        }
    }

    public var systemImage: String {
        switch self {
        case .multipleChoice: "checklist"
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
