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

    private func inMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CardRecord.self, ReviewRecord.self, DeepDiveRecord.self, QuizRecord.self,
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

    @Test func aSessionPlansAndSchedulesTheFirstCard() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()

        #expect(model.current != nil)
        let first = try #require(model.current)
        #expect(first.mode == .multipleChoice)

        model.submitMultipleChoice(first.word.teachingDefinition)
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

    @Test func aWrongMultipleChoiceAnswerSchedulesTheCardToReturn() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        let item = try #require(model.current)
        let wrong = try #require(model.multipleChoiceOptions(for: item)
            .first { $0 != item.word.teachingDefinition })

        model.submitMultipleChoice(wrong)
        guard case let .reviewing(feedback) = model.phase else {
            Issue.record("expected review phase")
            return
        }
        #expect(feedback.score == 0)
        #expect(feedback.rating == .again)
    }

    @Test func multipleChoiceAlwaysOffersTheRightAnswerAmongFour() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        for _ in 0..<12 {
            let item = try #require(model.current)
            let options = model.multipleChoiceOptions(for: item)
            #expect(options.count == 4, "\(item.word.id) offered \(options.count) options")
            #expect(options.contains(item.word.teachingDefinition),
                    "\(item.word.id) was not among its own options")
            model.submitMultipleChoice(item.word.teachingDefinition)
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

    @Test func writingModeIsReachableImmediatelyWhenTheThresholdIsZero() throws {
        let catalog = try WordCatalog.bundled()
        func firstMode(writingAfter: Int) -> StudyMode? {
            SessionPlanner.next(
                cards: [], catalog: catalog,
                settings: SessionSettings(aiEnabled: true, writingModeAfterReviews: writingAfter),
                scheduler: FSRS(), recentAccuracy: nil, recentWordIDs: [], now: .now
            )?.mode
        }
        #expect(firstMode(writingAfter: 0) == .defineAndUse)
        #expect(firstMode(writingAfter: 3) == .multipleChoice)
    }

    @Test func practisingAWordOutsideASessionSchedulesItTheSameWay() throws {
        let context = try inMemoryContext()
        let scheduler = FSRS(enableFuzzing: false)

        let record = ReviewRecorder.record(
            wordID: "abate", mode: .defineAndUse, grade: Grade(score: 95),
            rating: .easy, scheduler: scheduler, in: context
        )
        #expect(record.reviewCount == 1)
        #expect(record.due > .now)

        // Same word again, and the schedule must keep moving rather than reset.
        let firstDue = record.due
        let again = ReviewRecorder.record(
            wordID: "abate", mode: .defineAndUse, grade: Grade(score: 95),
            rating: .easy, scheduler: scheduler, in: context
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
                                  rating: .easy, scheduler: scheduler, in: context)
        }
        let graduated = try #require(ReviewRecorder.existing("laconic", in: context))
        #expect(graduated.fsrs.state == .review)

        let lapsed = ReviewRecorder.record(wordID: "laconic", mode: .defineAndUse, grade: Grade(score: 10),
                                           rating: .again, scheduler: scheduler, in: context)
        #expect(lapsed.lapses == 1)
    }

    // MARK: - Session mode picker

    @Test func forcingAModeRetestsEveryCardThatWay() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.forcedMode = .spelling

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        #expect(model.current?.mode == .spelling)
    }

    @Test func autoRestoresTheLadder() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.forcedMode = nil

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        #expect(model.current?.mode == .multipleChoice)
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

    @Test func aMissedWordDoesNotRepeatBackToBackAndTheDeckPointerMoves() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        let missed = try #require(model.current)
        model.admitNotKnowing()
        model.advance()
        // Rated Again → due in a minute, so within this synchronous test it is
        // not yet due; the planner's controlled-clock tests cover the return.
        var seen: [String] = []
        for _ in 0..<6 {
            guard let item = model.current else { break }
            seen.append(item.word.id)
            model.submitMultipleChoice(item.word.teachingDefinition)
            model.advance()
        }
        #expect(seen.contains(missed.word.id) == false, "the same word should not repeat back-to-back")
        #expect(settings.currentDeckID == catalog.decks[0].id)
    }

    @Test func aDeckTestRecordsItsScore() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let deck = catalog.decks[0]
        for id in deck.wordIDs.prefix(5) {
            ReviewRecorder.record(wordID: id, mode: .multipleChoice, grade: Grade(score: 100),
                                  rating: .good, scheduler: FSRS(), in: context)
        }
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings, quiz: .deck(deck))
        model.start()
        #expect(model.progress == 0)
        while let item = model.current {
            model.submitMultipleChoice(item.word.teachingDefinition)
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
                                  rating: .easy, scheduler: scheduler, in: context)
        }
        #expect(ReviewRecorder.recentAccuracy(in: context) == nil, "four answers is not enough to judge by")

        ReviewRecorder.record(wordID: "w5", mode: .spelling, grade: Grade(score: 100),
                              rating: .easy, scheduler: scheduler, in: context)
        #expect(ReviewRecorder.recentAccuracy(in: context) == 100)
    }

    // MARK: - Context modes

    @Test func aClozeQuestionOffersFourWordsAndOneBlankedSentence() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)

        let word = try #require(catalog["abate"])
        let card = StudyCard(wordID: word.id, fsrs: FSRSCard(stability: 10, difficulty: 5,
                                                             due: .now, lastReview: .now,
                                                             state: .review, step: nil),
                             reviewCount: 3)
        let item = SessionItem(card: card, word: word, mode: .contextCloze)

        let options = model.clozeOptions(for: item)
        #expect(options.count == 4)
        #expect(options.contains { $0.id == word.id })
        #expect(Set(options.map(\.id)).count == 4, "an option was repeated")

        let sentence = model.clozeSentence(for: item)
        #expect(sentence.contains("____"))
        #expect(sentence.localizedCaseInsensitiveContains(word.word) == false, "the answer is in the sentence")
    }

    @Test func answeringAClozeCorrectlyScoresAndSchedules() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        let item = try #require(model.current)

        model.submitCloze(item.word)
        guard case let .reviewing(feedback) = model.phase else {
            Issue.record("expected review phase, got \(model.phase)")
            return
        }
        #expect(feedback.score == 100)
        #expect(try context.fetch(FetchDescriptor<CardRecord>()).count == 1)
    }

    @Test func aWrongClozeShowsTheFullEntry() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        let item = try #require(model.current)
        let wrong = try #require(model.clozeOptions(for: item).first { $0.id != item.word.id })

        model.submitCloze(wrong)
        guard case let .reviewing(feedback) = model.phase else { Issue.record("expected review"); return }
        #expect(feedback.score == 0)
        #expect(feedback.showsReference, "a wrong answer in context is when the entry helps most")
    }

    @Test func aWhichMeaningQuestionOffersTheEverydayMeaningAsBait() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)

        let word = try #require(catalog["flag"])
        #expect(word.isTrap)
        let item = SessionItem(card: StudyCard(wordID: word.id), word: word, mode: .senseInContext)

        let options = model.senseOptions(for: item)
        #expect(options.count == 4)
        #expect(options.contains(word.teachingDefinition))
        #expect(Set(options).count == 4, "a meaning was repeated")

        // The sentence is shown unblanked: interpreting the word is the task.
        let sentence = model.senseSentence(for: item)
        #expect(sentence.contains("____") == false)
        #expect(sentence.isEmpty == false)
    }

    @Test func choosingTheWrongMeaningIsMarkedWrong() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        let item = try #require(model.current)

        // Graded against the card actually on screen, so drive it through the model.
        let wrong = try #require(
            model.senseOptions(for: item).first { $0 != item.word.teachingDefinition }
        )
        model.submitSense(wrong)
        guard case let .reviewing(feedback) = model.phase else { Issue.record("expected review"); return }
        #expect(feedback.score == 0)
        #expect(feedback.showsReference, "the whole point is to show the tested meaning")
    }

    @Test func choosingTheTestedMeaningScoresFull() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        let item = try #require(model.current)

        model.submitSense(item.word.teachingDefinition)
        guard case let .reviewing(feedback) = model.phase else { Issue.record("expected review"); return }
        #expect(feedback.score == 100)
    }

    // MARK: - Reset

    @Test func resettingErasesProgressAndRestoresDefaults() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let scheduler = FSRS(enableFuzzing: false)

        // Something of every kind that a reset must remove.
        let deck = catalog.decks[0]
        for id in deck.wordIDs.prefix(6) {
            ReviewRecorder.record(wordID: id, mode: .multipleChoice, grade: Grade(score: 100),
                                  rating: .good, scheduler: scheduler, in: context)
        }
        context.insert(QuizRecord(deckID: deck.id, score: 80, wordCount: 6, takenAt: .now))
        context.insert(DeepDiveRecord(
            wordID: "abate",
            dive: WordDeepDive(etymology: "e", mnemonic: "m", nuance: "n", confusableWith: []),
            fetchedAt: .now
        ))
        try context.save()

        settings.strictness = .strict
        settings.desiredRetention = 0.8
        settings.currentDeckID = deck.id
        settings.forcedMode = .spelling
        settings.writingModeAfterReviews = 0

        try ReviewRecorder.eraseAllProgress(in: context)
        settings.resetToDefaults()

        #expect(try context.fetch(FetchDescriptor<CardRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ReviewRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<QuizRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DeepDiveRecord>()).isEmpty)

        #expect(settings.strictness == .standard)
        #expect(settings.desiredRetention == 0.9)
        #expect(settings.currentDeckID == nil)
        #expect(settings.forcedMode == nil)
        #expect(settings.writingModeAfterReviews == 3)
    }

    @Test func resettingSurvivesARelaunch() throws {
        // The defaults must be written through, not just held in memory.
        let suite = "test-\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.strictness = .strict
        settings.currentDeckID = "core-9"
        settings.resetToDefaults()

        let relaunched = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        #expect(relaunched.strictness == .standard)
        #expect(relaunched.currentDeckID == nil)
    }

    @Test func resettingLeavesTheApiKeyUntouched() throws {
        // Wiping progress must not lock the learner out of the graded mode.
        // Asserted as "unchanged" rather than by writing a key first: the CI
        // simulator has no Keychain entitlement, so a write there is a no-op.
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let keyBefore = KeychainStore.apiKey
        let hadKey = settings.hasAPIKey

        settings.resetToDefaults()

        #expect(KeychainStore.apiKey == keyBefore, "a reset changed the stored key")
        #expect(settings.hasAPIKey == hadKey)
    }

    @Test func aSessionAfterResetStartsFromTheFirstDeckAgain() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        for _ in 0..<4 {
            guard let item = model.current else { break }
            model.submitMultipleChoice(item.word.teachingDefinition)
            model.advance()
        }
        #expect(try context.fetch(FetchDescriptor<CardRecord>()).isEmpty == false)

        try ReviewRecorder.eraseAllProgress(in: context)
        settings.resetToDefaults()

        let fresh = SessionViewModel(context: context, catalog: catalog, settings: settings)
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

    @Test func gradingCostIsStoredAndTotalled() throws {
        let context = try inMemoryContext()
        let scheduler = FSRS(enableFuzzing: false)
        #expect(ReviewRecorder.totalSpend(in: context) == 0)

        ReviewRecorder.record(
            wordID: "abate", mode: .defineAndUse, grade: Grade(score: 80), rating: .good,
            scheduler: scheduler, in: context,
            cost: CallCost(promptTokens: 400, completionTokens: 90, usd: 0.0003)
        )
        ReviewRecorder.record(
            wordID: "laconic", mode: .defineAndUse, grade: Grade(score: 80), rating: .good,
            scheduler: scheduler, in: context,
            cost: CallCost(promptTokens: 400, completionTokens: 90, usd: 0.0002)
        )
        // A locally-graded answer costs nothing and must not inflate the total.
        ReviewRecorder.record(wordID: "acumen", mode: .spelling, grade: Grade(score: 100),
                              rating: .easy, scheduler: scheduler, in: context)

        #expect(abs(ReviewRecorder.totalSpend(in: context) - 0.0005) < 1e-9)
    }
}
