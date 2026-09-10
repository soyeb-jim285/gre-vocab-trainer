import Foundation

/// What a model call is allowed to cost.
///
/// Nil is no limit. A cap only means anything over a complete ledger, so the app
/// counts every call -- grading, deep dives, mnemonics, the coach -- against it,
/// not just the ones made during a session.
public struct AIBudget: Codable, Equatable, Sendable {
    public var dailyUSD: Double?
    public var lifetimeUSD: Double?

    public init(dailyUSD: Double? = 0.50, lifetimeUSD: Double? = nil) {
        self.dailyUSD = dailyUSD
        self.lifetimeUSD = lifetimeUSD
    }

    public func allows(spentToday: Double, spentLifetime: Double) -> Bool {
        if let dailyUSD, spentToday >= dailyUSD { return false }
        if let lifetimeUSD, spentLifetime >= lifetimeUSD { return false }
        return true
    }
}

/// The learner's goal and pace. One per install, so it lives in preferences
/// rather than the store.
public struct LearnerProfile: Codable, Equatable, Sendable {

    /// Nil until onboarding asks, and for anyone studying without a deadline.
    public var testDate: Date?
    /// What the learner said they would give it. Sets the size of a day.
    public var dailyMinutes: Int
    /// A ceiling on new words a day, independent of what the deadline demands.
    /// Meeting forty new words in a day is how someone quits on day three.
    public var newWordsPerDayCap: Int
    public var desiredRetention: Double
    public var strictness: GradingStrictness
    public var confidence: ConfidenceSettings
    public var budget: AIBudget

    public init(
        testDate: Date? = nil,
        dailyMinutes: Int = 20,
        newWordsPerDayCap: Int = 15,
        desiredRetention: Double = 0.9,
        strictness: GradingStrictness = .standard,
        confidence: ConfidenceSettings = ConfidenceSettings(),
        budget: AIBudget = AIBudget()
    ) {
        self.testDate = testDate
        self.dailyMinutes = max(1, dailyMinutes)
        self.newWordsPerDayCap = max(0, newWordsPerDayCap)
        // Outside this range FSRS either schedules everything tomorrow or lets
        // words rot for years; neither is a setting worth offering.
        self.desiredRetention = min(max(desiredRetention, 0.7), 0.97)
        self.strictness = strictness
        self.confidence = confidence
        self.budget = budget
    }
}
