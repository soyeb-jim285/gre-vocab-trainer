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

/// What kind of fixed test to run instead of the open-ended study queue.
enum QuizSpec: Equatable {
    case deck(Deck)
    case everything

    var deckID: String? {
        if case let .deck(deck) = self { return deck.id }
        return nil
    }
}

struct SessionSummary: Equatable {
    var answered: Int
    var meanScore: Int
    var isQuiz: Bool
}

@Observable
@MainActor
final class SessionViewModel {

    enum Phase: Equatable {
        case loading
        case answering
        case grading
        case reviewing(AnswerFeedback)
        /// Study only: nothing due and no new words left.
        case caughtUp(nextDue: Date?)
        case finished(SessionSummary)
        case failed(String)
    }

    private(set) var current: SessionItem?
    private(set) var phase: Phase = .loading
    /// Mean score over recent answers; nil until there is enough history.
    private(set) var recentAccuracy: Double?
    /// What this session has cost so far.
    private(set) var sessionSpend: Double = 0
    private(set) var answeredCount = 0
    /// Scores this session, for the summary and the quiz record.
    private var scores: [Int] = []
    /// Newest last; the planner keeps these out of the way.
    private var recentWordIDs: [String] = []
    /// Quiz only: the fixed list and where we are in it.
    private var queue: [SessionItem] = []
    private var queueIndex = 0
    let quiz: QuizSpec?

    /// Kept so a failed API call can be retried with the same answer.
    var definitionDraft = ""
    var sentenceDraft = ""
    var typedAnswer = ""
    private(set) var chosenOptionID: String?

    private let context: ModelContext
    private let catalog: WordCatalog
    private let settings: AppSettings

    /// Quiz: fraction done. Study is open-ended, so nil hides the bar.
    var progress: Double? {
        guard quiz != nil, !queue.isEmpty else { return nil }
        return Double(queueIndex) / Double(queue.count)
    }

    init(context: ModelContext, catalog: WordCatalog, settings: AppSettings, quiz: QuizSpec? = nil) {
        self.context = context
        self.catalog = catalog
        self.settings = settings
        self.quiz = quiz
    }

    // MARK: - Lifecycle

    func start(now: Date = .now) {
        phase = .loading
        answeredCount = 0
        scores = []
        recentWordIDs = []
        sessionSpend = 0
        resetDrafts()
        if let quiz {
            let cards = Array(ReviewRecorder.cardsByID(in: context).values)
            let seed = UInt64(now.timeIntervalSince1970)
            queue = switch quiz {
            case let .deck(deck):
                QuizPlanner.deckTest(deck: deck, cards: cards, catalog: catalog, seed: seed)
            case .everything:
                QuizPlanner.globalTest(cards: cards, catalog: catalog, scheduler: settings.scheduler,
                                       seed: seed, now: now)
            }
            queueIndex = 0
            current = queue.first
            phase = current == nil ? .finished(summary()) : .answering
        } else {
            loadNext(now: now)
        }
    }

