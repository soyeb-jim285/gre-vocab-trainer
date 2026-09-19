import Foundation

/// How much of a word set the learner actually holds.
///
/// Answers "how much of the likely test vocabulary do I know", which no word
/// count does: three hundred words met is not three hundred words held.
public struct Coverage: Equatable, Sendable {
    public let held: Int
    public let total: Int

    /// - Parameter atLeast: the level that counts as held. Familiar is FSRS
    ///   stability of three days or more: past the learning steps and
    ///   surviving on its own.
    public init(wordIDs: [String], cards: [String: StudyCard], atLeast: Mastery = .familiar) {
        self.total = wordIDs.count
        self.held = wordIDs.filter { Mastery(card: cards[$0]) >= atLeast }.count
    }

    public var fraction: Double { total == 0 ? 0 : Double(held) / Double(total) }
    public var percent: Int { Int((fraction * 100).rounded(.down)) }
}

/// Which example sentence to show for a word this time.
///
/// Varied contexts help a held word transfer to new sentences, but hurt a new
/// one: the learner has no stable meaning yet to carry across them. So a word
/// keeps one anchor sentence until it is familiar, then rotates.
public enum ContextRotation {
    public static func index(count: Int, card: StudyCard) -> Int {
        guard count > 1 else { return 0 }
        guard Mastery(card: card) >= .familiar else { return 0 }
        return card.reviewCount % count
    }
}
