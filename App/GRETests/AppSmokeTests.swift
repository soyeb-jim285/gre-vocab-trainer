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

        model.submitMultipleChoice(first.word)
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
        let wrong = try #require(model.multipleChoiceOptions(for: item).first { $0.id != item.word.id })

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
            #expect(options.contains { $0.id == item.word.id }, "\(item.word.id) was not among its own options")
            model.submitMultipleChoice(item.word)
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
            model.submitMultipleChoice(item.word)
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
            model.submitMultipleChoice(item.word)
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
