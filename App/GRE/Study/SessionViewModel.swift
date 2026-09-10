import Foundation
import GRECore
import Observation
import SwiftData

/// What the learner sees after answering.
///
/// Wraps the judgement rather than copying its fields out, so there is no second
/// place for the score and the rating to disagree.
struct AnswerFeedback: Equatable {
    /// The parts only a graded answer has.
    struct Extras: Equatable {
        var sentenceFeedback: String?
        var correctedSentence: String?
        var missedNuances: [String] = []
        var memorableSentence: String?
    }

    var judgement: Judgement
    /// What this grade cost, when a model was involved.
    var cost: CallCost?
    var extras = Extras()

    var score: Int { judgement.grade.score }
    var rating: FSRSRating { judgement.rating }
    var headline: String { judgement.headline }
    var detail: String { judgement.detail }
    /// Worth printing the dictionary entry after writing, where the learner
    /// produced the meaning themselves; noise after multiple choice, which
    /// already showed the definition.
    var showsReference: Bool { judgement.showsReference }
}

/// A fixed queue instead of the open-ended study session.
enum SessionShape: Equatable {
    case deck(Deck)
    case everything
    /// One word, one mode, on request. Practising a word outside a session used
    /// to be a second screen with its own grading call, its own submit gating
    /// and a fabricated card invented to satisfy the feedback view. It is a
    /// queue of one.
    case practise(word: Word, mode: StudyMode)

    /// Only a real test is worth scoring and recording as one.
    var isTest: Bool {
        if case .practise = self { return false }
        return true
    }

    var deckID: String? {
        if case let .deck(deck) = self { return deck.id }
        return nil
    }
}

/// What the session is showing right now: a word being taught, or a question.
///
/// An enum rather than an optional pair, so "introducing" cannot coexist with
/// "asking" and every screen has to handle both.
enum SessionCard: Equatable {
    case introduce(word: Word, card: StudyCard)
    case drill(SessionItem)

    var word: Word {
        switch self {
        case let .introduce(word, _): word
        case let .drill(item): item.word
        }
    }

    var card: StudyCard {
        switch self {
        case let .introduce(_, card): card
        case let .drill(item): item.card
        }
    }

    var item: SessionItem? {
        if case let .drill(item) = self { return item }
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
        /// Meeting a word for the first time. Nothing to grade.
        case introducing
        case answering
        case grading
        case reviewing(AnswerFeedback)
        /// Study only: nothing due and no new words left.
        case caughtUp(nextDue: Date?)
        case finished(SessionSummary)
    }

    private(set) var current: SessionCard?
    /// The day's shape, recomputed whenever a card is served so the countdown on
    /// screen is never behind the work.
    private(set) var day: DayPlan?
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
    private var queue: [SessionCard] = []
    private var queueIndex = 0
    let quiz: SessionShape?

    /// A failed call, shown above the answer rather than instead of it, so the
    /// learner's typing is still on screen to resubmit.
    private(set) var lastError: String?
    /// What was picked, so the feedback can show it beside the right answer.
    private(set) var chosenOptionID: String?

    /// A suspending clock, not a date: a clock change or an NTP correction would
    /// otherwise land in the middle of an answer and read as hesitation.
    private var clock = AnswerClock()

    private let context: ModelContext
    private let catalog: WordCatalog
    private let settings: AppSettings
    private let index: MasteryIndex

    /// Quiz: fraction done. Study is open-ended, so nil hides the bar.
    var progress: Double? {
        guard quiz != nil, !queue.isEmpty else { return nil }
        return Double(queueIndex) / Double(queue.count)
    }

    init(
        context: ModelContext, catalog: WordCatalog, settings: AppSettings,
        index: MasteryIndex, quiz: SessionShape? = nil
    ) {
        self.context = context
        self.catalog = catalog
        self.settings = settings
        self.index = index
        self.quiz = quiz
    }

    // MARK: - Lifecycle

    func start(now: Date = .now) {
        phase = .loading
        answeredCount = 0
        scores = []
        recentWordIDs = []
        sessionSpend = 0
        chosenOptionID = nil
        lastError = nil
        if let quiz {
            let cards = Array(ReviewRecorder.cardsByID(in: context).values)
            let seed = UInt64(now.timeIntervalSince1970)
            queue = switch quiz {
            case let .deck(deck):
                QuizPlanner.deckTest(deck: deck, cards: cards, catalog: catalog, seed: seed)
                    .map(SessionCard.drill)
            case .everything:
                QuizPlanner.globalTest(cards: cards, catalog: catalog, scheduler: settings.scheduler,
                                       seed: seed, now: now).map(SessionCard.drill)
            case let .practise(word, mode):
                // The word's real card, so practice moves the same schedule a
                // session would rather than scheduling a card nobody owns.
                [.drill(SessionItem(
                    card: ReviewRecorder.existing(word.id, in: context)?.studyCard
                        ?? StudyCard(wordID: word.id),
                    word: word, mode: mode
                ))]
            }
            queueIndex = 0
            current = queue.first
            if current == nil { phase = .finished(summary()) } else { beginAnswering() }
        } else {
            loadNext(now: now)
        }
    }

