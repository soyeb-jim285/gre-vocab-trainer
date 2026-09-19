import Foundation

/// What the learner produced, whatever mode asked for it.
public enum AnswerDraft: Equatable, Sendable {
    /// A tapped option, identified by ``AnswerJudge/correctChoice(for:)``.
    case choice(String)
    /// Typed a single word: spelling and recall.
    case typed(String)
    /// Wrote both halves of the graded mode. Needs a model.
    case written(definition: String, sentence: String)
    /// Typed what the word means, in the learner's own words. Needs a model,
    /// and a different one: this is graded against the word's grounding rather
    /// than against a single reference line.
    case meaning(String)
    /// Said whether the meaning came to mind, after seeing it. Quick recall
    /// only.
    case recalled(Bool)
    /// Gave up without answering.
    case gaveUp

    /// Whether this is worth submitting.
    ///
    /// Here rather than in the view so the rule is stated once for every mode
    /// instead of once per mode at the call site.
    public var isSubmittable: Bool {
        switch self {
        case let .typed(text):
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .written(definition, sentence):
            !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .meaning(text):
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .choice, .recalled, .gaveUp:
            true
        }
    }
}

/// The verdict on one answer: what it scored, what the scheduler is told, and
/// what the learner reads.
public struct Judgement: Equatable, Sendable {
    public let grade: Grade
    public let rating: FSRSRating
    public let headline: String
    public let detail: String
    /// Whether to print the dictionary entry underneath.
    public let showsReference: Bool

    public init(
        grade: Grade, rating: FSRSRating, headline: String, detail: String,
        showsReference: Bool = false
    ) {
        self.grade = grade
        self.rating = rating
        self.headline = headline
        self.detail = detail
        self.showsReference = showsReference
    }
}

/// The single place an answer becomes a verdict.
///
/// Every mode routes through here, so the score, the rating and the words the
/// learner reads are decided together rather than being re-decided per mode in
/// the view layer, which is how they drifted apart before.
public enum AnswerJudge {

    /// What a tapped option has to match. Cloze offers words, the other two
    /// offer definitions.
    public static func correctChoice(for item: SessionItem) -> String {
        switch item.mode {
        case .contextCloze, .discriminate: item.word.id
        case .charge: (item.word.charge ?? .neutral).rawValue
        default: item.word.teachingDefinition
        }
    }

    /// Nil means this answer needs the model. That is the graded mode and only
    /// the graded mode.
    public static func judge(
        _ draft: AnswerDraft,
        item: SessionItem,
        strictness: GradingStrictness = .standard,
        latency: Duration? = nil,
        confidence: ConfidenceSettings = ConfidenceSettings(),
        /// What the learner said before the answer was revealed, when asked.
        selfReport: SelfReport? = nil,
        /// How much help they took getting there.
        hints: HintLevel = .none
    ) -> Judgement? {
        switch draft {
        case .written, .meaning:
            return nil

        case .gaveUp:
            // Rated Again outright rather than mapped from zero: an unanswered
            // card is not weak evidence of a weak memory, it is the learner
            // saying so. No model call either -- paying to be told that an empty
            // answer is wrong would be absurd.
            return Judgement(
                grade: Grade(score: 0), rating: .again,
                headline: "Let's learn it",
                detail: item.mode == .reverseRecall || item.mode == .spelling
                    ? item.word.word : "",
                showsReference: true
            )

        case let .recalled(knew):
            // Self-rated, so the claim is taken at face value only downward: a
            // miss is a miss, and a hit is Good at best.
            let grade = Grade(score: knew ? 100 : 0)
            return Judgement(
                grade: grade,
                rating: rate(grade, item: item, strictness: strictness,
                             latency: latency, confidence: confidence,
                             selfReport: selfReport, hints: hints),
                headline: knew ? "Kept" : "Back soon",
                detail: item.word.teachingDefinition
            )

        case let .choice(chosen):
            let correct = chosen == correctChoice(for: item)
            let grade = Grade(score: correct ? 100 : 0)
            let (headline, showsReference): (String, Bool) = switch item.mode {
            case .contextCloze:
                // Getting it wrong in context is the moment the full entry helps.
                (correct ? "That fits" : "Not that one", !correct)
            case .senseInContext:
                (correct ? "Right meaning" : "That is the everyday meaning", true)
            case .charge:
                (correct ? "Right charge" : "It is \((item.word.charge ?? .neutral).label.lowercased())", true)
            case .discriminate:
                // The distinction is the whole answer here, right or wrong: a
                // learner who guessed correctly still has not been told what
                // separates the two.
                (correct ? "Told apart" : "That is the other one", false)
            default:
                // Multiple choice already showed the definition among the options.
                (correct ? "Correct" : "Not quite", false)
            }
            return Judgement(
                grade: grade,
                rating: rate(grade, item: item, strictness: strictness,
                             latency: latency, confidence: confidence,
                             selfReport: selfReport, hints: hints),
                headline: headline,
                detail: item.mode == .discriminate
                    ? ConfusionDrill.distinction(for: item) ?? item.word.teachingDefinition
                    : item.word.teachingDefinition,
                showsReference: showsReference
            )

        case let .typed(typed):
            if item.mode == .spelling {
                let result = LocalGrader.gradeSpelling(typed: typed, expected: item.word.word)
                return Judgement(
                    grade: result.grade,
                    rating: rate(result.grade, item: item, strictness: strictness,
                                 latency: latency, confidence: confidence,
                                 selfReport: selfReport, hints: hints),
                    headline: result.isExact ? "Spelled correctly" : "Spelling is off",
                    detail: result.isExact
                        ? item.word.teachingDefinition
                        : "You wrote \"\(typed.trimmingCharacters(in: .whitespaces))\" — it's \"\(item.word.word)\"."
                )
            }
            let grade = LocalGrader.gradeRecall(typed: typed, expected: item.word.word)
            return Judgement(
                grade: grade,
                rating: rate(grade, item: item, strictness: strictness,
                             latency: latency, confidence: confidence,
                             selfReport: selfReport, hints: hints),
                headline: grade.score == 100 ? "Got it" : (grade.score > 0 ? "Close" : "The word was"),
                detail: item.word.word,
                showsReference: true
            )
        }
    }

    private static func rate(
        _ grade: Grade, item: SessionItem, strictness: GradingStrictness,
        latency: Duration?, confidence: ConfidenceSettings,
        selfReport: SelfReport? = nil, hints: HintLevel = .none
    ) -> FSRSRating {
        AnswerAppraisal.rate(
            grade: grade, selfReport: selfReport, hints: hints, mode: item.mode,
            latency: latency, strictness: strictness, settings: confidence
        )
    }
}
