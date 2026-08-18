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
        scheduler: FSRS, in context: ModelContext, at date: Date = .now
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
            score: grade.score, rating: rating
        ))
        try? context.save()
        return record
    }

    static func existing(_ wordID: String, in context: ModelContext) -> CardRecord? {
        var descriptor = FetchDescriptor<CardRecord>(predicate: #Predicate { $0.wordID == wordID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
