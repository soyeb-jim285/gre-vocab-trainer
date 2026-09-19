import Foundation

/// One "tell these two apart" question: the word, a neighbour it is easy to mix
/// up with, and the line that separates them.
public struct DiscriminationQuestion: Equatable, Sendable {
    /// The word being asked about. Its definition is the prompt.
    public let word: Word
    /// The near-miss offered alongside it.
    public let partner: Word
    /// Read afterwards, whether or not the answer was right.
    public let distinction: String

    public init(word: Word, partner: Word, distinction: String) {
        self.word = word
        self.partner = partner
        self.distinction = distinction
    }

    /// Both words, in a stable order that is not the answer's order.
    ///
    /// Sorted by a hash of the pair rather than shuffled, so the answer is
    /// neither always first nor different on every launch: position can never
    /// be the tell, and it can never be a memory aid either.
    public var options: [Word] {
        [word, partner].sorted {
            stableKey($0.id, salt: word.id + "|" + partner.id)
                < stableKey($1.id, salt: word.id + "|" + partner.id)
        }
    }
}

/// Builds discrimination questions from the dataset's confusion annotations.
///
/// The pairs are hand-written and already verified to name both words, which is
/// why the distinction is feedback rather than prompt: showing it first would
/// hand over the answer.
public enum ConfusionDrill {

    /// Whether this word has a neighbour to be told apart from.
    ///
    /// - Parameter met: words the learner has already been introduced to. A
    ///   partner outside it is skipped: two similar words that are both new
    ///   interfere with each other, and telling them apart only helps once one
    ///   of them is held. Nil skips the check.
    public static func isAvailable(
        for word: Word, in catalog: WordCatalog, met: Set<String>? = nil
    ) -> Bool {
        partners(for: word, in: catalog, met: met).isEmpty == false
    }

    /// A question for this word, or nil when it has no usable neighbour.
    ///
    /// - Parameter preferring: neighbours this learner has already mixed up.
    ///   A pair that has actually caused trouble is worth more than one that
    ///   merely could, and drilling it is the only way to find out whether the
    ///   confusion has been cleared.
    /// - Parameter attempt: varies the pair across exposures, so a word with
    ///   three neighbours is not asked against the same one every time.
    public static func question(
        for word: Word, from catalog: WordCatalog,
        preferring confused: Set<String> = [], attempt: Int = 0,
        met: Set<String>? = nil
    ) -> DiscriminationQuestion? {
        let usable = partners(for: word, in: catalog, met: met)
        guard !usable.isEmpty else { return nil }
        let troubled = usable.filter { confused.contains($0.0.id) }
        let pool = troubled.isEmpty ? usable : troubled
        let (partner, distinction) = pool[abs(attempt) % pool.count]
        return DiscriminationQuestion(word: word, partner: partner, distinction: distinction)
    }

    /// The line to show after a discrimination answer, found from the pair the
    /// question was built with.
    public static func distinction(for item: SessionItem) -> String? {
        guard let with = item.confusedWith else { return nil }
        return item.word.confusion?.first { $0.with == with }?.distinction
    }

    /// Annotated neighbours that are actually in this catalog, in dataset order
    /// so the choice is reproducible.
    private static func partners(
        for word: Word, in catalog: WordCatalog, met: Set<String>? = nil
    ) -> [(Word, String)] {
        (word.confusion ?? []).compactMap { pair in
            guard met?.contains(pair.with) ?? true else { return nil }
            return catalog[pair.with].map { ($0, pair.distinction) }
        }
    }
}

/// Order-only hash. Not security, and not stored: it just has to be the same
/// every launch, which `hashValue` is not.
private func stableKey(_ value: String, salt: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in (salt + value).utf8 {
        hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
    return hash
}
