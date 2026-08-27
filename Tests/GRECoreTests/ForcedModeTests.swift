import Foundation
import Testing
@testable import GRECore

/// A forced mode drills one skill for a whole session. It overrides the ladder,
/// but not the API key -- having no key is a hard constraint, not a preference.
@Suite struct ForcedModeTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(reviews: Int, state: FSRSState = .review) -> StudyCard {
        StudyCard(
            wordID: "abate",
            fsrs: FSRSCard(stability: 10, difficulty: 5, due: now.addingTimeInterval(-86_400),
                           lastReview: now.addingTimeInterval(-172_800), state: state, step: nil),
            reviewCount: reviews
        )
    }

    private func mode(forced: StudyMode?, reviews: Int, ai: Bool = true, writingAfter: Int = 3) -> StudyMode {
        SessionPlanner.mode(
            for: card(reviews: reviews),
            settings: SessionSettings(aiEnabled: ai, writingModeAfterReviews: writingAfter, forcedMode: forced)
        )
    }

    @Test func autoIsTheDefault() {
        #expect(SessionSettings().forcedMode == nil)
    }

    @Test(arguments: StudyMode.allCases)
    func forcingAModeAppliesItWhateverTheHistory(forced: StudyMode) {
        for reviews in [0, 1, 2, 3, 9] {
            #expect(mode(forced: forced, reviews: reviews) == forced)
        }
        #expect(SessionPlanner.mode(for: card(reviews: 4, state: .relearning),
                                    settings: SessionSettings(forcedMode: forced)) == forced)
    }

    @Test func forcingAModeAlsoAppliesToBrandNewWords() {
        let item = SessionPlanner.next(
            cards: [], catalog: Self.catalog, settings: SessionSettings(aiEnabled: false, forcedMode: .spelling),
            scheduler: FSRS(), recentAccuracy: nil, recentWordIDs: [], now: now
        )
        #expect(item?.mode == .spelling)
    }

    @Test func forcingWritingWithoutAKeyFallsBackToLocalModes() {
        for reviews in [0, 1, 2, 5] {
            let m = mode(forced: .defineAndUse, reviews: reviews, ai: false)
            #expect(m != .defineAndUse)
            #expect(StudyMode.locallyGraded.contains(m))
        }
    }

    @Test func forcingALocalModeWorksWithoutAKey() {
        #expect(mode(forced: .spelling, reviews: 0, ai: false) == .spelling)
        #expect(mode(forced: .spelling, reviews: 4, ai: false) == .spelling)
    }

    @Test func theWritingThresholdIsIgnoredWhileAModeIsForced() {
        #expect(mode(forced: .defineAndUse, reviews: 0, writingAfter: 99) == .defineAndUse)
    }
}
