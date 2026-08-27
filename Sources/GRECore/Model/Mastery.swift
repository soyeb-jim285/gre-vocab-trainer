import Foundation

/// How well a word is held, read straight off FSRS stability (days until recall
/// drops to the desired retention). A lapse collapses stability, so a level is
/// lost automatically -- no separate bookkeeping.
public enum Mastery: Int, Comparable, CaseIterable, Sendable {
    case new, learning, familiar, known, mastered

    public init(stability: Double?) {
        switch stability ?? 0 {
        case 90...: self = .mastered
        case 21...: self = .known
        case 3...: self = .familiar
        default: self = .learning
        }
    }

    /// Nil, or a card that has never been answered, is new.
    public init(card: StudyCard?) {
        guard let card, card.reviewCount > 0 else { self = .new; return }
        self.init(stability: card.fsrs.stability)
    }

    public var label: String {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .familiar: "Familiar"
        case .known: "Known"
        case .mastered: "Mastered"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where a deck stands, for rings and bars.
public struct DeckProgress: Equatable, Sendable {
    public let counts: [Mastery: Int]
    public let total: Int

    public init(deck: Deck, cards: [String: StudyCard]) {
        let levels = deck.wordIDs.map { Mastery(card: cards[$0]) }
        self.counts = Dictionary(levels.map { ($0, 1) }, uniquingKeysWith: +)
        self.total = levels.count
    }

    /// Mean level over the deck, 0 (all new) to 1 (all mastered).
    public var fraction: Double {
        guard total > 0 else { return 0 }
        let sum = counts.reduce(0) { $0 + $1.key.rawValue * $1.value }
        return Double(sum) / Double(total * Mastery.mastered.rawValue)
    }

    public func count(atLeast level: Mastery) -> Int {
        counts.filter { $0.key >= level }.values.reduce(0, +)
    }

    public var isComplete: Bool { total > 0 && count(atLeast: .known) == total }
}
