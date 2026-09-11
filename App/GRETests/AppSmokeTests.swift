import AVFoundation
import Foundation
import GRECore
import SwiftData
import Testing
@testable import GRE

/// The app target's own tests. GRECore's logic is covered on Linux; these cover
/// the parts that only exist once SwiftData and the app are in the picture.
@Suite @MainActor
struct AppSmokeTests {

    /// A throwaway mastery cache. These tests are about scheduling, not about
    /// what the rings show, but the recorder now insists on being handed one so
    /// no screen can go stale behind a write.
    private let index = MasteryIndex()

    /// Walks past the teaching card every unmet word now starts with.
    ///
    /// Teaching schedules nothing, so the word stays due and the very next card
    /// is a real question about it.
    @discardableResult
    private func drill(_ model: SessionViewModel) throws -> SessionItem {
        if case .introduce? = model.current { model.finishIntroduction() }
        return try #require(model.current?.item)
    }

    /// The right answer for whatever mode a card happens to be in.
    ///
    /// A quiz rotates modes, and they disagree about what an answer even is:
    /// cloze is graded on the word, the other tap modes on the definition text,
    /// and two modes want it typed.
    private func correctDraft(for item: SessionItem) -> AnswerDraft {
        item.mode.isTapToAnswer
            ? .choice(AnswerJudge.correctChoice(for: item))
            : .typed(item.word.word)
    }

    private func inMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CardRecord.self, ReviewRecord.self, DeepDiveRecord.self, QuizRecord.self,
            AICall.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func theBundledCatalogLoadsInsideTheApp() throws {
        let catalog = try WordCatalog.bundled()
        #expect(catalog.words.count > 2500)
    }

    @Test func cardRecordRoundTripsFsrsState() throws {
        let context = try inMemoryContext()
        let record = CardRecord(wordID: "abate")
        context.insert(record)

        let scheduled = FSRS(enableFuzzing: false)
            .review(FSRSCard(), rating: .good, at: Date(timeIntervalSince1970: 0))
        record.fsrs = scheduled

        #expect(record.fsrs == scheduled)
        #expect(record.stateRaw == scheduled.state.rawValue)
    }

