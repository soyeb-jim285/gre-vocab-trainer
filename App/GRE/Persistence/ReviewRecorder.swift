import Foundation
import GRECore
import SwiftData

/// Applies a graded answer to a word's schedule.
///
/// Shared by the study session and one-off writing practice so a review recorded
/// outside a session moves the schedule exactly the same way -- two code paths
/// updating FSRS state differently would be a silent scheduling bug.
@MainActor
enum ReviewRecorder {

    @discardableResult
    static func record(
        wordID: String, mode: StudyMode, grade: Grade, rating: FSRSRating,
        scheduler: FSRS, in context: ModelContext, cost: CallCost? = nil, at date: Date = .now
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

        context.insert(ReviewRecord(
            wordID: wordID, reviewedAt: date, mode: mode,
            score: grade.score, rating: rating, cost: cost
        ))
        try? context.save()
        return record
    }

    /// Mean score over the learner's most recent answers, which is what the
    /// adaptive word order reads. Nil until there is enough to judge by.
    static func recentAccuracy(in context: ModelContext, over count: Int = 40) -> Double? {
        var descriptor = FetchDescriptor<ReviewRecord>(
            sortBy: [SortDescriptor(\.reviewedAt, order: .reverse)]
        )
        descriptor.fetchLimit = count
        guard let recent = try? context.fetch(descriptor), recent.count >= 5 else { return nil }
        return Double(recent.map(\.score).reduce(0, +)) / Double(recent.count)
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

    static func totalSpend(in context: ModelContext) -> Double {
        let all = (try? context.fetch(FetchDescriptor<ReviewRecord>())) ?? []
        return all.compactMap(\.costUSD).reduce(0, +)
    }

    static func existing(_ wordID: String, in context: ModelContext) -> CardRecord? {
        var descriptor = FetchDescriptor<CardRecord>(predicate: #Predicate { $0.wordID == wordID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