    /// Study: one more card, against freshly read state.
    ///
    /// Three decisions, each in its own place: the day says how many new words
    /// are still allowed, the queue picks which word, and the curriculum picks
    /// which question. None of them used to be separable.
    private func loadNext(allowEarly: Bool = false, now: Date = .now) {
        let cards = Array(ReviewRecorder.cardsByID(in: context).values)
        recentAccuracy = ReviewRecorder.recentAccuracy(in: context)

        let today = ReviewRecorder.todaysWork(in: context, since: settings.dayStart(at: now))
        let plan = DayPlanner.plan(
            cards: cards, catalog: catalog, profile: settings.profile,
            introducedToday: today.introduced, answeredToday: today.answered, now: now
        )
        day = plan

        let picked = SessionQueue.nextCard(
            cards: cards, catalog: catalog, currentDeckID: settings.currentDeckID,
            // Early review is the learner asking to keep going past the day's
            // plan, so the allowance stops applying.
            newWordsAllowed: allowEarly ? .max : plan.newWordsRemaining,
            scheduler: settings.scheduler, recentAccuracy: recentAccuracy,
            recentWordIDs: recentWordIDs, allowEarly: allowEarly, now: now
        )

        guard let picked, let word = catalog[picked.wordID] else {
            current = nil
            phase = .caughtUp(nextDue: SessionQueue.nextDue(cards: cards, now: now))
            return
        }

        // A new word moves the deck pointer, so the Library and the next launch
        // pick up where this one left off.
        if !picked.isIntroduced, let deck = catalog.deck(containing: word.id) {
            settings.currentDeckID = deck.id
        }

        switch Curriculum.step(
            for: picked, word: word,
            competence: ReviewRecorder.competence(for: word.id, in: context),
            settings: settings.sessionSettings
        ) {
        case .introduce:
            current = .introduce(word: word, card: picked)
            phase = .introducing
        case let .drill(mode):
            current = .drill(SessionItem(card: picked, word: word, mode: mode))
            beginAnswering()
        }
    }

    /// Done reading. Nothing is graded, and nothing is scheduled: the card stays
    /// due, so the very next thing is a real question about the word just met.
    func finishIntroduction() {
        guard case let .introduce(word, _)? = current else { return }
        ReviewRecorder.introduce(wordID: word.id, in: context, index: index)
        loadNext()
    }

    /// Called wherever a card becomes answerable, which is the only honest place
    /// to start counting: not in `body`, which runs whenever SwiftUI likes.
    private func beginAnswering() {
        clock.start()
        phase = .answering
    }

    // MARK: - Answering

    /// Everything the question needs, built once when the card is served.
    ///
    /// Options are sorted by a stable hash rather than shuffled, so the right
    /// answer neither sits in the same slot every time nor moves between
    /// launches: position can never be the tell, and it can never be a memory
    /// aid either.
    func options(for item: SessionItem) -> AnswerOptions {
        switch item.mode {
        case .multipleChoice:
            let wrong = DistractorPicker.definitionDistractors(for: item.word, from: catalog, count: 3)
            return AnswerOptions(
                choices: ordered(wrong + [item.word.teachingDefinition],
                                 salt: item.word.id).map(AnswerOption.init)
            )

        case .contextCloze:
            let wrong = DistractorPicker.clozeDistractors(for: item.word, from: catalog, count: 3)
            let words = (wrong + [item.word]).sorted {
                stableSortKey($0.id, salt: "cloze-" + item.word.id)
                    < stableSortKey($1.id, salt: "cloze-" + item.word.id)
            }
            return AnswerOptions(
                choices: words.map(AnswerOption.init),
                sentence: pick(item.word.gre?.cloze ?? [], for: item),
                choicesAreWords: true
            )

        case .senseInContext:
            let wrong = DistractorPicker.senseDistractors(for: item.word, from: catalog, count: 3)
            return AnswerOptions(
                choices: ordered(wrong + [item.word.teachingDefinition],
                                 salt: "sense-" + item.word.id).map(AnswerOption.init),
                sentence: pick(item.word.gre?.sentences ?? [], for: item)
            )

        case .reverseRecall, .spelling, .defineAndUse:
            return AnswerOptions()
        }
    }

    private func ordered(_ options: [String], salt: String) -> [String] {
        options.sorted { stableSortKey($0, salt: salt) < stableSortKey($1, salt: salt) }
    }

    /// Chosen per card, so a word met twice is not asked with the same sentence
    /// both times.
    private func pick(_ options: [String], for item: SessionItem) -> String {
        guard !options.isEmpty else { return "" }
        return options[item.card.reviewCount % options.count]
    }

