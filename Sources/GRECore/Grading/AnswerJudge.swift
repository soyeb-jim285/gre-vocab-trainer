import Foundation

/// What the learner produced, whatever mode asked for it.
public enum AnswerDraft: Equatable, Sendable {
    /// A tapped option, identified by ``AnswerJudge/correctChoice(for:)``.
    case choice(String)
    /// Typed a single word: spelling and recall.
    case typed(String)
    /// Wrote both halves of the graded mode. Only this one needs a model.
    case written(definition: String, sentence: String)
    /// Gave up without answering.
    case gaveUp
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
        case .contextCloze: item.word.id
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
        confidence: ConfidenceSettings = ConfidenceSettings()
    ) -> Judgement? {
        switch draft {
        case .written:
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

        case let .choice(chosen):
            let correct = chosen == correctChoice(for: item)
            let grade = Grade(score: correct ? 100 : 0)
            let (headline, showsReference): (String, Bool) = switch item.mode {
            case .contextCloze:
                // Getting it wrong in context is the moment the full entry helps.
                (correct ? "That fits" : "Not that one", !correct)
            case .senseInContext:
                (correct ? "Right meaning" : "That is the everyday meaning", true)
            default:
                // Multiple choice already showed the definition among the options.
                (correct ? "Correct" : "Not quite", false)
            }
            return Judgement(
                grade: grade,
                rating: rate(grade, item: item, strictness: strictness,
                             latency: latency, confidence: confidence),
                headline: headline,
                detail: item.word.teachingDefinition,
                showsReference: showsReference
            )

        case let .typed(typed):
            if item.mode == .spelling {
                let result = LocalGrader.gradeSpelling(typed: typed, expected: item.word.word)
                return Judgement(
                    grade: result.grade,
                    rating: rate(result.grade, item: item, strictness: strictness,
                                 latency: latency, confidence: confidence),
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
                             latency: latency, confidence: confidence),
                headline: grade.score == 100 ? "Got it" : (grade.score > 0 ? "Close" : "The word was"),
                detail: item.word.word,
                showsReference: true
            )
        }
    }

    private static func rate(
        _ grade: Grade, item: SessionItem, strictness: GradingStrictness,
        latency: Duration?, confidence: ConfidenceSettings
    ) -> FSRSRating {
        Confidence.adjust(
            grade.rating(strictness: strictness),
            mode: item.mode, latency: latency, settings: confidence
        )
    }
}
