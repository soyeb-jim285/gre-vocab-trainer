import Foundation

/// What the deadline demands, against what the learner is willing to do.
public struct PacingAdvice: Equatable, Sendable {
    /// New words a day needed to have met every remaining word before the test.
    /// Nil when there is no test date to pace against.
    public let required: Int?
    /// What the learner's own cap allows.
    public let allowed: Int
    /// The day the last unseen word gets introduced at `allowed` a day.
    /// Nil when the cap is zero, so coverage never completes.
    public let completion: Date?
    public let wordsRemaining: Int

    /// False only when there is a deadline and the cap cannot meet it. Saying so
    /// is the point: falling behind quietly is the failure mode.
    public var isOnTrack: Bool {
        guard let required else { return true }
        return required <= allowed
    }

    /// What the learner should actually meet today.
    public var newWordsToday: Int {
        guard wordsRemaining > 0 else { return 0 }
        return min(allowed, max(required ?? allowed, 0), wordsRemaining)
    }
}

/// Turning a deadline into a daily rate, and a daily rate back into a date.
public enum Pacing {

    /// Days left to study on, counting today and stopping the day before the
    /// test. The morning of the exam is not a study day worth planning around.
    public static func studyDaysRemaining(
        from now: Date, to testDate: Date, calendar: Calendar = .current
    ) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: testDate)
        return max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    public static func newWordsPerDay(
        remaining: Int, testDate: Date, from now: Date = .now, calendar: Calendar = .current
    ) -> Int {
        guard remaining > 0 else { return 0 }
        let days = studyDaysRemaining(from: now, to: testDate, calendar: calendar)
        return Int((Double(remaining) / Double(days)).rounded(.up))
    }

    /// The day the last unseen word is introduced at this rate. Today counts as
    /// the first day, so a rate that clears the backlog today returns today.
    public static func completionDate(
        remaining: Int, newWordsPerDay rate: Int, from now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard remaining > 0 else { return today }
        guard rate > 0 else { return nil }
        let days = Int((Double(remaining) / Double(rate)).rounded(.up))
        return calendar.date(byAdding: .day, value: days - 1, to: today)
    }

    public static func advise(
        remaining: Int, profile: LearnerProfile, from now: Date = .now,
        calendar: Calendar = .current
    ) -> PacingAdvice {
        let required = profile.testDate.map {
            newWordsPerDay(remaining: remaining, testDate: $0, from: now, calendar: calendar)
        }
        return PacingAdvice(
            required: required,
            allowed: profile.newWordsPerDayCap,
            completion: completionDate(
                remaining: remaining, newWordsPerDay: profile.newWordsPerDayCap,
                from: now, calendar: calendar
            ),
            wordsRemaining: remaining
        )
    }
}
