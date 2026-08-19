import Foundation
import GRECore
import Observation
import SwiftData

/// What the learner sees after answering.
struct AnswerFeedback: Equatable {
    var score: Int
    var rating: FSRSRating
    var headline: String
    var detail: String
    /// Only the graded mode fills these in.
    var sentenceFeedback: String?
    var correctedSentence: String?
    var missedNuances: [String] = []
    var memorableSentence: String?
    /// What this grade cost, when a model was involved.
    var cost: CallCost?
    /// Whether to print the dictionary entry underneath. Worth it after writing,
    /// where the learner produced the meaning themselves and needs to check it;
    /// noise after multiple choice, which already showed the definition.
    var showsReference = false
}

@Observable
@MainActor
final class SessionViewModel {

    enum Phase: Equatable {
        case loading
        case answering
        case grading
        case reviewing(AnswerFeedback)
        case finished
        case failed(String)
    }

    private(set) var items: [SessionItem] = []
    private(set) var index = 0
    private(set) var phase: Phase = .loading
    /// Mean score over recent answers; nil until there is enough history.
    private(set) var recentAccuracy: Double?
    /// What this session has cost so far.
    private(set) var sessionSpend: Double = 0

    /// Kept so a failed API call can be retried with the same answer.
    var definitionDraft = ""
    var sentenceDraft = ""
    var typedAnswer = ""
    private(set) var chosenOptionID: String?

    private let context: ModelContext
    private let catalog: WordCatalog
    private let settings: AppSettings

    var current: SessionItem? { index < items.count ? items[index] : nil }
    var progress: Double { items.isEmpty ? 0 : Double(index) / Double(items.count) }
    var answeredCount: Int { index }

    init(context: ModelContext, catalog: WordCatalog, settings: AppSettings) {
        self.context = context
        self.catalog = catalog
        self.settings = settings
    }

    // MARK: - Lifecycle

    func start(now: Date = .now) {
        phase = .loading
        do {
            let records = try context.fetch(FetchDescriptor<CardRecord>())
            // The adaptive order reads this to decide how hard the new words
            // should be, so it has to be recomputed each session.
            recentAccuracy = ReviewRecorder.recentAccuracy(in: context)
            items = SessionPlanner.plan(
                cards: records.map(\.studyCard), catalog: catalog,
                settings: settings.sessionSettings, recentAccuracy: recentAccuracy, now: now
            )
            index = 0
            resetDrafts()
            phase = items.isEmpty ? .finished : .answering
        } catch {
            phase = .failed("Could not load your cards: \(error.localizedDescription)")
        }
    }

    private func resetDrafts() {
        definitionDraft = ""
        sentenceDraft = ""
        typedAnswer = ""
        chosenOptionID = nil
    }

    // MARK: - Answering

    func multipleChoiceOptions(for item: SessionItem) -> [Word] {
        let distractors = DistractorPicker.distractors(for: item.word, from: catalog, count: 3)
        // Sorted by a stable hash rather than shuffled, so the right answer does
        // not sit in the same slot every time and cannot be guessed positionally.
        return (distractors + [item.word]).sorted {
            stableSortKey($0.id, salt: item.word.id) < stableSortKey($1.id, salt: item.word.id)
        }
    }

    func submitMultipleChoice(_ chosen: Word) {
        guard let item = current else { return }
        chosenOptionID = chosen.id
        let correct = chosen.id == item.word.id
        finish(
            grade: Grade(score: correct ? 100 : 0),
            feedback: AnswerFeedback(
                score: correct ? 100 : 0,
                rating: Grade(score: correct ? 100 : 0).rating(strictness: settings.strictness),
                headline: correct ? "Correct" : "Not quite",
                detail: item.word.primarySense.definition
            )
        )
    }

