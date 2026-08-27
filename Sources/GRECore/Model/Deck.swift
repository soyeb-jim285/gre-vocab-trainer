import Foundation

/// A study unit of roughly 25 words: one tier, easiest first.
///
/// Decks are computed from the catalog, never stored, so regenerating the
/// dataset may move a word between decks. Progress lives on words, not decks,
/// so nothing is lost when that happens.
public struct Deck: Identifiable, Hashable, Sendable {
    public let id: String
    public let tier: WordTier
    /// 1-based position within the tier.
    public let index: Int
    public let wordIDs: [String]

    public var title: String { "\(tier.label) \(index)" }

    /// Split a tier's words into decks of 23–25: `ceil(n/25)` decks, sizes as
    /// even as they can be, so the last deck is never a runt.
    static func chunk(_ words: [Word], tier: WordTier, targetSize: Int = 25) -> [Deck] {
        guard !words.isEmpty else { return [] }
        let sorted = words.sorted { $0.zipf != $1.zipf ? $0.zipf > $1.zipf : $0.id < $1.id }
        let count = (sorted.count + targetSize - 1) / targetSize
        let base = sorted.count / count
        let extra = sorted.count % count   // the first `extra` decks take one more
        var start = 0
        return (0..<count).map { n in
            let size = base + (n < extra ? 1 : 0)
            defer { start += size }
            return Deck(
                id: "\(tier.rawValue)-\(n + 1)", tier: tier, index: n + 1,
                wordIDs: sorted[start..<start + size].map(\.id)
            )
        }
    }
}

extension WordTier {
    public var label: String {
        switch self {
        case .core: "Core"
        case .common: "Common"
        case .extended: "Extended"
        }
    }
}
