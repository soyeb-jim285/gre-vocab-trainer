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
            for: CardRecord.self, ReviewRecord.self, DeepDiveRecord.self,
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
        settings.dailyNewWordLimit = 3
        settings.sessionLength = 5

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()

        #expect(model.items.count == 3)
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
        settings.dailyNewWordLimit = 2

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
        settings.dailyNewWordLimit = 12

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        for item in model.items {
            let options = model.multipleChoiceOptions(for: item)
            #expect(options.count == 4, "\(item.word.id) offered \(options.count) options")
            #expect(options.contains { $0.id == item.word.id }, "\(item.word.id) was not among its own options")
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
        var settings = SessionSettings(dailyNewWordLimit: 3, aiEnabled: true, writingModeAfterReviews: 0)
        var plan = SessionPlanner.plan(cards: [], catalog: catalog, settings: settings, now: .now)
        #expect(plan.allSatisfy { $0.mode == .defineAndUse })

        settings.writingModeAfterReviews = 3
        plan = SessionPlanner.plan(cards: [], catalog: catalog, settings: settings, now: .now)
        #expect(plan.allSatisfy { $0.mode == .multipleChoice })
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
        settings.dailyNewWordLimit = 5
        settings.forcedMode = .spelling

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        #expect(model.items.isEmpty == false)
        #expect(model.items.allSatisfy { $0.mode == .spelling })
    }

    @Test func autoRestoresTheLadder() throws {
        let context = try inMemoryContext()
        let catalog = try WordCatalog.bundled()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        settings.dailyNewWordLimit = 5
        settings.forcedMode = nil

        let model = SessionViewModel(context: context, catalog: catalog, settings: settings)
        model.start()
        #expect(model.items.allSatisfy { $0.mode == .multipleChoice })
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
}
