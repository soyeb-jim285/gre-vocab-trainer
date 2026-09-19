import Foundation

/// A real GRE verbal question, as opposed to a question about one word.
///
/// The study modes test whether a word is held. These test whether it can be
/// used to read a sentence, which is the thing the exam actually scores. They
/// are written and verified rather than generated at runtime: a blank with two
/// defensible answers is worse than no question at all, and only a person can
/// settle that.
public struct GREItem: Codable, Identifiable, Hashable, Sendable {

    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// One blank, five options, exactly one best answer.
        case textCompletion
        /// One blank, six options, exactly two answers that both fit and leave
        /// the sentence meaning the same thing.
        case sentenceEquivalence

        /// How many options the learner picks.
        public var answerCount: Int {
            switch self {
            case .textCompletion: 1
            case .sentenceEquivalence: 2
            }
        }

        public var optionCount: Int {
            switch self {
            case .textCompletion: 5
            case .sentenceEquivalence: 6
            }
        }

        public var label: String {
            switch self {
            case .textCompletion: "Text completion"
            case .sentenceEquivalence: "Sentence equivalence"
            }
        }

        public var instruction: String {
            switch self {
            case .textCompletion: "Choose the word that best completes the sentence."
            case .sentenceEquivalence:
                "Choose the two words that complete the sentence and leave it meaning the same thing."
            }
        }
    }

    public let id: String
    public let kind: Kind
    /// The sentence, with the blank written as five underscores.
    public let stem: String
    /// Word ids, in the order they are shown.
    public let options: [String]
    /// Word ids. One for a completion, two for an equivalence.
    public let answers: [String]
    /// Why the answer is the answer, read after the attempt. One or two
    /// sentences, and it has to do more than restate the definition: the point
    /// is the clue in the sentence that settles it.
    public let explanation: String
    /// Words this item is worth scheduling against. Always includes the
    /// answers; a distractor is not evidence about itself.
    public var testedWordIDs: [String] { answers }

    public init(
        id: String, kind: Kind, stem: String, options: [String],
        answers: [String], explanation: String
    ) {
        self.id = id
        self.kind = kind
        self.stem = stem
        self.options = options
        self.answers = answers
        self.explanation = explanation
    }

    /// The blank as written in every stem.
    public static let blank = "_____"

    /// Whether a set of picks is the answer. Order never matters: an
    /// equivalence is a pair, not a sequence.
    public func isCorrect(_ picked: some Collection<String>) -> Bool {
        picked.count == answers.count && Set(picked) == Set(answers)
    }

    /// Structural problems, as sentences. Empty means the item is shaped right,
    /// which is all a machine can tell: whether the blank has exactly one best
    /// answer is a reading judgement and belongs to the sampled human review.
    public func structuralProblems(knownWordIDs: Set<String>) -> [String] {
        var problems: [String] = []
        if !stem.contains(Self.blank) {
            problems.append("the stem has no blank")
        } else if stem.components(separatedBy: Self.blank).count != 2 {
            problems.append("the stem has more than one blank")
        }
        if options.count != kind.optionCount {
            problems.append("\(options.count) options, expected \(kind.optionCount)")
        }
        if Set(options).count != options.count { problems.append("a repeated option") }
        if answers.count != kind.answerCount {
            problems.append("\(answers.count) answers, expected \(kind.answerCount)")
        }
        if !Set(answers).isSubset(of: Set(options)) {
            problems.append("an answer that is not among the options")
        }
        for id in options where !knownWordIDs.contains(id) {
            problems.append("option \"\(id)\" is not in the dataset")
        }
        if explanation.count < 40 { problems.append("the explanation is too short to explain") }
        return problems
    }
}
