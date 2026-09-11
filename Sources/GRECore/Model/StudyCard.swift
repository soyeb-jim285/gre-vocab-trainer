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
    /// Type what the word means, in your own words; graded by a model against
    /// the word's ``Grounding``.
    ///
    /// This is the pretest question and the backbone of the model: a free answer
    /// says how well a word is actually held, where a tap says only that four
    /// options were distinguishable.
    case typeMeaning
    /// Two words that are easy to mix up, and one definition. Pick the one that
    /// fits.
    ///
    /// The other modes ask whether a word is known. This asks whether it is
    /// known apart from its neighbour, which is the thing the exam actually
    /// tests and the thing a four-option question hides: three unrelated
    /// distractors let a vague sense of the word carry the answer.
    case discriminate

    /// The modes that work with no API key.
    public static let locallyGraded: [StudyMode] = [
        .multipleChoice, .contextCloze, .senseInContext, .reverseRecall, .spelling,
        .discriminate,
    ]

    /// Answered by tapping one of four options rather than by typing.
    public var isTapToAnswer: Bool {
        self == .multipleChoice || self == .contextCloze || self == .senseInContext
            || self == .discriminate
    }

    /// Only meaningful for a word whose everyday sense competes with the tested
    /// one; asking "which meaning?" about `laconic` has a single answer.
    public var needsTrapWord: Bool { self == .senseInContext }

    public var needsAI: Bool { self == .defineAndUse || self == .typeMeaning }

    /// How much work this question asks of the learner, 1 to 3.
    ///
    /// Not difficulty: a hard multiple-choice question is still one tap. This is
    /// the cost of answering at all, and it is what stops a day's reviews
    /// becoming homework. A hundred and fifty typed definitions is a punishment
    /// however well chosen each one is.
    public var friction: Int {
        switch self {
        case .multipleChoice, .contextCloze, .senseInContext, .discriminate: 1
        case .reverseRecall, .spelling: 2
        case .typeMeaning, .defineAndUse: 3
        }
    }

    /// Shown in the session's mode picker.
    public var label: String {
        switch self {
        case .multipleChoice: "Multiple choice"
        case .contextCloze: "In context"
        case .senseInContext: "Which meaning"
        case .reverseRecall: "Recall"
        case .spelling: "Spelling"
        case .defineAndUse: "Writing"
        case .typeMeaning: "Meaning"
        case .discriminate: "Tell apart"
        }
    }

    /// What the learner is being asked, in one line.
    ///
    /// Here rather than in the view because it was previously written twice for
    /// the same question: the prompt card and the answer area each had their own
    /// wording, and they drifted.
    public var question: String {
        switch self {
        case .multipleChoice: "Which definition fits?"
        case .contextCloze: "Fill the gap"
        case .senseInContext: "Which meaning is used here?"
        case .reverseRecall: "Which word means this?"
        case .spelling: "Listen and spell"
        case .defineAndUse: "Define it, then use it"
        case .typeMeaning: "What does this mean?"
        case .discriminate: "Which of these two means this?"
        }
    }

    /// What the prompt shows above the question.
    public var promptSubject: PromptSubject {
        switch self {
        case .spelling: .audio
        // Showing the headword would answer the question: the definition is
        // the prompt and the two words are the options.
        case .reverseRecall, .discriminate: .definition
        // The gap is the question, and it lives with the options. A headword
        // here would answer it.
        case .contextCloze: .nothing
        case .multipleChoice, .senseInContext, .defineAndUse, .typeMeaning: .word
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
        case .typeMeaning: "text.cursor"
        case .discriminate: "arrow.left.and.right"
        }
    }
}

/// One word's scheduling state. The app persists this; GRECore only reads it.
/// What a question shows before the learner answers it.
public enum PromptSubject: Equatable, Sendable {
    /// The headword, its pronunciation and its part of speech.
    case word
    /// A definition, to recall the word from.
    case definition
    /// Sound only.
    case audio
    /// Nothing: showing anything would give it away.
    case nothing
}

public struct StudyCard: Equatable, Sendable {
    public let wordID: String
    public var fsrs: FSRSCard
    /// Completed reviews.
    public var reviewCount: Int
    /// Whether the word has been taught.
    ///
    /// Separate from `reviewCount` on purpose. Teaching must not consume the
    /// card's first FSRS rating: initial stability is set by the first rating a
    /// card ever gets, so recording a meeting as a review would fix every word's
    /// starting difficulty on something the learner was never asked.
    public var isIntroduced: Bool

    public init(
        wordID: String, fsrs: FSRSCard = FSRSCard(), reviewCount: Int = 0,
        isIntroduced: Bool = false
    ) {
        self.wordID = wordID
        self.fsrs = fsrs
        self.reviewCount = reviewCount
        // Anything already answered has plainly been met, whatever the store says.
        self.isIntroduced = isIntroduced || reviewCount > 0
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
    /// The neighbour this question is asking the word apart from, for
    /// ``StudyMode/discriminate``. Nil for every other mode.
    ///
    /// Carried on the item rather than looked up at grading time because a
    /// right answer does not say which pair was asked, and the line the learner
    /// needs to read afterwards belongs to the pair.
    public let confusedWith: String?

    public init(
        card: StudyCard, word: Word, mode: StudyMode, confusedWith: String? = nil
    ) {
        self.card = card
        self.word = word
        self.mode = mode
        self.confusedWith = confusedWith
    }
}
