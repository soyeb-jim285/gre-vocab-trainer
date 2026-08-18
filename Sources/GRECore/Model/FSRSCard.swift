import Foundation

/// How well the learner recalled a card. Matches FSRS's four-button scale.
public enum FSRSRating: Int, Codable, Sendable, CaseIterable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}

/// Where a card sits in the learning pipeline.
public enum FSRSState: Int, Codable, Sendable {
    /// Never graduated: still working through the short learning steps.
    case learning = 1
    /// Graduated; intervals are measured in days.
    case review = 2
    /// Was in review, then forgotten; working back through the relearning steps.
    case relearning = 3
}

/// The scheduler's entire memory of one card.
///
/// `stability` is how many days until recall probability falls to the desired
/// retention. `difficulty` (1...10) is how fast that stability grows.
/// Both are nil until the card's first review.
public struct FSRSCard: Equatable, Codable, Sendable {
    public var stability: Double?
    public var difficulty: Double?
    public var due: Date
    public var lastReview: Date?
    public var state: FSRSState
    /// Index into the learning/relearning steps; nil once the card is in review.
    public var step: Int?

    public init(
        stability: Double? = nil,
        difficulty: Double? = nil,
        due: Date = Date(timeIntervalSince1970: 0),
        lastReview: Date? = nil,
        state: FSRSState = .learning,
        step: Int? = 0
    ) {
        self.stability = stability
        self.difficulty = difficulty
        self.due = due
        self.lastReview = lastReview
        self.state = state
        self.step = step
    }
}