    @Test func aSessionPlansAndSchedulesTheFirstCard() async throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)
        model.start()

        // A word never seen is taught, not tested.
        #expect(model.current != nil)
        guard case let .introduce(word, card)? = model.current else {
            Issue.record("a brand-new word should be introduced, not questioned")
            return
        }
        #expect(card.isIntroduced == false)
        model.finishIntroduction()

        let first = try #require(model.current?.item)
        #expect(first.word.id == word.id, "the question should be about the word just taught")
        #expect(first.mode == .multipleChoice)

        await model.submit(.choice(first.word.teachingDefinition))
        guard case let .reviewing(feedback) = model.phase else {
            Issue.record("expected review phase, got \(model.phase)")
            return
        }
        #expect(feedback.score == 100)

        let saved = try context.fetch(FetchDescriptor<CardRecord>())
        #expect(saved.count == 1)
        #expect(saved[0].reviewCount == 1)
        // A scheduled card must have moved off the epoch default.
        #expect(saved[0].due > Date(timeIntervalSince1970: 1))
    }

    @Test func aWrongMultipleChoiceAnswerSchedulesTheCardToReturn() async throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)
        model.start()
        let item = try drill(model)
        let wrong = try #require(model.options(for: item).choices.map(\.id)
            .first { $0 != item.word.teachingDefinition })

        await model.submit(.choice(wrong))
        guard case let .reviewing(feedback) = model.phase else {
            Issue.record("expected review phase")
            return
        }
        #expect(feedback.score == 0)
        #expect(feedback.rating == .again)
    }

    @Test func multipleChoiceAlwaysOffersTheRightAnswerAmongFour() async throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)
        model.start()
        for _ in 0..<12 {
            let item = try drill(model)
            let options = model.options(for: item).choices.map(\.id)
            #expect(options.count == 4, "\(item.word.id) offered \(options.count) options")
            #expect(options.contains(item.word.teachingDefinition),
                    "\(item.word.id) was not among its own options")
            await model.submit(.choice(item.word.teachingDefinition))
            model.advance()
        }
    }

    @Test func withoutAKeyTheGradedModeIsNeverOffered() throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        #expect(settings.hasAPIKey == false, "no key should be present in a fresh test suite")
        #expect(settings.sessionSettings.aiEnabled == false)
    }

    // MARK: - Voice selection

    @Test func aVoiceIsAlwaysResolvedByIdentifierNotByLanguage() throws {
        // AVSpeechSynthesisVoice(language:) regressed in iOS 26 and returns the
        // system default regardless of accent, which would flatten the picker.
        // Resolving through the catalog must give a concrete, distinct voice.
        let american = try #require(VoiceCatalog.best(for: .american))
        #expect(american.identifier.isEmpty == false)
        #expect(american.language.lowercased().hasPrefix("en-us"))

        if let british = VoiceCatalog.best(for: .british) {
            #expect(british.language.lowercased().hasPrefix("en-gb"))
            #expect(british.identifier != american.identifier,
                    "accents resolved to the same voice — the regression is not being worked around")
        }
    }

    @Test func voicesAreOfferedBestQualityFirst() {
        for accent in SpeechAccent.allCases {
            let ranks = VoiceCatalog.voices(for: accent).map(\.quality.rank)
            #expect(ranks == ranks.sorted(by: >), "\(accent.label) voices are not best-first")
        }
    }

    @Test func aPinnedVoiceWinsAndAMissingOneFallsBack() throws {
        let best = try #require(VoiceCatalog.best(for: .american))
        let pinned = try #require(VoiceCatalog.voice(identifier: best.identifier, accent: .american))
        #expect(pinned.identifier == best.identifier)

        // A voice the user has since deleted must not silence the app.
        let fallback = VoiceCatalog.voice(identifier: "com.example.deleted.voice", accent: .american)
        #expect(fallback?.identifier == best.identifier)
    }

    // MARK: - Writing practice

    @Test func aWordIsNotQuestionedSecondsAfterItsAnswerWasOnScreen() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)
        model.start()

        guard case let .introduce(taught, _)? = model.current else {
            Issue.record("expected a teaching card")
            return
        }
        model.finishIntroduction()

        // Asking "which definition fits?" three seconds after showing the
        // definition tests short-term memory and teaches the scheduler nothing.
        #expect(model.current?.word.id != taught.id,
                "the word was questioned immediately after its answer was shown")

        // It still has to come back soon, not be lost behind the whole catalog.
        var gap = 0
        var met: [String] = []
        while gap < 8 {
            guard let card = model.current else { break }
            if card.word.id == taught.id { break }
            met.append(card.word.id)
            model.finishIntroduction()
            gap += 1
        }
        #expect(model.current?.word.id == taught.id,
                "the taught word never came back; met \(met) instead")
        #expect(model.current?.item?.mode == .multipleChoice,
                "it should come back as a question, not as another teaching card")
        #expect(gap >= 1 && gap <= 5, "a batch of \(gap) words before the first question")
    }

    @Test func aBrandNewWordIsTaughtBeforeAnythingIsAsked() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        // Even set to write straight away: "straight away" means straight after
        // meeting the word, not instead of meeting it. Which threshold applies
        // once it has been met is Curriculum's business and is tested there,
        // without needing a Keychain a simulator test bundle cannot write to.
        settings.writingModeAfterReviews = 0

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)
        model.start()
        guard case .introduce? = model.current else {
            Issue.record("a brand-new word should be taught first, got \(String(describing: model.current))")
            return
        }
        // Teaching schedules nothing, so the card is still due; it is the
        // recently-shown window, not the scheduler, that holds it back.
        model.finishIntroduction()
        #expect(model.current != nil)
        #expect(model.cardsSeen == 1, "reading a teaching card is something to stop after")
    }

    @Test func practisingAWordOutsideASessionSchedulesItTheSameWay() throws {
        let context = try inMemoryContext()
        let scheduler = FSRS(enableFuzzing: false)

        let record = ReviewRecorder.record(
            wordID: "abate", mode: .defineAndUse, grade: Grade(score: 95),
            rating: .easy, scheduler: scheduler, in: context, index: index
        )
        #expect(record.reviewCount == 1)
        #expect(record.due > .now)

        // Same word again, and the schedule must keep moving rather than reset.
        let firstDue = record.due
        let again = ReviewRecorder.record(
            wordID: "abate", mode: .defineAndUse, grade: Grade(score: 95),
            rating: .easy, scheduler: scheduler, in: context, index: index
        )
        #expect(again.reviewCount == 2)
        #expect(again.due > firstDue)
        #expect(try context.fetch(FetchDescriptor<CardRecord>()).count == 1, "practice created a duplicate card")
        #expect(try context.fetch(FetchDescriptor<ReviewRecord>()).count == 2)
    }

    @Test func aLapseAfterGraduatingIsCounted() throws {
        let context = try inMemoryContext()
        let scheduler = FSRS(enableFuzzing: false)
        for _ in 0..<4 {
            ReviewRecorder.record(wordID: "laconic", mode: .defineAndUse, grade: Grade(score: 95),
                                  rating: .easy, scheduler: scheduler, in: context, index: index)
        }
        let graduated = try #require(ReviewRecorder.existing("laconic", in: context))
        #expect(graduated.fsrs.state == .review)

        let lapsed = ReviewRecorder.record(wordID: "laconic", mode: .defineAndUse, grade: Grade(score: 10),
                                           rating: .again, scheduler: scheduler, in: context, index: index)
        #expect(lapsed.lapses == 1)
    }

    // MARK: - Session mode picker

    @Test func forcingAModeRetestsEveryCardThatWay() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.forcedMode = .spelling

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)
        model.start()
        // Even a forced drill meets the word first.
        #expect(try drill(model).mode == .spelling)
    }

    @Test func autoRestoresTheLadder() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.forcedMode = nil

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)
        model.start()
        #expect(try drill(model).mode == .multipleChoice)
    }

    @Test func removingTheKeyClearsAForcedWritingMode() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.forcedMode = .defineAndUse
        settings.setAPIKey(nil)
        // Otherwise the picker would read "Writing" while the planner ran something else.
        #expect(settings.forcedMode == nil)
    }

    @Test func aForcedSpellingModeSurvivesRemovingTheKey() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.forcedMode = .spelling
        settings.setAPIKey(nil)
        #expect(settings.forcedMode == .spelling)
    }

    // MARK: - Difficulty and cost

    @Test func aMissedWordDoesNotRepeatBackToBackAndTheDeckPointerMoves() async throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)
        model.start()
        let missed = try drill(model)
        await model.admitNotKnowing()
        model.advance()
        // Rated Again → due in a minute, so within this synchronous test it is
        // not yet due; the planner's controlled-clock tests cover the return.
        var seen: [String] = []
        for _ in 0..<6 {
            guard model.current != nil, let item = try? drill(model) else { break }
            seen.append(item.word.id)
            await model.submit(correctDraft(for: item))
            model.advance()
        }
        #expect(seen.contains(missed.word.id) == false, "the same word should not repeat back-to-back")
        #expect(settings.currentDeckID == catalog.decks[0].id)
    }

    @Test func aDeckTestRecordsItsScore() async throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let deck = catalog.decks[0]
        for id in deck.wordIDs.prefix(5) {
            ReviewRecorder.record(wordID: id, mode: .multipleChoice, grade: Grade(score: 100),
                                  rating: .good, scheduler: FSRS(), in: context, index: index)
        }
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index, quiz: .deck(deck))
        model.start()
        #expect(model.progress == 0)
        while model.current != nil, let item = try? drill(model) {
            await model.submit(correctDraft(for: item))
            model.advance()
        }
        guard case let .finished(summary) = model.phase else { Issue.record("expected finished"); return }
        #expect(summary.answered == 5 && summary.meanScore == 100 && summary.isQuiz)
        #expect(ReviewRecorder.bestQuizScore(deckID: deck.id, in: context) == 100)
    }

    @Test func recentAccuracyNeedsSomeHistoryBeforeItReportsAnything() throws {
        let context = try inMemoryContext()
        let scheduler = FSRS(enableFuzzing: false)
        #expect(ReviewRecorder.recentAccuracy(in: context) == nil)

        for i in 0..<4 {
            ReviewRecorder.record(wordID: "w\(i)", mode: .spelling, grade: Grade(score: 100),
                                  rating: .easy, scheduler: scheduler, in: context, index: index)
        }
        #expect(ReviewRecorder.recentAccuracy(in: context) == nil, "four answers is not enough to judge by")

        ReviewRecorder.record(wordID: "w5", mode: .spelling, grade: Grade(score: 100),
                              rating: .easy, scheduler: scheduler, in: context, index: index)
        #expect(ReviewRecorder.recentAccuracy(in: context) == 100)
    }

    // MARK: - Context modes

    @Test func aClozeQuestionOffersFourWordsAndOneBlankedSentence() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)

        let word = try #require(catalog["abate"])
        let card = StudyCard(wordID: word.id, fsrs: FSRSCard(stability: 10, difficulty: 5,
                                                             due: .now, lastReview: .now,
                                                             state: .review, step: nil),
                             reviewCount: 3)
        let item = SessionItem(card: card, word: word, mode: .contextCloze)

        let options = model.options(for: item).choices
        #expect(options.count == 4)
        #expect(options.contains { $0.id == word.id })
        #expect(Set(options.map(\.id)).count == 4, "an option was repeated")

        let sentence = model.options(for: item).sentence
        #expect(sentence.contains("____"))
        #expect(sentence.localizedCaseInsensitiveContains(word.word) == false, "the answer is in the sentence")
    }

    @Test func answeringAClozeCorrectlyScoresAndSchedules() async throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let word = try #require(catalog["abate"])
        // A queue of one, so the question is the one under test rather than
        // whatever the curriculum thinks this learner needs.
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings,
                                     index: index, quiz: .practise(word: word, mode: .contextCloze))
        model.start()
        let item = try #require(model.current?.item)
        #expect(item.mode == .contextCloze)

        // Cloze is graded on the word, not on a definition string.
        await model.submit(.choice(item.word.id))
        guard case let .reviewing(feedback) = model.phase else {
            Issue.record("expected review phase, got \(model.phase)")
            return
        }
        #expect(feedback.score == 100)
        #expect(try context.fetch(FetchDescriptor<CardRecord>()).count == 1)
    }

    @Test func aWrongClozeShowsTheFullEntry() async throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let word = try #require(catalog["abate"])
        // A queue of one, so the question is the one under test rather than
        // whatever the curriculum thinks this learner needs.
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings,
                                     index: index, quiz: .practise(word: word, mode: .contextCloze))
        model.start()
        let item = try #require(model.current?.item)
        #expect(item.mode == .contextCloze)

        let wrong = try #require(model.options(for: item).choices.first { $0.id != item.word.id })
        await model.submit(.choice(wrong.id))
        guard case let .reviewing(feedback) = model.phase else { Issue.record("expected review"); return }
        #expect(feedback.score == 0)
        #expect(feedback.showsReference, "a wrong answer in context is when the entry helps most")
    }

    @Test func aWhichMeaningQuestionOffersTheEverydayMeaningAsBait() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)

        let word = try #require(catalog["flag"])
        #expect(word.isTrap)
        let item = SessionItem(card: StudyCard(wordID: word.id), word: word, mode: .senseInContext)

        let options = model.options(for: item).choices.map(\.id)
        #expect(options.count == 4)
        #expect(options.contains(word.teachingDefinition))
        #expect(Set(options).count == 4, "a meaning was repeated")

        // The sentence is shown unblanked: interpreting the word is the task.
        let sentence = model.options(for: item).sentence
        #expect(sentence.contains("____") == false)
        #expect(sentence.isEmpty == false)
    }

    @Test func choosingTheWrongMeaningIsMarkedWrong() async throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let word = try #require(catalog["flag"])
        // A queue of one, so the question is the one under test rather than
        // whatever the curriculum thinks this learner needs.
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings,
                                     index: index, quiz: .practise(word: word, mode: .senseInContext))
        model.start()
        let item = try #require(model.current?.item)
        #expect(item.mode == .senseInContext)
        #expect(item.word.isTrap)

        let wrong = try #require(
            model.options(for: item).choices.map(\.id).first { $0 != item.word.teachingDefinition }
        )
        await model.submit(.choice(wrong))
        guard case let .reviewing(feedback) = model.phase else { Issue.record("expected review"); return }
        #expect(feedback.score == 0)
        #expect(feedback.showsReference, "the whole point is to show the tested meaning")
    }

    @Test func choosingTheTestedMeaningScoresFull() async throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let word = try #require(catalog["flag"])
        // A queue of one, so the question is the one under test rather than
        // whatever the curriculum thinks this learner needs.
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings,
                                     index: index, quiz: .practise(word: word, mode: .senseInContext))
        model.start()
        let item = try #require(model.current?.item)
        #expect(item.mode == .senseInContext)

        await model.submit(.choice(item.word.teachingDefinition))
        guard case let .reviewing(feedback) = model.phase else { Issue.record("expected review"); return }
        #expect(feedback.score == 100)
    }

    @Test func aSessionAfterResetStartsFromTheFirstDeckAgain() async throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)
        model.start()
        for _ in 0..<4 {
            guard model.current != nil, let item = try? drill(model) else { break }
            await model.submit(correctDraft(for: item))
            model.advance()
        }
        #expect(try context.fetch(FetchDescriptor<CardRecord>()).isEmpty == false)

        try ReviewRecorder.eraseAllProgress(in: context, index: index)
        settings.resetToDefaults()

        let fresh = SessionViewModel(context: context, catalog: catalog, settings: settings, index: index)
        fresh.start()
        #expect(fresh.current?.word.id == catalog.decks[0].wordIDs[0])
        #expect(fresh.current?.card.reviewCount == 0)
    }

    @Test func resetTokenChangesSoALiveSessionRebuilds() throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let before = settings.resetToken
        settings.resetToDefaults()
        #expect(settings.resetToken != before, "a live session would keep its deleted cards")
    }

    // MARK: - Spending

    @Test func everyKindOfCallIsCountedNotJustGrading() async throws {
        let context = try inMemoryContext()
        let dayStart = Date.now.addingTimeInterval(-3600)
        let unlimited = AIBudget(dailyUSD: nil, lifetimeUSD: nil)
        #expect(AILedger.spentLifetime(in: context) == 0)

        for (kind, usd) in [(AICallKind.grading, 0.0003), (.deepDive, 0.0002), (.coach, 0.0001)] {
            _ = try await AILedger.spend(kind, budget: unlimited, dayStart: dayStart, in: context) {
                ("done", CallCost(promptTokens: 400, completionTokens: 90, usd: usd))
            }
        }
        // Deep dives and coaching used to spend money the total never saw.
        #expect(abs(AILedger.spentLifetime(in: context) - 0.0006) < 1e-9)
        #expect(abs(AILedger.spentToday(in: context, since: dayStart) - 0.0006) < 1e-9)
    }

    @Test func theCapRefusesBeforeTheCallRatherThanAfter() async throws {
        let context = try inMemoryContext()
        let dayStart = Date.now.addingTimeInterval(-3600)
        let budget = AIBudget(dailyUSD: 0.001, lifetimeUSD: nil)

        _ = try await AILedger.spend(.grading, budget: budget, dayStart: dayStart, in: context) {
            ("first", CallCost(promptTokens: 1, completionTokens: 1, usd: 0.002))
        }

        var reached = false
        await #expect(throws: AIBudgetError.self) {
            _ = try await AILedger.spend(.grading, budget: budget, dayStart: dayStart, in: context) {
                reached = true
                return ("second", nil)
            }
        }
        #expect(reached == false, "the money was spent before the limit was checked")
        #expect(try context.fetchCount(FetchDescriptor<AICall>()) == 1)
    }

    @Test func spendOutsideTheDayDoesNotCountAgainstIt() async throws {
        let context = try inMemoryContext()
        let unlimited = AIBudget(dailyUSD: nil, lifetimeUSD: nil)
        _ = try await AILedger.spend(.coach, budget: unlimited,
                                     dayStart: .now.addingTimeInterval(-86_400), in: context) {
            ("old", CallCost(promptTokens: 1, completionTokens: 1, usd: 0.5))
        }
        // The row was written now, so a day starting later excludes it.
        let later = Date.now.addingTimeInterval(3600)
        #expect(AILedger.spentToday(in: context, since: later) == 0)
        #expect(AILedger.spentLifetime(in: context) == 0.5)
    }

    // MARK: - Teaching before testing

    @Test func anIntroductionTeachesWithoutSpendingTheFirstRating() throws {
        let context = try inMemoryContext()

        let record = ReviewRecorder.introduce(wordID: "abate", in: context, index: index)
        #expect(record.introducedAt != nil)
        #expect(record.studyCard.isIntroduced)
        // Initial stability comes from the first rating a card ever gets, so
        // teaching must not spend it: the card is untouched and still due, and
        // the very next thing is a real question about the word just met.
        #expect(record.reviewCount == 0)
        #expect(record.stability == nil)
        #expect(record.due == .distantPast)

        let logged = try #require(try context.fetch(FetchDescriptor<ReviewRecord>()).first)
        #expect(logged.isIntroduction)
        #expect(logged.latency == nil, "a taught card has no answer time to read")
        #expect(ReviewRecorder.competence(for: "abate", in: context).totalAttempts == 0)
    }

    @Test func teachingTheSameWordTwiceDoesNotResetWhenItWasMet() throws {
        let context = try inMemoryContext()
        let first = ReviewRecorder.introduce(wordID: "abate", in: context, index: index,
                                             at: Date(timeIntervalSince1970: 1_000))
        ReviewRecorder.introduce(wordID: "abate", in: context, index: index)
        #expect(first.introducedAt == Date(timeIntervalSince1970: 1_000))
        #expect(try context.fetch(FetchDescriptor<CardRecord>()).count == 1)
    }

    @Test func competenceIgnoresIntroductionsAndReadsTheRest() throws {
        let context = try inMemoryContext()
        let scheduler = FSRS(enableFuzzing: false)
        ReviewRecorder.introduce(wordID: "abate", in: context, index: index)
        ReviewRecorder.record(wordID: "abate", mode: .spelling, grade: Grade(score: 100),
                              rating: .easy, scheduler: scheduler, in: context, index: index,
                              latency: .seconds(3))
        ReviewRecorder.record(wordID: "abate", mode: .spelling, grade: Grade(score: 0),
                              rating: .again, scheduler: scheduler, in: context, index: index)

        let competence = ReviewRecorder.competence(for: "abate", in: context)
        #expect(competence.totalAttempts == 2)
        #expect(competence[.spelling].accuracy == 0.5)
        #expect(competence[.contextCloze].attempts == 0)
    }

    @Test func anAnswerTimeSurvivesTheRoundTripToDisk() throws {
        let context = try inMemoryContext()
        ReviewRecorder.record(wordID: "abate", mode: .multipleChoice, grade: Grade(score: 100),
                              rating: .easy, scheduler: FSRS(enableFuzzing: false),
                              in: context, index: index, latency: .milliseconds(2400))
        let logged = try #require(try context.fetch(FetchDescriptor<ReviewRecord>()).first)
        // Truncating to whole seconds would round every quick tap down to nothing.
        #expect(logged.latencyMS == 2400)
        #expect(logged.latency == .milliseconds(2400))
    }

    @Test func aTaintedTimeIsKeptButNotOffered() throws {
        let context = try inMemoryContext()
        ReviewRecorder.record(wordID: "abate", mode: .multipleChoice, grade: Grade(score: 100),
                              rating: .easy, scheduler: FSRS(enableFuzzing: false),
                              in: context, index: index,
                              latency: .milliseconds(9000), latencyTainted: true)
        let logged = try #require(try context.fetch(FetchDescriptor<ReviewRecord>()).first)
        // Kept so the bands can be retuned later against real times.
        #expect(logged.latencyMS == 9000)
        #expect(logged.latency == nil)
    }

    // MARK: - The shared mastery cache

    @Test func aWriteRefreshesTheSharedMasteryIndex() throws {
        let context = try inMemoryContext()
        #expect(index.cards["abate"] == nil)
        ReviewRecorder.record(wordID: "abate", mode: .spelling, grade: Grade(score: 100),
                              rating: .easy, scheduler: FSRS(enableFuzzing: false),
                              in: context, index: index)
        #expect(index.cards["abate"]?.reviewCount == 1)

        try ReviewRecorder.eraseAllProgress(in: context, index: index)
        #expect(index.cards.isEmpty, "the rings would still show deleted progress")
    }
}
