import Foundation

/// How demanding the mapping from score to FSRS rating should be.
public enum GradingStrictness: String, Codable, Sendable, CaseIterable {
    case lenient, standard, strict
}

/// A 0...100 score from any study mode, and the one place it becomes an FSRS rating.
///
/// Every mode -- AI-graded or local -- funnels through here, so the thresholds
/// live in exactly one place rather than drifting per mode.
public struct Grade: Equatable, Sendable {
    public let score: Int

    public init(score: Int) {
        // Providers vary in how strictly they honour a JSON schema, and strict
        // mode can't carry minimum/maximum, so an out-of-range score is expected
        // rather than exceptional.
        self.score = min(max(score, 0), 100)
    }

    /// Lower bound of each rating band, worst to best.
    private static func thresholds(_ strictness: GradingStrictness) -> (hard: Int, good: Int, easy: Int) {
        switch strictness {
        case .lenient: (35, 56, 81)
        case .standard: (50, 70, 90)
        case .strict: (60, 80, 95)
        }
    }

    public func rating(strictness: GradingStrictness = .standard) -> FSRSRating {
        let t = Self.thresholds(strictness)
        if score >= t.easy { return .easy }
        if score >= t.good { return .good }
        if score >= t.hard { return .hard }
        return .again
    }
}
