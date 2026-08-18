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
    public var dailyNewWordLimit: Int
    public var sessionLength: Int
    public var strictness: GradingStrictness
    /// False when no API key is configured, which locks the graded mode.
    public var aiEnabled: Bool

    public init(
        dailyNewWordLimit: Int = 10, sessionLength: Int = 20,
        strictness: GradingStrictness = .standard, aiEnabled: Bool = true
    ) {
        self.dailyNewWordLimit = dailyNewWordLimit
        self.sessionLength = sessionLength
        self.strictness = strictness
        self.aiEnabled = aiEnabled
    }
}

public struct SessionItem: Equatable, Sendable {
    public let card: StudyCard
    public let word: Word
    public let mode: StudyMode
}
