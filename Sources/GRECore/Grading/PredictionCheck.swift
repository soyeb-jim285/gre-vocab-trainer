import Foundation

/// How close a learner's own word for a blank came to the answer, judged
/// before the options appear.
///
/// Predicting first is the habit high scorers credit most, and it is a
/// generation task rather than a recognition one. The check is local and
/// deliberately modest: it knows the answer's synonyms, its accepted
/// paraphrases and its charge, and says "compare it yourself" rather than
/// guessing when none of those settle it.
public enum PredictionVerdict: Equatable, Sendable {
    /// Named the answer itself.
    case exact
    /// A word or phrase the dataset lists as meaning the same.
    case synonym
    /// Not the same meaning, but the same charge: the right half of the job.
    case sameCharge
    /// The opposite charge. The sentence was read the wrong way round.
    case oppositeCharge
    /// Nothing here to judge by.
    case unknown

    public var headline: String {
        switch self {
        case .exact: "You predicted the answer"
        case .synonym: "Your word means the same"
        case .sameCharge: "Right direction"
        case .oppositeCharge: "Opposite direction"
        case .unknown: "Compare your word"
        }
    }

    /// Whether the prediction pointed the right way.
    public var isOnTarget: Bool { self == .exact || self == .synonym || self == .sameCharge }
}

public enum PredictionCheck {

    public static func judge(
        _ prediction: String, answer: Word, catalog: WordCatalog
    ) -> PredictionVerdict {
        let guess = normalized(prediction)
        guard !guess.isEmpty else { return .unknown }
        if guess == normalized(answer.word) || guess == answer.id { return .exact }

        let synonyms = Set((answer.gre?.synonyms ?? []).map(normalized))
            .union((answer.grounding?.acceptedConcepts ?? []).map(normalized))
        if synonyms.contains(guess) { return .synonym }

        guard let predicted = catalog[guess] else { return .unknown }
        // The link runs either way: the answer may list the guess, or the
        // guess may list the answer.
        if Set((predicted.gre?.synonyms ?? []).map(normalized)).contains(normalized(answer.word)) {
            return .synonym
        }
        guard let mine = predicted.charge, let theirs = answer.charge,
              mine != .neutral, theirs != .neutral
        else { return .unknown }
        return mine == theirs ? .sameCharge : .oppositeCharge
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
