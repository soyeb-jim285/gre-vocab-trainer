import Foundation

public struct ConfidenceSettings: Codable, Equatable, Sendable {
    /// Off until there is real answer-time data to calibrate against. A loose
    /// threshold rates every quick answer Easy, which stretches intervals across
    /// the whole deck, and the learner would not find out for weeks.
    public var isEnabled: Bool
    /// Scales every mode's thresholds. Above 1 is more forgiving of a slow answer.
    public var scale: Double

    public init(isEnabled: Bool = false, scale: Double = 1) {
        self.isEnabled = isEnabled
        self.scale = scale
    }
}

/// How long an answer took, read as a rating adjustment.
///
/// The three tap-to-answer modes score 100 or 0, so without this the scheduler
/// only ever sees Again or Easy from half the app: a word recalled instantly and
/// a word dredged up after twenty seconds of staring are recorded identically.
public enum Confidence {

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
        case .senseInContext: (.seconds(7), .seconds(20))
        case .contextCloze: (.seconds(8), .seconds(22))
        case .reverseRecall, .spelling, .defineAndUse: (.seconds(6), .seconds(18))
        }
    }

    /// Narrow `rating` by how long the answer took.
    ///
    /// This only ever narrows. A latency read is weak evidence -- the learner may
    /// have been interrupted, or read the sentence twice out of interest -- so it
    /// may lower the rating the score earned and must never raise it. Everything
    /// downstream of here depends on that: widening would let a fast guess
    /// inflate an interval.
    public static func adjust(
        _ rating: FSRSRating, mode: StudyMode, latency: Duration?,
        settings: ConfidenceSettings
    ) -> FSRSRating {
        // Only the tap-to-answer modes. Spelling and recall already grade on a
        // graded scale, and writing is graded by a model against the reference;
        // there the score discriminates on its own, and folding latency in on top
        // would count the same hesitation twice.
        guard settings.isEnabled, settings.scale > 0,
              mode.isTapToAnswer,
              rating != .again,
              let latency, latency > .zero
        else { return rating }

        let band = band(for: mode)
        let ceiling: FSRSRating =
            if latency <= scaled(band.fast, by: settings.scale) { .easy }
            else if latency >= scaled(band.slow, by: settings.scale) { .hard }
            else { .good }

        return FSRSRating(rawValue: min(rating.rawValue, ceiling.rawValue)) ?? rating
    }

    private static func scaled(_ duration: Duration, by scale: Double) -> Duration {
        .seconds(Double(duration.components.seconds) * scale)
    }
}
