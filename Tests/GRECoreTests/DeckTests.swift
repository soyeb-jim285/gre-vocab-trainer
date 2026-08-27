import Foundation
import Testing
@testable import GRECore

@Suite struct DeckTests {

    private static let catalog = try! WordCatalog.bundled()

    @Test func everyWordIsInExactlyOneDeck() {
        let ids = Self.catalog.decks.flatMap(\.wordIDs)
        #expect(ids.count == Self.catalog.words.count)
        #expect(Set(ids).count == ids.count)
        for word in Self.catalog.words {
            #expect(Self.catalog.deck(containing: word.id) != nil, "\(word.id) has no deck")
        }
    }

    @Test func decksAreBetween23And25Words() {
        for deck in Self.catalog.decks {
            #expect((23...25).contains(deck.wordIDs.count), "\(deck.id) has \(deck.wordIDs.count)")
        }
    }

    @Test func decksRunCoreThenCommonThenExtendedAndAreNumberedFromOne() {
        let tiers = Self.catalog.decks.map(\.tier)
        #expect(tiers == tiers.sorted())
        for tier in WordTier.allCases {
            let indices = Self.catalog.decks(inTier: tier).map(\.index)
            #expect(indices == Array(1...indices.count))
        }
        #expect(Self.catalog.decks.first?.id == "core-1")
        #expect(Self.catalog.decks.first?.title == "Core 1")
    }

    @Test func wordsInsideATierRunEasiestFirst() {
        // Ordered by the hand-assigned rating, not by frequency: the whole point
        // is that "august" is a common word and a hard one.
        for tier in WordTier.allCases {
            let ratings = Self.catalog.decks(inTier: tier)
                .flatMap(\.wordIDs)
                .compactMap { Self.catalog[$0]?.rating }
            #expect(ratings == ratings.sorted(), "\(tier) is not easiest-first")
        }
    }

    @Test func theFirstDeckHoldsOnlyGenuinelyEasyWords() {
        let first = Self.catalog.decks[0].wordIDs.compactMap { Self.catalog[$0] }
        let tooHard = first.filter { $0.rating > 2 }.map(\.id)
        #expect(tooHard.isEmpty, "hard words in deck 1: \(tooHard)")
    }

    @Test func aDeckOnlyHoldsWordsOfItsTier() {
        for deck in Self.catalog.decks {
            #expect(deck.wordIDs.allSatisfy { Self.catalog[$0]?.tier == deck.tier })
        }
    }

    @Test func chunkingIsDeterministicAndHasNoRuntDeck() {
        let a = Self.catalog.decks.map(\.wordIDs)
        let b = WordCatalog(words: Self.catalog.words).decks.map(\.wordIDs)
        #expect(a == b)
        // 26 words must become 2 decks of 13, not 25 + 1.
        let words = Array(Self.catalog.words(inTier: .core).prefix(26))
        let sizes = Deck.chunk(words, tier: .core).map(\.wordIDs.count)
        #expect(sizes == [13, 13])
    }

    @Test func lookupsRoundTrip() throws {
        let deck = try #require(Self.catalog.deck(id: "common-2"))
        #expect(deck.tier == .common && deck.index == 2)
        let first = try #require(deck.wordIDs.first)
        #expect(Self.catalog.deck(containing: first)?.id == "common-2")
        #expect(Self.catalog.deck(id: "nope-9") == nil)
    }
}
