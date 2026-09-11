import Foundation

/// The rungs of help available on one question, in the order they are offered.
///
/// Stuck is a fork in the road, and an app that offers only the answer sends
/// every learner down the wrong branch. Recalling a word after a nudge is
/// worth far more than being told it, so the nudges come first and each one
/// costs something: see ``HintLevel/ceiling``.
///
/// Nothing here calls a model. Both rungs are already in the dataset, which is
/// what makes an unlimited hint ladder affordable.
public enum HintLadder {

    /// The hint for `level` on this word, or nil where the word cannot supply
    /// one and the ladder skips a rung.
    public static func hint(_ level: HintLevel, for word: Word) -> String? {
        switch level {
        case .none:
            nil
        case .semantic:
            // Written never to contain the word or its stem, so it gestures at
            // the meaning without handing it over.
            word.grounding?.semanticHint
        case .example:
            // The word's own sentence with the word blanked: the meaning is
            // recoverable from the situation, which is how it will have to be
            // recovered in the exam.
            word.gre?.cloze.first
        case .reveal:
            word.teachingDefinition
        }
    }

    /// The rungs this word can actually offer, in order.
    ///
    /// A word with no cloze sentence skips straight from the semantic hint to
    /// the reveal rather than offering an empty step.
    public static func available(for word: Word) -> [HintLevel] {
        [.semantic, .example, .reveal].filter { hint($0, for: word) != nil }
    }

    /// The next rung after `level`, or nil when the learner is at the reveal.
    public static func next(after level: HintLevel, for word: Word) -> HintLevel? {
        available(for: word).first { $0 > level }
    }
}
