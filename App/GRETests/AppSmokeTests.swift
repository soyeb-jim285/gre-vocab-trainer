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
}
