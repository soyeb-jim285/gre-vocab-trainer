import Foundation

/// One graded answer, as the curriculum needs to see it.
public struct ReviewEvidence: Equatable, Sendable {
    public let mode: StudyMode
    public let score: Int
    public let latency: Duration?
    public let at: Date

    public init(mode: StudyMode, score: Int, latency: Duration? = nil, at: Date) {
        self.mode = mode
        self.score = score
        self.latency = latency
        self.at = at
    }
}

/// What one word's history says about each way of asking it.
///
/// Derived on demand from the review log rather than stored. A denormalised copy
/// is a second thing to write, and it drifts the first time progress is reset.
public struct CardCompetence: Equatable, Sendable {

    /// The mark a mode has to clear to count as demonstrated. Fixed rather than
    /// following the learner's grading strictness: strictness tunes how the
    /// scheduler reacts to a score, but whether a mode has been shown to work is
    /// a question about the learner, and it should not move when they change a
    /// preference.
    public static let passingScore = 70

    public struct ModeRecord: Equatable, Sendable {
        public var attempts: Int = 0
        public var passes: Int = 0
        public var lastSeen: Date?

        public var accuracy: Double? {
            attempts == 0 ? nil : Double(passes) / Double(attempts)
        }
    }

    private var records: [StudyMode: ModeRecord] = [:]
    public private(set) var totalAttempts = 0

    public init(_ evidence: [ReviewEvidence]) {
        for item in evidence {
            var record = records[item.mode] ?? ModeRecord()
            record.attempts += 1
            if item.score >= Self.passingScore { record.passes += 1 }
            if let seen = record.lastSeen { record.lastSeen = max(seen, item.at) }
            else { record.lastSeen = item.at }
            records[item.mode] = record
            totalAttempts += 1
        }
    }

    public subscript(mode: StudyMode) -> ModeRecord {
        records[mode] ?? ModeRecord()
    }

    /// The candidate most worth asking next.
    ///
    /// A mode never tried wins outright: you cannot know someone is weak at
    /// something they have never been asked to do, and the modes test genuinely
    /// different abilities. Once every candidate has been tried, the weakest
    /// accuracy wins, which is the whole point of replacing a rotation.
    public func weakest(among candidates: [StudyMode]) -> StudyMode? {
        guard !candidates.isEmpty else { return nil }
        if let untried = candidates.first(where: { self[$0].attempts == 0 }) { return untried }
        return candidates.min { a, b in
            let (ra, rb) = (self[a], self[b])
            let (aa, ab) = (ra.accuracy ?? 0, rb.accuracy ?? 0)
            if aa != ab { return aa < ab }
            if ra.attempts != rb.attempts { return ra.attempts < rb.attempts }
            // Enum order, so the same history always picks the same mode.
            return candidates.firstIndex(of: a)! < candidates.firstIndex(of: b)!
        }
    }
}
