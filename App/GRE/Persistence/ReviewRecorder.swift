import Foundation
import GRECore
import SwiftData

/// Applies an answer to a word's schedule.
///
/// Shared by every path that can move a card so a review recorded outside a
/// session moves the schedule exactly the same way -- two code paths updating
/// FSRS state differently would be a silent scheduling bug.
@MainActor
enum ReviewRecorder {

    @discardableResult
    static func record(
        wordID: String, mode: StudyMode, grade: Grade, rating: FSRSRating,
        scheduler: FSRS, in context: ModelContext, index: MasteryIndex,
        latency: Duration? = nil, latencyTainted: Bool = false,
        isIntroduction: Bool = false, at date: Date = .now
    ) -> CardRecord {
        let record = existing(wordID, in: context) ?? {
            let fresh = CardRecord(wordID: wordID)
            context.insert(fresh)
            return fresh
        }()

        let before = record.fsrs.state
        record.fsrs = scheduler.review(record.fsrs, rating: rating, at: date)
        record.reviewCount += 1
        if before == .review && record.fsrs.state == .relearning { record.lapses += 1 }
        if record.introducedAt == nil { record.introducedAt = date }

        context.insert(ReviewRecord(
            wordID: wordID, reviewedAt: date, mode: mode, score: grade.score, rating: rating,
            latency: latency, latencyTainted: latencyTainted, isIntroduction: isIntroduction
        ))
        try? context.save()
        // Required rather than optional: a stale ring is a bug report, and an
        // argument you can forget is one you will.
        index.reload(from: context)
        return record
    }

    /// Teach a word rather than test it.
    ///
    /// Rated Good, which walks the card onto the next learning step and puts the
    /// first real question about ten minutes out. That is the point: meet the
    /// word, then be asked about it while it is still warm. Recorded as an
    /// introduction so it never counts toward accuracy or competence -- being
    /// shown a word is not evidence you can do anything with it.
    @discardableResult
    static func introduce(
        wordID: String, scheduler: FSRS, in context: ModelContext, index: MasteryIndex,
        at date: Date = .now
    ) -> CardRecord {
        record(
            wordID: wordID, mode: .multipleChoice, grade: Grade(score: 0), rating: .good,
            scheduler: scheduler, in: context, index: index, latencyTainted: true,
            isIntroduction: true, at: date
        )
    }

    /// Mean score over the learner's most recent graded answers. Nil until there
    /// is enough to judge by.
    static func recentAccuracy(in context: ModelContext, over count: Int = 40) -> Double? {
        var descriptor = FetchDescriptor<ReviewRecord>(
            predicate: #Predicate { !$0.isIntroduction },
            sortBy: [SortDescriptor(\.reviewedAt, order: .reverse)]
        )
        descriptor.fetchLimit = count
        guard let recent = try? context.fetch(descriptor), recent.count >= 5 else { return nil }
        return Double(recent.map(\.score).reduce(0, +)) / Double(recent.count)
    }

    /// What the learner has shown they can do with one word.
    ///
    /// Derived from the log rather than stored: a denormalised copy is a second
    /// thing to write, and it drifts the first time progress is reset.
    static func competence(for wordID: String, in context: ModelContext) -> CardCompetence {
        let descriptor = FetchDescriptor<ReviewRecord>(
            predicate: #Predicate { $0.wordID == wordID && !$0.isIntroduction }
        )
        return CardCompetence(((try? context.fetch(descriptor)) ?? []).map(\.evidence))
    }

    /// Answers given since the study day rolled over, and how many of them were
    /// first meetings. Both drive the day's countdown.
    static func todaysWork(in context: ModelContext, since dayStart: Date) -> (answered: Int, introduced: Int) {
        let descriptor = FetchDescriptor<ReviewRecord>(
            predicate: #Predicate { $0.reviewedAt >= dayStart }
        )
        let today = (try? context.fetch(descriptor)) ?? []
        return (today.count, today.filter(\.isIntroduction).count)
    }

