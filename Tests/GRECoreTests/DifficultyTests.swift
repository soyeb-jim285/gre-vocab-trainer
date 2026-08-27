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

    @Test func theBandsSeparateOnTheHandAssignedRating() throws {
        // They no longer separate on frequency, deliberately: a band is a claim
        // about the tested sense, and frequency measures the word form.
        let familiar = Self.catalog.words(withDifficulty: .familiar)
        let rare = Self.catalog.words(withDifficulty: .rare)
        #expect(familiar.isEmpty == false)
        #expect(rare.isEmpty == false)
        #expect(familiar.map(\.rating).max()! < rare.map(\.rating).min()!)
    }

    @Test func aCommonWordWithARareTestedSenseIsNotCalledEasy() throws {
        // "start" is one of the most frequent words in English; the sense the
        // exam tests -- to jump in surprise -- is not.
        let start = try #require(Self.catalog["start"])
        #expect(start.zipf > 5.0, "expected a very common word form")
        #expect(start.difficulty >= .hard, "frequency is deciding the band again")
    }

    @Test func genuinelyEasyWordsStillLandInEasyBands() throws {
        let modest = try #require(Self.catalog["modest"])
        let cajole = try #require(Self.catalog["cajole"])
        #expect(modest.difficulty < cajole.difficulty)
    }
}