    func submitSpelling() {
        guard let item = current else { return }
        let result = LocalGrader.gradeSpelling(typed: typedAnswer, expected: item.word.word)
        finish(
            grade: result.grade,
            feedback: AnswerFeedback(
                score: result.grade.score,
                rating: result.grade.rating(strictness: settings.strictness),
                headline: result.isExact ? "Spelled correctly" : "Spelling is off",
                detail: result.isExact
                    ? item.word.primarySense.definition
                    : "You wrote \"\(typedAnswer.trimmingCharacters(in: .whitespaces))\" — it's \"\(item.word.word)\"."
            )
        )
    }

    func submitRecall() {
        guard let item = current else { return }
        let grade = LocalGrader.gradeRecall(typed: typedAnswer, expected: item.word.word)
        finish(
            grade: grade,
            feedback: AnswerFeedback(
                score: grade.score,
                rating: grade.rating(strictness: settings.strictness),
                headline: grade.score == 100 ? "Got it" : (grade.score > 0 ? "Close" : "The word was"),
                detail: item.word.word,
                showsReference: true
            )
        )
    }

    func submitDefineAndUse() async {
        guard let item = current else { return }
        guard settings.hasAPIKey else {
            phase = .failed(OpenRouterError.missingAPIKey.description)
            return
        }
        phase = .grading
        do {
            let (result, cost) = try await settings.client().gradeWithCost(
                word: item.word.word,
                referenceDefinition: item.word.primarySense.definition,
                partOfSpeech: item.word.primarySense.pos.rawValue,
                learnerDefinition: definitionDraft,
                learnerSentence: sentenceDraft,
                model: settings.gradingModel
            )
            sessionSpend += cost?.usd ?? 0
            finish(
                grade: Grade(score: result.combinedScore),
                rating: result.rating,
                cost: cost,
                feedback: AnswerFeedback(
                    score: result.combinedScore,
                    rating: result.rating,
                    headline: headline(for: result.combinedScore),
                    detail: result.definitionFeedback,
                    sentenceFeedback: result.sentenceFeedback,
                    correctedSentence: result.correctedSentence,
                    missedNuances: result.missedNuances,
                    memorableSentence: result.memorableSentence,
                    cost: cost,
                    showsReference: true
                )
            )
        } catch {
            // Deliberately not scheduled: a network failure is not evidence about
            // the learner's memory, and recording it would poison the scheduler.
            let message = (error as? OpenRouterError)?.description ?? error.localizedDescription
            phase = .failed(message)
        }
    }

    /// Give up on the current card.
    ///
    /// Scored zero and rated Again, so the word comes back almost immediately.
    /// No model call: there is nothing to grade, and paying to be told an empty
    /// answer is wrong would be absurd.
    func admitNotKnowing() {
        guard let item = current else { return }
        finish(
            grade: Grade(score: 0),
            rating: .again,
            feedback: AnswerFeedback(
                score: 0,
                rating: .again,
                headline: "Let's learn it",
                detail: item.mode == .reverseRecall || item.mode == .spelling
                    ? item.word.word
                    : "",
                showsReference: true
            )
        )
    }

    /// Return to the answer screen with the drafts intact after a failed call.
    func retryAfterFailure() {
        phase = .answering
    }

    // MARK: - Scheduling

    /// The model's own rating wins when it gave one; otherwise the score maps.
    private func finish(
        grade: Grade, rating: FSRSRating? = nil, cost: CallCost? = nil, feedback: AnswerFeedback
    ) {
        guard let item = current else { return }
        let rating = rating ?? grade.rating(strictness: settings.strictness)

        ReviewRecorder.record(
            wordID: item.card.wordID, mode: item.mode, grade: grade, rating: rating,
            scheduler: settings.scheduler, in: context, cost: cost
        )
        phase = .reviewing(feedback)
    }

    func advance() {
        index += 1
        resetDrafts()
        phase = index < items.count ? .answering : .finished
    }

    private func headline(for score: Int) -> String {
        switch score {
        case 90...: "Excellent"
        case 70..<90: "Good"
        case 50..<70: "Shaky"
        default: "Needs work"
        }
    }
}

/// Stable ordering key so option positions survive a relaunch.
private func stableSortKey(_ id: String, salt: String) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in (salt + id).utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return hash
}
