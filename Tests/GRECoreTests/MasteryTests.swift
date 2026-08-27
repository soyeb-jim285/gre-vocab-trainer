import Foundation
import Testing
@testable import GRECore

@Suite struct MasteryTests {

    private func card(_ id: String = "abate", stability: Double?, reviews: Int = 1) -> StudyCard {
        StudyCard(wordID: id, fsrs: FSRSCard(stability: stability, difficulty: 5, state: .review, step: nil),
                  reviewCount: reviews)
    }

    @Test func noCardIsNew() {
        #expect(Mastery(card: nil) == .new)
        #expect(Mastery(card: StudyCard(wordID: "abate")) == .new, "a card that was never answered is still new")
    }

    @Test func thresholdsFollowStabilityInDays() {
        #expect(Mastery(card: card(stability: nil)) == .learning)
        #expect(Mastery(card: card(stability: 2.9)) == .learning)
        #expect(Mastery(card: card(stability: 3)) == .familiar)
        #expect(Mastery(card: card(stability: 20.9)) == .familiar)
        #expect(Mastery(card: card(stability: 21)) == .known)
        #expect(Mastery(card: card(stability: 89)) == .known)
        #expect(Mastery(card: card(stability: 90)) == .mastered)
        #expect(Mastery(card: card(stability: 400)) == .mastered)
    }

    @Test func levelsAreOrdered() {
        #expect(Mastery.allCases == [.new, .learning, .familiar, .known, .mastered])
        #expect(Mastery.new < Mastery.learning && Mastery.known < Mastery.mastered)
    }

    @Test func deckProgressAveragesLevels() {
        let deck = Deck(id: "t-1", tier: .core, index: 1, wordIDs: ["a", "b", "c", "d"])
        let cards = [
            "a": card("a", stability: 100),   // mastered = 4
            "b": card("b", stability: 30),    // known = 3
            "c": card("c", stability: nil),   // learning = 1
        ]                                     // d: new = 0
        let progress = DeckProgress(deck: deck, cards: cards)
        #expect(progress.total == 4)
        #expect(progress.counts[.mastered] == 1)
        #expect(progress.counts[.new] == 1)
        #expect(abs(progress.fraction - 8.0 / 16.0) < 1e-9)
        #expect(progress.isComplete == false)
        #expect(progress.count(atLeast: .known) == 2)
    }

    @Test func aDeckIsCompleteWhenEveryWordIsAtLeastKnown() {
        let deck = Deck(id: "t-1", tier: .core, index: 1, wordIDs: ["a", "b"])
        let done = DeckProgress(deck: deck, cards: ["a": card("a", stability: 21), "b": card("b", stability: 95)])
        #expect(done.isComplete)
        #expect(DeckProgress(deck: deck, cards: [:]).fraction == 0)
    }
}
