import Foundation

/// How sure the learner said they were, asked before anything is revealed.
///
/// Asked before rather than after because afterwards it is not a report, it is a
/// reaction to being told. The point is to catch the gap between what someone
/// knows and what they think they know, and that gap closes the instant the
/// answer appears.
public enum SelfReport: String, Codable, Sendable, CaseIterable, Comparable {
    case guess
    case unsure
    case confident

    private var order: Int {
        switch self {
        case .guess: 0
        case .unsure: 1
        case .confident: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

/// How much help the learner took before answering.
///
/// A ladder, not a switch. Recalling a word after one nudge is a real memory
/// with a weak cue; being told the answer is not a memory at all. Rating them
/// the same is how a deck fills up with words the learner has only ever read.
public enum HintLevel: Int, Codable, Sendable, CaseIterable, Comparable {
    /// Answered cold.
    case none = 0
    /// Took the semantic hint: the meaning gestured at without the word.
    case semantic = 1
    /// Took the example: the word's own sentence, blanked.
    case example = 2
    /// Gave up and read the answer.
    case reveal = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The best rating still available after taking this much help.
    var ceiling: FSRSRating {
        switch self {
        // Easy means "this was effortless and can wait longer". One hint already
        // says it was not.
        case .none: .easy
        case .semantic: .good
        case .example: .hard
        case .reveal: .again
        }
    }
}

/// Everything known about one answer, and the single place it becomes a rating.
///
/// This replaces the latency-only confidence adjustment. Latency was never a
/// separate signal, it was a proxy for how sure the learner felt, measured
/// badly: a long pause is someone thinking, or someone answering the door. Now
/// that the app asks outright, latency is one input among four rather than the
/// only one.
public enum AnswerAppraisal {

    /// Derive the rating the scheduler is told.
    ///
    /// Every input may lower the rating the score earned; none may raise it.
    /// That rule is what keeps the schedule honest: a fast confident guess must
    /// not stretch an interval, because nothing about it says the memory will
    /// last. Widening anywhere here would let the deck quietly drift out of
    /// reach of the learner's actual recall.
    public static func rate(
        grade: Grade,
        selfReport: SelfReport? = nil,
        hints: HintLevel = .none,
        mode: StudyMode,
        latency: Duration? = nil,
        strictness: GradingStrictness = .standard,
        settings: ConfidenceSettings = ConfidenceSettings()
    ) -> FSRSRating {
        // Confidently wrong comes back as soon as possible. A learner who was
        // sure and mistaken holds a wrong memory that will compete with the
        // right one every time the word appears, which is worse than holding
        // nothing: there is something to unlearn first.
        if grade.rating(strictness: strictness) == .again { return .again }

        var rating = grade.rating(strictness: strictness)
        rating = narrow(rating, to: mode.ratingCeiling)
        rating = narrow(rating, to: hints.ceiling)

        if let selfReport {
            rating = narrow(rating, to: ceiling(for: selfReport))
        }

        return narrow(rating, to: latencyCeiling(
            mode: mode, latency: latency, settings: settings
        ) ?? rating)
    }

    /// Whether a first answer says the learner already owns this word.
    ///
    /// All four conditions, because each one rules out a way of being right
    /// without knowing: precise rather than approximately right, sure rather
    /// than hopeful, unaided rather than nudged, and quick rather than
    /// reconstructed. A word that clears all four does not need teaching, and
    /// making someone sit through a lesson for it is how three thousand words
    /// becomes a chore nobody finishes.
    ///
    /// `latency` may be nil when the clock was tainted, which fails the test:
    /// this pathway skips teaching outright, so it should need evidence rather
    /// than assume it.
    public static func isFastKnown(
        grade: Grade,
        selfReport: SelfReport?,
        hints: HintLevel,
        mode: StudyMode,
        latency: Duration?,
        strictness: GradingStrictness = .standard
    ) -> Bool {
        guard grade.rating(strictness: strictness) == .easy,
              selfReport == .confident,
              hints == .none,
              let latency, latency > .zero
        else { return false }
        return latency <= band(for: mode).fast
    }

    /// A right answer the learner called a guess is worth less than the same
    /// answer they were sure of: one is a memory, the other is a coin that came
    /// up heads. Being unsure and right is a real but shaky memory, which is
    /// exactly what Good means.
    private static func ceiling(for report: SelfReport) -> FSRSRating {
        switch report {
        case .confident: .easy
        case .unsure: .good
        case .guess: .hard
        }
    }

    /// Reading load differs sharply by mode. Four short definitions are taken in
    /// far faster than a cloze sentence, which has to be read before recall even
    /// begins. One global threshold would mark cloze as hesitant across the board.
    ///
    /// ponytail: a fixed per-mode table under a single scale knob. Move to
    /// individually configurable thresholds if real answer times show the modes
    /// drifting apart unevenly rather than together.
    public static func band(for mode: StudyMode) -> (fast: Duration, slow: Duration) {
        switch mode {
        case .multipleChoice: (.seconds(4), .seconds(12))
        // One tap on a single word, and the three options never change.
        case .charge, .gist: (.seconds(3), .seconds(8))
        // Two options, but the whole question is the hesitation between them:
        // an instant answer means the pair is genuinely separate in memory.
        case .discriminate: (.seconds(5), .seconds(15))
        // An exam question is read before it is answered, and the real test
        // allows about a minute and a half each.
        case .greItem: (.seconds(20), .seconds(75))
        case .senseInContext: (.seconds(7), .seconds(20))
        case .contextCloze: (.seconds(8), .seconds(22))
        case .reverseRecall, .spelling, .defineAndUse: (.seconds(6), .seconds(18))
        // Typing a meaning is composition, not recognition: the learner has to
        // find the words as well as the sense, so the same clock would call
        // every honest answer hesitant.
        case .typeMeaning: (.seconds(8), .seconds(25))
        }
    }

    /// Nil when latency says nothing usable: the feature is off, the clock was
    /// tainted, or the mode grades on a scale fine enough that folding time in
    /// would count the same hesitation twice.
    private static func latencyCeiling(
        mode: StudyMode, latency: Duration?, settings: ConfidenceSettings
    ) -> FSRSRating? {
        guard settings.isEnabled, settings.scale > 0,
              mode.isTapToAnswer,
              let latency, latency > .zero
        else { return nil }

        let band = band(for: mode)
        if latency <= scaled(band.fast, by: settings.scale) { return .easy }
        if latency >= scaled(band.slow, by: settings.scale) { return .hard }
        return .good
    }

    private static func narrow(_ rating: FSRSRating, to ceiling: FSRSRating) -> FSRSRating {
        FSRSRating(rawValue: min(rating.rawValue, ceiling.rawValue)) ?? rating
    }

    private static func scaled(_ duration: Duration, by scale: Double) -> Duration {
        .seconds(Double(duration.components.seconds) * scale)
    }
}