    /// Every card keyed by word, which is how decks and the planner read them.
    static func cardsByID(in context: ModelContext) -> [String: StudyCard] {
        let records = (try? context.fetch(FetchDescriptor<CardRecord>())) ?? []
        return Dictionary(records.map { ($0.wordID, $0.studyCard) }, uniquingKeysWith: { a, _ in a })
    }

    static func bestQuizScore(deckID: String?, in context: ModelContext) -> Int? {
        let all = (try? context.fetch(FetchDescriptor<QuizRecord>())) ?? []
        return all.filter { $0.deckID == deckID }.map(\.score).max()
    }

    /// Delete every trace of study: schedules, answered reviews, test scores,
    /// what was spent, and the paid-for deep dives. Listed explicitly rather than
    /// looped over the container so a new @Model added later fails review here
    /// rather than silently surviving a reset.
    static func eraseAllProgress(in context: ModelContext, index: MasteryIndex) throws {
        try context.delete(model: CardRecord.self)
        try context.delete(model: ReviewRecord.self)
        try context.delete(model: QuizRecord.self)
        try context.delete(model: DeepDiveRecord.self)
        try context.delete(model: AICall.self)
        try context.save()
        index.reload(from: context)
    }

    static func existing(_ wordID: String, in context: ModelContext) -> CardRecord? {
        var descriptor = FetchDescriptor<CardRecord>(predicate: #Predicate { $0.wordID == wordID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

enum AIBudgetError: LocalizedError {
    case exhausted(spentToday: Double, spentLifetime: Double)

    var errorDescription: String? {
        switch self {
        case let .exhausted(today, lifetime):
            "That would go over your spending limit. \(Self.money(today)) today, "
                + "\(Self.money(lifetime)) in total. Raise or clear the limit in Settings."
        }
    }

    private static func money(_ usd: Double) -> String {
        usd < 0.01 && usd > 0 ? String(format: "%.2f¢", usd * 100) : String(format: "$%.2f", usd)
    }
}

/// The one place money is spent, and the one place it is counted.
///
/// Every model call goes through ``spend(_:budget:dayStart:in:call:)``. Three
/// separate call sites checking their own limits against their own partial
/// totals is how a cap becomes decorative -- and the mnemonic on every new word
/// multiplies call volume by the daily new-word allowance, so the cap has to
/// actually hold.
@MainActor
enum AILedger {

    static func spentLifetime(in context: ModelContext) -> Double {
        let all = (try? context.fetch(FetchDescriptor<AICall>())) ?? []
        return all.map(\.usd).reduce(0, +)
    }

    static func spentToday(in context: ModelContext, since dayStart: Date) -> Double {
        let descriptor = FetchDescriptor<AICall>(predicate: #Predicate { $0.at >= dayStart })
        return ((try? context.fetch(descriptor)) ?? []).map(\.usd).reduce(0, +)
    }

    /// Run `call` only if the budget still allows it, and record what it cost.
    ///
    /// The check happens before dispatch: refusing after the money is spent is
    /// not a limit. A call the provider did not price is still recorded, at zero,
    /// so the token counts survive.
    @discardableResult
    static func spend<T>(
        _ kind: AICallKind, budget: AIBudget, dayStart: Date, in context: ModelContext,
        call: () async throws -> (T, CallCost?)
    ) async throws -> (T, CallCost?) {
        let today = spentToday(in: context, since: dayStart)
        let lifetime = spentLifetime(in: context)
        guard budget.allows(spentToday: today, spentLifetime: lifetime) else {
            throw AIBudgetError.exhausted(spentToday: today, spentLifetime: lifetime)
        }

        let (value, cost) = try await call()
        context.insert(AICall(kind: kind, cost: cost, at: .now))
        try? context.save()
        return (value, cost)
    }
}
