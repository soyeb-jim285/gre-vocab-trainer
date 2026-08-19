import Foundation
import Testing
@testable import GRECore

@Suite struct WordDifficultyTests {

    private static let catalog = try! WordCatalog.bundled()

    @Test func difficultyOrdersEasiestFirst() {
        #expect(WordDifficulty.familiar < WordDifficulty.moderate)
        #expect(WordDifficulty.moderate < WordDifficulty.hard)
        #expect(WordDifficulty.hard < WordDifficulty.rare)
        #expect(WordDifficulty.allCases.sorted() == [.familiar, .moderate, .hard, .rare])
    }

    @Test func everyWordCarriesAFrequencyAndABand() throws {
        for word in Self.catalog.words {
            #expect(word.zipf >= 0, "\(word.id): negative frequency")
            #expect(WordDifficulty.allCases.contains(word.difficulty))
        }
    }

    @Test func familiarWordsAreActuallyMoreCommonThanRareOnes() throws {
        let familiar = Self.catalog.words(withDifficulty: .familiar)
        let rare = Self.catalog.words(withDifficulty: .rare)
        #expect(familiar.isEmpty == false)
        #expect(rare.isEmpty == false)
        // The bands must separate on the underlying number, not just by label.
        #expect(familiar.map(\.zipf).min()! > rare.map(\.zipf).max()!)
    }

    @Test func knownEasyWordsLandInEasyBands() throws {
        let start = try #require(Self.catalog["start"])
        let cajole = try #require(Self.catalog["cajole"])
        #expect(start.difficulty < cajole.difficulty)
    }
}

@Suite struct NewWordOrderTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func introduced(
        _ order: NewWordOrder, limit: Int = 12, accuracy: Double? = nil
    ) -> [Word] {
        SessionPlanner.plan(
            cards: [], catalog: Self.catalog,
            settings: SessionSettings(dailyNewWordLimit: limit, aiEnabled: false, newWordOrder: order),
            recentAccuracy: accuracy, now: now
        ).map(\.word)
    }

    @Test func easiestFirstIntroducesTheMostCommonWords() {
        let words = introduced(.easiestFirst)
        #expect(words.allSatisfy { $0.difficulty == .familiar })
        // And genuinely in descending commonness, not merely inside the band.
        let zipfs = words.map(\.zipf)
        #expect(zipfs == zipfs.sorted(by: >))
    }

    @Test func mostTestedKeepsTheOldPrepListOrdering() {
        let words = introduced(.mostTested)
        #expect(words.allSatisfy { $0.tier == .core })
    }

    @Test func theTwoOrdersDisagreeWhichProvesFrequencyIsNotListCount() {
        #expect(introduced(.easiestFirst).map(\.id) != introduced(.mostTested).map(\.id))
    }

    @Test func orderingIsStableAcrossCalls() {
        #expect(introduced(.easiestFirst).map(\.id) == introduced(.easiestFirst).map(\.id))
    }
}

@Suite struct AdaptiveDifficultyTests {

    private static let catalog = try! WordCatalog.bundled()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ceiling(_ accuracy: Double?) -> WordDifficulty {
        SessionSettings.difficultyCeiling(forAccuracy: accuracy)
    }

    private func introduced(accuracy: Double?) -> [Word] {
        SessionPlanner.plan(
            cards: [], catalog: Self.catalog,
            settings: SessionSettings(dailyNewWordLimit: 10, aiEnabled: false, newWordOrder: .adaptive),
            recentAccuracy: accuracy, now: now
        ).map(\.word)
    }

    @Test func aBeginnerWithNoHistoryStartsOnTheEasiestWords() {
        #expect(ceiling(nil) == .familiar)
        #expect(introduced(accuracy: nil).allSatisfy { $0.difficulty == .familiar })
    }

    @Test func theCeilingRisesAsAccuracyRises() {
        #expect(ceiling(30) == .familiar)
        #expect(ceiling(60) == .moderate)
        #expect(ceiling(75) == .hard)
        #expect(ceiling(92) == .rare)
    }

    @Test func theCeilingNeverFallsAsAccuracyRises() {
        var previous = WordDifficulty.familiar
        for percent in stride(from: 0.0, through: 100.0, by: 1) {
            let current = ceiling(percent)
            #expect(current >= previous, "ceiling dropped at \(percent)%")
            previous = current
        }
    }

    @Test func strugglingKeepsHarderWordsOutOfTheQueue() {
        let words = introduced(accuracy: 35)
        #expect(words.isEmpty == false)
        #expect(words.allSatisfy { $0.difficulty == .familiar })
    }

    @Test func doingWellUnlocksTheHarderWordsWithoutSkippingTheEasyOnes() {
        // Raising the ceiling widens the pool; it does not jump straight to rare.
        let words = introduced(accuracy: 95)
        #expect(words.allSatisfy { $0.difficulty <= .rare })
        #expect(words.first?.difficulty == .familiar, "should still start from the easiest available")
    }

    @Test func aWordIsNeverIntroducedAboveTheCeiling() {
        for accuracy in [0.0, 40, 65, 80, 100] {
            let limit = ceiling(accuracy)
            #expect(introduced(accuracy: accuracy).allSatisfy { $0.difficulty <= limit },
                    "accuracy \(accuracy) introduced a word above \(limit)")
        }
    }
}
