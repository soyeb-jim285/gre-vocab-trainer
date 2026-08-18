import Foundation

/// FSRS-6, ported from the reference implementation (open-spaced-repetition/py-fsrs).
///
/// This is a port, not a reinterpretation: `Tests/GRECoreTests/FSRSTests.swift`
/// checks every step against golden vectors generated from py-fsrs itself, so
/// the formulas below must stay structurally identical to theirs. Regenerate the
/// vectors with `tools/gen_fsrs_vectors.py` after bumping the pinned version.
public struct FSRS: Sendable {

    public static let defaultParameters: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722,
        0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
        0.0912, 0.0658, 0.1542,
    ]

    private static let minDifficulty = 1.0
    private static let maxDifficulty = 10.0
    private static let minStability = 0.001

    public let parameters: [Double]
    public let desiredRetention: Double
    public let learningSteps: [TimeInterval]
    public let relearningSteps: [TimeInterval]
    public let maximumIntervalDays: Int
    public let enableFuzzing: Bool

    private let decay: Double
    private let factor: Double

    public init(
        parameters: [Double] = FSRS.defaultParameters,
        desiredRetention: Double = 0.9,
        learningSteps: [TimeInterval] = [60, 600],
        relearningSteps: [TimeInterval] = [600],
        maximumIntervalDays: Int = 36_500,
        enableFuzzing: Bool = true
    ) {
        precondition(parameters.count == 21, "FSRS-6 takes exactly 21 parameters")
        self.parameters = parameters
        self.desiredRetention = desiredRetention
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.maximumIntervalDays = maximumIntervalDays
        self.enableFuzzing = enableFuzzing
        self.decay = -parameters[20]
        self.factor = pow(0.9, 1 / decay) - 1
    }

    // MARK: - Public API

    /// Probability the learner still recalls this card at `date`.
    public func retrievability(_ card: FSRSCard, at date: Date) -> Double {
        guard let lastReview = card.lastReview, let stability = card.stability else { return 0 }
        let elapsed = Double(max(0, wholeDays(from: lastReview, to: date)))
        return pow(1 + factor * elapsed / stability, decay)
    }

    /// Apply a review and return the rescheduled card.
    public func review(
        _ card: FSRSCard,
        rating: FSRSRating,
        at reviewDate: Date,
        using rng: inout some RandomNumberGenerator
    ) -> FSRSCard {
        var card = card
        // The reference compares in whole days, so a same-day review reads as 0.
        let daysSinceLastReview = card.lastReview.map { wholeDays(from: $0, to: reviewDate) }
        var interval: TimeInterval

        switch card.state {
        case .learning, .relearning:
            let steps = card.state == .learning ? learningSteps : relearningSteps

            if card.stability == nil || card.difficulty == nil {
                card.stability = initialStability(rating)
                card.difficulty = clampDifficulty(initialDifficulty(rating))
            } else if let days = daysSinceLastReview, days < 1 {
                card.stability = shortTermStability(card.stability!, rating)
                card.difficulty = nextDifficulty(card.difficulty!, rating)
            } else {
                card.stability = nextStability(
                    difficulty: card.difficulty!,
                    stability: card.stability!,
                    retrievability: retrievability(card, at: reviewDate),
                    rating: rating
                )
                card.difficulty = nextDifficulty(card.difficulty!, rating)
            }

            let step = card.step ?? 0
            if steps.isEmpty || (step >= steps.count && rating != .again) {
                interval = graduate(&card)
            } else {
                switch rating {
                case .again:
                    card.step = 0
                    interval = steps[0]
                case .hard:
                    if step == 0 && steps.count == 1 {
                        interval = steps[0] * 1.5
                    } else if step == 0 && steps.count >= 2 {
                        interval = (steps[0] + steps[1]) / 2
                    } else {
                        interval = steps[step]
                    }
                case .good:
                    if step + 1 == steps.count {
                        interval = graduate(&card)
                    } else {
                        card.step = step + 1
                        interval = steps[step + 1]
                    }
                case .easy:
                    interval = graduate(&card)
                }
            }

        case .review:
            if let days = daysSinceLastReview, days < 1 {
                card.stability = shortTermStability(card.stability!, rating)
            } else {
                card.stability = nextStability(
                    difficulty: card.difficulty!,
                    stability: card.stability!,
                    retrievability: retrievability(card, at: reviewDate),
                    rating: rating
                )
            }
            card.difficulty = nextDifficulty(card.difficulty!, rating)

            if rating == .again && !relearningSteps.isEmpty {
                card.state = .relearning
                card.step = 0
                interval = relearningSteps[0]
            } else {
                interval = Double(nextIntervalDays(card.stability!)) * 86_400
            }
        }

        if enableFuzzing && card.state == .review {
            interval = fuzz(interval, using: &rng)
        }
        card.lastReview = reviewDate
        card.due = reviewDate.addingTimeInterval(interval)
        return card
    }

    /// Convenience overload for the common case of not caring about the RNG.
    public func review(_ card: FSRSCard, rating: FSRSRating, at reviewDate: Date) -> FSRSCard {
        var rng = SystemRandomNumberGenerator()
        return review(card, rating: rating, at: reviewDate, using: &rng)
    }

    // MARK: - Formulas

    private func graduate(_ card: inout FSRSCard) -> TimeInterval {
        card.state = .review
        card.step = nil
        return Double(nextIntervalDays(card.stability!)) * 86_400
    }

    private func initialStability(_ rating: FSRSRating) -> Double {
        max(parameters[rating.rawValue - 1], Self.minStability)
    }

    private func initialDifficulty(_ rating: FSRSRating) -> Double {
        parameters[4] - exp(parameters[5] * Double(rating.rawValue - 1)) + 1
    }

    /// Internal rather than private so the half-to-even rounding, which has to
    /// match Python's `round()` for parity with the reference, can be pinned directly.
    func nextIntervalDays(_ stability: Double) -> Int {
        let raw = (stability / factor) * (pow(desiredRetention, 1 / decay) - 1)
        // Python's round() is half-to-even; Swift's default is half-away-from-zero.
        let days = Int(raw.rounded(.toNearestOrEven))
        return min(max(days, 1), maximumIntervalDays)
    }

    private func shortTermStability(_ stability: Double, _ rating: FSRSRating) -> Double {
        var increase = exp(parameters[17] * (Double(rating.rawValue) - 3 + parameters[18]))
            * pow(stability, -parameters[19])
        if rating != .again { increase = max(increase, 1.0) }
        return max(stability * increase, Self.minStability)
    }

    private func nextDifficulty(_ difficulty: Double, _ rating: FSRSRating) -> Double {
        let deltaDifficulty = -(parameters[6] * (Double(rating.rawValue) - 3))
        let damped = difficulty + (10.0 - difficulty) * deltaDifficulty / 9.0
        // Mean reversion pulls difficulty back toward the "easy" baseline over time.
        let target = initialDifficulty(.easy)
        return clampDifficulty(parameters[7] * target + (1 - parameters[7]) * damped)
    }

    private func nextStability(
        difficulty: Double, stability: Double, retrievability: Double, rating: FSRSRating
    ) -> Double {
        let next = rating == .again
            ? forgetStability(difficulty: difficulty, stability: stability, retrievability: retrievability)
            : recallStability(difficulty: difficulty, stability: stability,
                              retrievability: retrievability, rating: rating)
        return max(next, Self.minStability)
    }

    private func forgetStability(
        difficulty: Double, stability: Double, retrievability: Double
    ) -> Double {
        let longTerm = parameters[11]
            * pow(difficulty, -parameters[12])
            * (pow(stability + 1, parameters[13]) - 1)
            * exp((1 - retrievability) * parameters[14])
        let shortTerm = stability / exp(parameters[17] * parameters[18])
        return min(longTerm, shortTerm)
    }

    private func recallStability(
        difficulty: Double, stability: Double, retrievability: Double, rating: FSRSRating
    ) -> Double {
        let hardPenalty = rating == .hard ? parameters[15] : 1
        let easyBonus = rating == .easy ? parameters[16] : 1
        return stability * (1
            + exp(parameters[8])
            * (11 - difficulty)
            * pow(stability, -parameters[9])
            * (exp((1 - retrievability) * parameters[10]) - 1)
            * hardPenalty
            * easyBonus)
    }

    private func clampDifficulty(_ d: Double) -> Double {
        min(max(d, Self.minDifficulty), Self.maxDifficulty)
    }

    // MARK: - Helpers

    /// Whole elapsed days, floored -- the reference works in `timedelta.days`.
    private func wholeDays(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) / 86_400).rounded(.down))
    }

    /// Spread due dates so cards introduced together don't come back together.
    private func fuzz(_ interval: TimeInterval, using rng: inout some RandomNumberGenerator) -> TimeInterval {
        let days = interval / 86_400
        guard days >= 2.5 else { return interval }

        var delta = 1.0
        for (start, end, factor) in Self.fuzzRanges {
            delta += factor * max(min(days, end) - start, 0.0)
        }
        let low = max(2.0, (days - delta).rounded())
        let high = min((days + delta).rounded(), Double(maximumIntervalDays))
        guard high > low else { return low * 86_400 }
        return Double.random(in: low...high, using: &rng).rounded() * 86_400
    }

    private static let fuzzRanges: [(start: Double, end: Double, factor: Double)] = [
        (2.5, 7.0, 0.15), (7.0, 20.0, 0.1), (20.0, .infinity, 0.05),
    ]
}