    /// The one way an answer is submitted, whatever asked for it.
    ///
    /// Every mode reaches the same judge, so the score, the rating and the words
    /// the learner reads are decided together instead of being re-decided six
    /// times in the view layer.
    func submit(_ draft: AnswerDraft) async {
        guard let item = current?.item, phase == .answering else { return }
        let latency = clock.stop()
        lastError = nil
        if case let .choice(chosen) = draft { chosenOptionID = chosen }

        if let judgement = AnswerJudge.judge(
            draft, item: item, strictness: settings.strictness,
            latency: clock.isTainted ? nil : latency,
            confidence: settings.profile.confidence
        ) {
            finish(judgement, latency: latency)
            return
        }
        await gradeRemotely(draft, item: item, latency: latency)
    }

    /// Give up on the current card.
    func admitNotKnowing() async {
        await submit(.gaveUp)
    }

    /// Audio played, so the time on the clock is reading time, not recall time.
    func noteAudioPlayed() {
        clock.taint()
    }

    func pauseTimer() { clock.pause() }
    func resumeTimer() { clock.resume() }

    private func gradeRemotely(_ draft: AnswerDraft, item: SessionItem, latency: Duration) async {
        guard case let .written(definition, sentence) = draft else { return }
        guard settings.hasAPIKey else {
            lastError = OpenRouterError.missingAPIKey.description
            return
        }
        phase = .grading
        do {
            let (result, cost) = try await AILedger.spend(
                .grading, budget: settings.profile.budget,
                dayStart: settings.dayStart(), in: context
            ) {
                try await settings.client().gradeWithCost(
                    word: item.word.word,
                    referenceDefinition: item.word.teachingDefinition,
                    partOfSpeech: item.word.primaryPartOfSpeech.rawValue,
                    learnerDefinition: definition,
                    learnerSentence: sentence,
                    model: settings.gradingModel
                )
            }
            sessionSpend += cost?.usd ?? 0
            finish(
                Judgement(
                    grade: Grade(score: result.combinedScore),
                    // The model rated the answer itself; that beats mapping a
                    // number it also produced.
                    rating: result.rating,
                    headline: Self.headline(for: result.combinedScore),
                    detail: result.definitionFeedback,
                    showsReference: true
                ),
                latency: latency,
                cost: cost,
                extras: AnswerFeedback.Extras(
                    sentenceFeedback: result.sentenceFeedback,
                    correctedSentence: result.correctedSentence,
                    missedNuances: result.missedNuances,
                    memorableSentence: result.memorableSentence
                )
            )
        } catch {
            // Deliberately not scheduled: a network failure is not evidence
            // about the learner's memory, and recording it would poison the
            // scheduler. The answer stays on screen.
            lastError = (error as? OpenRouterError)?.description ?? error.localizedDescription
            phase = .answering
        }
    }

    // MARK: - Scheduling

    private func finish(
        _ judgement: Judgement, latency: Duration,
        cost: CallCost? = nil, extras: AnswerFeedback.Extras = .init()
    ) {
        guard let item = current?.item else { return }
        ReviewRecorder.record(
            wordID: item.card.wordID, mode: item.mode, grade: judgement.grade,
            rating: judgement.rating, scheduler: settings.scheduler, in: context, index: index,
            latency: latency, latencyTainted: clock.isTainted
        )
        answeredCount += 1
        scores.append(judgement.grade.score)
        recentWordIDs.append(item.card.wordID)
        phase = .reviewing(AnswerFeedback(judgement: judgement, cost: cost, extras: extras))
    }

    func advance() {
        chosenOptionID = nil
        lastError = nil
        if quiz != nil {
            queueIndex += 1
            current = queueIndex < queue.count ? queue[queueIndex] : nil
            if current == nil { finishQuiz() } else { beginAnswering() }
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
        return SessionSummary(answered: answeredCount, meanScore: mean,
                              isQuiz: quiz?.isTest ?? false)
    }

    private func finishQuiz() {
        let result = summary()
        if quiz?.isTest == true, result.answered >= QuizPlanner.minimumWords {
            context.insert(QuizRecord(deckID: quiz?.deckID, score: result.meanScore,
                                      wordCount: result.answered, takenAt: .now))
            try? context.save()
        }
        phase = .finished(result)
    }

    static func headline(for score: Int) -> String {
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

/// How long an answer took.
///
/// A suspending clock rather than dates: a manual clock change or an NTP
/// correction landing mid-card would otherwise be recorded as hesitation. It
/// also stops while the device is asleep, and `pause` covers the other half --
/// the app in the background on a device that is awake.
struct AnswerClock {
    private var started: SuspendingClock.Instant?
    private var accumulated: Duration = .zero
    /// Whatever is on the clock is not evidence about recall.
    private(set) var isTainted = false

    mutating func start() {
        started = SuspendingClock.now
        accumulated = .zero
        isTainted = false
    }

    mutating func pause() {
        guard let started else { return }
        accumulated += SuspendingClock.now - started
        self.started = nil
    }

    mutating func resume() {
        guard started == nil else { return }
        started = SuspendingClock.now
    }

    /// Reading the sentence aloud is reading time, not recall time.
    mutating func taint() { isTainted = true }

    mutating func stop() -> Duration {
        pause()
        // Nobody deliberates for a minute; they put the phone down. Recording it
        // as hesitation would drag the word's schedule for no reason.
        if accumulated > .seconds(60) { isTainted = true }
        return accumulated
    }
}
