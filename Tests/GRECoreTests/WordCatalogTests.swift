import Foundation
import Testing
@testable import GRECore

@Suite struct WordCatalogTests {

    @Test func loadsTheBundledDataset() throws {
        let catalog = try WordCatalog.bundled()
        // The pipeline currently ships 2898 words; assert a floor rather than an
        // exact count so regenerating the dataset doesn't break the build.
        #expect(catalog.words.count > 2500)
    }

    @Test func looksUpWordsById() throws {
        let catalog = try WordCatalog.bundled()
        let abate = try #require(catalog["abate"])
        #expect(abate.word == "abate")
        #expect(abate.ipa == "əˈbeɪt")
        #expect(abate.senses.first?.pos == .verb)
        #expect(abate.senses.first?.definition.isEmpty == false)
        #expect(catalog["definitelynotaword"] == nil)
    }

    @Test func everyWordHasAtLeastOneSenseWithADefinition() throws {
        let catalog = try WordCatalog.bundled()
        for word in catalog.words {
            #expect(word.senses.isEmpty == false, "\(word.id) has no senses")
            #expect(word.senses.allSatisfy { !$0.definition.isEmpty }, "\(word.id) has a blank definition")
        }
    }

    @Test func tiersOrderCoreFirstSoCommonWordsAreTaughtSoonest() {
        #expect(WordTier.core < WordTier.common)
        #expect(WordTier.common < WordTier.extended)
        #expect([WordTier.extended, .core, .common].sorted() == [.core, .common, .extended])
    }

    @Test func tierAgreesWithHowManyListsTheWordAppearsOn() throws {
        let catalog = try WordCatalog.bundled()
        for word in catalog.words {
            let expected: WordTier = word.listCount >= 3 ? .core : (word.listCount == 2 ? .common : .extended)
            #expect(word.tier == expected, "\(word.id): tier \(word.tier) vs \(word.listCount) lists")
            #expect(word.listCount == word.sourceLists.count, "\(word.id): listCount disagrees with sourceLists")
        }
    }

    @Test func groupsWordsByPartOfSpeechForDistractorPicking() throws {
        let catalog = try WordCatalog.bundled()
        let adverbs = catalog.words(withPartOfSpeech: .adverb)
        #expect(adverbs.isEmpty == false)
        #expect(adverbs.allSatisfy { $0.primaryPartOfSpeech == .adverb })

        let total = PartOfSpeech.allCases.map { catalog.words(withPartOfSpeech: $0).count }.reduce(0, +)
        #expect(total == catalog.words.count, "every word must land in exactly one part-of-speech bucket")
    }

    @Test func wordsInTierReturnsOnlyThatTier() throws {
        let catalog = try WordCatalog.bundled()
        let core = catalog.words(inTier: .core)
        #expect(core.isEmpty == false)
        #expect(core.allSatisfy { $0.tier == .core })
        #expect(core.count < catalog.words.count)
    }

    @Test func decodesASenseWithoutOptionalFieldsBeingNil() throws {
        let catalog = try WordCatalog.bundled()
        // Most words have no antonyms; those must decode as empty, never nil.
        let withoutAntonyms = try #require(catalog.words.first { $0.senses.allSatisfy { $0.antonyms.isEmpty } })
        #expect(withoutAntonyms.senses.allSatisfy { $0.antonyms.isEmpty })
    }
}
