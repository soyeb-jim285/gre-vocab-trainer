import Foundation

/// The shape of one study day: what is left to do, and whether the goal is
/// still reachable.
public struct DayPlan: Equatable, Sendable {
    /// Reviews the scheduler wants now.
    public let dueNow: Int
    /// New words the day still allows, after those already met today.
    public let newWordsRemaining: Int
    /// Answers given since the day rolled over, introductions included.
    public let answeredToday: Int
    /// When the next card falls due, for a day that is already finished.
    public let nextDue: Date?
    public let pacing: PacingAdvice

    /// What is left. Both halves shrink as the learner works, so this is a
    /// countdown rather than a target snapshotted at the start of the day.
    ///
    /// It undercounts slightly on purpose: a word met today comes back inside
    /// the learning steps and is answered again before bed. Promising a number
    /// that only grows as you approach it would be worse than promising a floor.
    public var remainingAnswers: Int { dueNow + newWordsRemaining }

    public var isComplete: Bool { remainingAnswers == 0 }

    public var estimatedMinutes: Int {
        Int((Double(remainingAnswers) * DayPlanner.secondsPerAnswer / 60).rounded(.up))
    }

    /// How far through the day's work, 0 to 1.
    public var progress: Double {
        let total = answeredToday + remainingAnswers
        guard total > 0 else { return 1 }
        return Double(answeredToday) / Double(total)
    }
}

/// Turns the whole card collection into one day's work.
public enum DayPlanner {

    /// ponytail: one flat estimate across every mode. Writing runs to minutes and
    /// a tap runs to seconds, so replace this with a per-mode table once there is
    /// a real latency log to average -- the review record stores the raw times
    /// for exactly that.
    public static let secondsPerAnswer: Double = 12

    public static func plan(
        cards: [StudyCard], catalog: WordCatalog, profile: LearnerProfile,
        introducedToday: Int, answeredToday: Int,
        now: Date = .now, calendar: Calendar = .current
    ) -> DayPlan {
        // A card for a word the dataset no longer carries is history, not work.
        let known = cards.filter { catalog[$0.wordID] != nil }
        // Met, not answered: a word taught a minute ago is no longer waiting to
        // be introduced, so it must not count toward the backlog.
        let met = known.filter(\.isIntroduced)

        let pacing = Pacing.advise(
            remaining: max(0, catalog.words.count - met.count),
            profile: profile, from: now, calendar: calendar
        )

        return DayPlan(
            dueNow: met.filter { $0.fsrs.due <= now }.count,
            newWordsRemaining: max(0, pacing.newWordsToday - introducedToday),
            answeredToday: answeredToday,
            nextDue: known.map(\.fsrs.due).filter { $0 > now }.min(),
            pacing: pacing
        )
    }
}
