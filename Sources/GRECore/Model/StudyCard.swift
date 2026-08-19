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

/// How fresh words are chosen.
public enum NewWordOrder: String, Codable, Sendable, CaseIterable {
    /// Most common in ordinary English first -- the gentlest on-ramp.
    case easiestFirst
    /// Most prep lists first. Highest exam value, but not the easiest words.
    case mostTested
    /// Easiest first, with a difficulty ceiling that follows recent accuracy.
    case adaptive
}

public struct SessionSettings: Equatable, Sendable {
    public var dailyNewWordLimit: Int
    public var sessionLength: Int
    public var strictness: GradingStrictness
    /// False when no API key is configured, which locks the graded mode.
    public var aiEnabled: Bool
    /// Reviews a word must have before it graduates to writing practice.
    /// Zero starts there immediately; the default eases in through the local modes.
    public var writingModeAfterReviews: Int
    /// Drills one mode for the whole session. Nil follows the automatic ladder.
    public var forcedMode: StudyMode?
    public var newWordOrder: NewWordOrder

    public init(
        dailyNewWordLimit: Int = 10, sessionLength: Int = 20,
        strictness: GradingStrictness = .standard, aiEnabled: Bool = true,
        writingModeAfterReviews: Int = 3, forcedMode: StudyMode? = nil,
        newWordOrder: NewWordOrder = .adaptive
    ) {
        self.dailyNewWordLimit = dailyNewWordLimit
        self.sessionLength = sessionLength
        self.strictness = strictness
        self.aiEnabled = aiEnabled
        self.writingModeAfterReviews = writingModeAfterReviews
        self.forcedMode = forcedMode
        self.newWordOrder = newWordOrder
    }
}

extension SessionSettings {
    /// Hardest band to introduce, given how the learner has been scoring.
    ///
    /// Deliberately conservative with no history: someone who has answered
    /// nothing yet gets the most familiar words, not a random sample.
    public static func difficultyCeiling(forAccuracy accuracy: Double?) -> WordDifficulty {
        guard let accuracy else { return .familiar }
        let ceiling: WordDifficulty = switch accuracy {
        case 85...: .rare
        case 70..<85: .hard
        case 55..<70: .moderate
        default: .familiar
        }
        return ceiling
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
