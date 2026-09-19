import Foundation
import Testing
@testable import GRECore

@Suite struct QuizPlannerTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let fsrs = FSRS(enableFuzzing: false)

    private func studied(_ id: String, stability: Double = 10, daysAgo: Double = 1) -> StudyCard {
        StudyCard(
            wordID: id,
            fsrs: FSRSCard(stability: stability, difficulty: 5, due: now.addingTimeInterval(5 * 86_400),
                           lastReview: now.addingTimeInterval(-daysAgo * 86_400), state: .review, step: nil),
            reviewCount: 2
        )
    }

    private var dayStart: Date { Date(timeIntervalSince1970: 1_799_971_200) }

    @Test func theChallengeIsTheSameSetAllDayAndANewOneTomorrow() {
        // Either you did today's or you did not. Re-rolling on every open would
        // make it another session with a different name.
        let cards = Self.catalog.words.prefix(60).map { studied($0.id) }
        func challenge(_ start: Date) -> [String] {
            QuizPlanner.dailyChallenge(cards: cards, catalog: Self.catalog, scheduler: fsrs,
                                       dayStart: start, now: now).map(\.card.wordID)
        }
        #expect(challenge(dayStart) == challenge(dayStart))
        #expect(challenge(dayStart) != challenge(dayStart.addingTimeInterval(86_400)))
    }

    @Test func theChallengeOnlyAsksQuestionsThatNeedNoKey() {
        // It is the one screen that has to work on a train.
        let cards = Self.catalog.words.prefix(60).map { studied($0.id) }
        let items = QuizPlanner.dailyChallenge(cards: cards, catalog: Self.catalog,
                                               scheduler: fsrs, dayStart: dayStart, now: now)
        #expect(items.count == 20)
        #expect(items.allSatisfy { StudyMode.locallyGraded.contains($0.mode) })
        #expect(items.allSatisfy { $0.mode != .senseInContext })
        #expect(Set(items.map(\.mode)).count == 4)
    }

    @Test func thereIsNoChallengeBeforeThereIsAnythingToBeChallengedOn() {
        let cards = Self.catalog.words.prefix(4).map { studied($0.id) }
        #expect(QuizPlanner.dailyChallenge(cards: cards, catalog: Self.catalog, scheduler: fsrs,
                                           dayStart: dayStart, now: now).isEmpty)
    }

    @Test func aGlobalTestSamplesTheRequestedCountFromStudiedWords() {
        let cards = Self.catalog.words.prefix(60).map { studied($0.id) }
        let items = QuizPlanner.globalTest(cards: cards, catalog: Self.catalog, scheduler: fsrs, count: 20, seed: 1, now: now)
        #expect(items.count == 20)
        #expect(Set(items.map(\.card.wordID)).count == 20)
    }

    @Test func aGlobalTestFavoursTheWordsMostLikelyForgotten() {
        // 40 rock-solid words and 10 shaky ones; the shaky ones should dominate.
        let solid = Self.catalog.words.prefix(40).map { studied($0.id, stability: 400, daysAgo: 0) }
        let shaky = Self.catalog.words.dropFirst(40).prefix(10).map { studied($0.id, stability: 0.5, daysAgo: 10) }
        var hits = 0
        for seed in 0..<20 {
            let items = QuizPlanner.globalTest(cards: solid + shaky, catalog: Self.catalog, scheduler: fsrs,
                                               count: 10, seed: UInt64(seed), now: now)
            hits += items.filter { shaky.map(\.wordID).contains($0.card.wordID) }.count
        }
        // Uniform sampling would give ~2 of 10 per run (40 of 200); weighting must beat that clearly.
        #expect(hits > 100, "only \(hits)/200 picks were shaky words")
    }

    @Test func aGlobalTestWithTooFewWordsIsEmpty() {
        let cards = Self.catalog.words.prefix(4).map { studied($0.id) }
        #expect(QuizPlanner.globalTest(cards: cards, catalog: Self.catalog, scheduler: fsrs, seed: 1, now: now).isEmpty)
    }
}