    /// Study: ask the planner for one more card against the freshest state.
    private func loadNext(allowEarly: Bool = false, now: Date = .now) {
        let cards = Array(ReviewRecorder.cardsByID(in: context).values)
        recentAccuracy = ReviewRecorder.recentAccuracy(in: context)
        let item = SessionPlanner.next(
            cards: cards, catalog: catalog, settings: settings.sessionSettings,
            scheduler: settings.scheduler, recentAccuracy: recentAccuracy,
            recentWordIDs: recentWordIDs, allowEarly: allowEarly, now: now
        )
        current = item
        guard let item else {
            phase = .caughtUp(nextDue: SessionPlanner.nextDue(cards: cards, now: now))
            return
        }
        // A new word moves the deck pointer, so the Decks tab and the next
        // launch pick up where this one left off.
        if item.card.reviewCount == 0, let deck = catalog.deck(containing: item.word.id) {
            settings.currentDeckID = deck.id
        }
        phase = .answering
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

    /// Four words for a fill-in-the-blank, ordered as the plain multiple-choice
    /// options are so position never gives the answer away.
    func clozeOptions(for item: SessionItem) -> [Word] {
        let distractors = DistractorPicker.clozeDistractors(for: item.word, from: catalog, count: 3)
        return (distractors + [item.word]).sorted {
            stableSortKey($0.id, salt: "cloze-" + item.word.id)
                < stableSortKey($1.id, salt: "cloze-" + item.word.id)
        }
    }

    /// The tested meaning plus the everyday ones it is confused with.
    func senseOptions(for item: SessionItem) -> [String] {
        let wrong = DistractorPicker.senseDistractors(for: item.word, from: catalog, count: 3)
        return (wrong + [item.word.teachingDefinition]).sorted {
            stableSortKey($0, salt: "sense-" + item.word.id)
                < stableSortKey($1, salt: "sense-" + item.word.id)
        }
    }

    /// One blanked sentence, chosen per card so a word met twice is not asked
    /// with the same sentence both times.
    func clozeSentence(for item: SessionItem) -> String {
        let options = item.word.gre?.cloze ?? []
        guard !options.isEmpty else { return "" }
        return options[item.card.reviewCount % options.count]
    }

    /// The sentence a "which meaning" question is asked about. Unblanked: the
    /// word is exactly what the learner has to interpret.
    func senseSentence(for item: SessionItem) -> String {
        let options = item.word.gre?.sentences ?? []
        guard !options.isEmpty else { return "" }
        return options[item.card.reviewCount % options.count]
    }

    func submitCloze(_ chosen: Word) {
        guard let item = current else { return }
        chosenOptionID = chosen.id
        let correct = chosen.id == item.word.id
        finish(
            grade: Grade(score: correct ? 100 : 0),
            feedback: AnswerFeedback(
                score: correct ? 100 : 0,
                rating: Grade(score: correct ? 100 : 0).rating(strictness: settings.strictness),
                headline: correct ? "That fits" : "Not that one",
                detail: item.word.teachingDefinition,
                // Getting it wrong in context is the moment the full entry helps.
                showsReference: !correct
            )
        )
    }

    func submitSense(_ chosen: String) {
        guard let item = current else { return }
        chosenOptionID = chosen
        let correct = chosen == item.word.teachingDefinition
        finish(
            grade: Grade(score: correct ? 100 : 0),
            feedback: AnswerFeedback(
                score: correct ? 100 : 0,
                rating: Grade(score: correct ? 100 : 0).rating(strictness: settings.strictness),
                headline: correct ? "Right meaning" : "That is the everyday meaning",
                detail: item.word.teachingDefinition,
                showsReference: true
            )
        )
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
                detail: item.word.teachingDefinition
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
                    ? item.word.teachingDefinition
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
                referenceDefinition: item.word.teachingDefinition,
                partOfSpeech: item.word.primaryPartOfSpeech.rawValue,
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
                // Nothing was produced, so the full entry is the whole lesson.
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
        answeredCount += 1
        scores.append(grade.score)
        recentWordIDs.append(item.card.wordID)
        phase = .reviewing(feedback)
    }

    func advance() {
        resetDrafts()
        if quiz != nil {
            queueIndex += 1
            current = queueIndex < queue.count ? queue[queueIndex] : nil
            if current == nil { finishQuiz() } else { phase = .answering }
        } else {
            loadNext()
        }
    }

    /// Study: wrap up with a summary.
    func stop() {
        current = nil
        phase = .finished(summary())
    }

    /// Caught up but not done: review the weakest memories ahead of time.
    func keepGoing() {
        loadNext(allowEarly: true)
    }

    private func summary() -> SessionSummary {
        let mean = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        return SessionSummary(answered: answeredCount, meanScore: mean, isQuiz: quiz != nil)
    }

    private func finishQuiz() {
        let result = summary()
        if result.answered >= QuizPlanner.minimumWords {
            context.insert(QuizRecord(deckID: quiz?.deckID, score: result.meanScore,
                                      wordCount: result.answered, takenAt: .now))
            try? context.save()
        }
        phase = .finished(result)
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
