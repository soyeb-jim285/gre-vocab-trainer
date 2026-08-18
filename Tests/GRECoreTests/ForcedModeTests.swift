import Foundation
import Testing
@testable import GRECore

/// A forced mode drills one skill for a whole session. It overrides the ladder,
/// but not the API key -- having no key is a hard constraint, not a preference.
@Suite struct ForcedModeTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(_ id: String, reviews: Int) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: 10, difficulty: 5, due: now.addingTimeInterval(-86_400),
                           lastReview: now.addingTimeInterval(-172_800), state: .review, step: nil),
            reviewCount: reviews
        )
    }

    private func plan(
        forced: StudyMode?, reviews: [Int], ai: Bool = true, newLimit: Int = 0
    ) -> [SessionItem] {
        let cards = reviews.enumerated().map { card(Self.catalog.words[$0.offset].id, reviews: $0.element) }
        return SessionPlanner.plan(
            cards: cards, catalog: Self.catalog,
            settings: SessionSettings(dailyNewWordLimit: newLimit, aiEnabled: ai, forcedMode: forced),
            now: now
        )
    }

    @Test func autoIsTheDefaultAndKeepsTheLadder() {
        #expect(SessionSettings().forcedMode == nil)
        let modes = plan(forced: nil, reviews: [0, 1, 2, 3]).map(\.mode)
        #expect(modes == [.multipleChoice, .reverseRecall, .spelling, .defineAndUse])
    }

    @Test(arguments: StudyMode.allCases)
    func forcingAModeAppliesItToEveryCardWhateverItsHistory(mode: StudyMode) {
        let modes = plan(forced: mode, reviews: [0, 1, 2, 3, 9]).map(\.mode)
        #expect(modes.allSatisfy { $0 == mode }, "got \(Set(modes)) instead of all \(mode)")
    }

    @Test func forcingAModeAlsoAppliesToBrandNewWords() {
        let modes = plan(forced: .spelling, reviews: [], newLimit: 4).map(\.mode)
        #expect(modes.count == 4)
        #expect(modes.allSatisfy { $0 == .spelling })
    }

    @Test func forcingWritingWithoutAKeyFallsBackToLocalModes() {
        // The picker should not be able to strand the learner on a locked mode.
        let modes = plan(forced: .defineAndUse, reviews: [0, 1, 2, 5], ai: false).map(\.mode)
        #expect(modes.contains(.defineAndUse) == false)
        #expect(modes.allSatisfy { StudyMode.locallyGraded.contains($0) })
    }

    @Test func forcingALocalModeWorksWithoutAKey() {
        let modes = plan(forced: .spelling, reviews: [0, 4], ai: false).map(\.mode)
        #expect(modes.allSatisfy { $0 == .spelling })
    }

    @Test func aForcedModeDoesNotChangeWhichCardsAreDue() {
        // Only how they're tested changes, never the selection or its order.
        let auto = plan(forced: nil, reviews: [0, 1, 2, 3]).map(\.card.wordID)
        let forced = plan(forced: .spelling, reviews: [0, 1, 2, 3]).map(\.card.wordID)
        #expect(auto == forced)
    }

    @Test func theWritingThresholdIsIgnoredWhileAModeIsForced() {
        let cards = [card("abate", reviews: 0)]
        let settings = SessionSettings(
            dailyNewWordLimit: 0, aiEnabled: true,
            writingModeAfterReviews: 99, forcedMode: .defineAndUse
        )
        let plan = SessionPlanner.plan(cards: cards, catalog: Self.catalog, settings: settings, now: now)
        #expect(plan[0].mode == .defineAndUse)
    }
}
