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
