import Foundation
import GRECore
import SwiftData

/// One word's scheduling state on disk.
///
/// GRECore owns the algorithm and knows nothing about SwiftData; this class
/// stores the fields and bridges to the value type the scheduler works in.
@Model
final class CardRecord {
    #Unique<CardRecord>([\.wordID])
    #Index<CardRecord>([\.due])

    var wordID: String = ""
    var stability: Double?
    var difficulty: Double?
    var due: Date = Date.distantPast
    var lastReview: Date?
    var stateRaw: Int = FSRSState.learning.rawValue
    var step: Int?
    var reviewCount: Int = 0
    var lapses: Int = 0
    /// Set once, when the word is first taught. Distinct from `reviewCount > 0`
    /// only in that it survives a mode being added later.
    var introducedAt: Date?
    /// True when the learner proved they already knew this word on first
    /// contact, before it was ever taught.
    ///
    /// Stored rather than derived. "Never taught" cannot be read off
    /// `introducedAt`, because a word that was tested first and taught later
    /// carries the same absence, and Progress needs to count the two apart.
    var knownOnFirstContact: Bool = false

    init(wordID: String) {
        self.wordID = wordID
        self.due = .distantPast
    }

    var fsrs: FSRSCard {
        get {
            FSRSCard(
                stability: stability, difficulty: difficulty, due: due,
                lastReview: lastReview,
                state: FSRSState(rawValue: stateRaw) ?? .learning, step: step
            )
        }
        set {
            stability = newValue.stability
            difficulty = newValue.difficulty
            due = newValue.due
            lastReview = newValue.lastReview
            stateRaw = newValue.state.rawValue
            step = newValue.step
        }
    }

    var studyCard: StudyCard {
        StudyCard(wordID: wordID, fsrs: fsrs, reviewCount: reviewCount,
                  isIntroduced: introducedAt != nil)
    }
}

/// Every answer, kept for the stats screen, the coach prompt, and as the only
/// source of what the learner can do in each mode.
///
/// Money is deliberately not here. Spend is tracked in ``AICall`` because deep
/// dives, mnemonics and the coach cost money without producing a review, and a
/// budget cap over a partial ledger is not a cap.
@Model
final class ReviewRecord {
    #Index<ReviewRecord>([\.wordID], [\.reviewedAt])

    var wordID: String = ""
    var reviewedAt: Date = Date.distantPast
    var modeRaw: String = StudyMode.multipleChoice.rawValue
    var score: Int = 0
    var ratingRaw: Int = FSRSRating.good.rawValue
    /// How long the answer took. Stored even when tainted, so the confidence
    /// bands can be retuned against real times rather than guessed at twice.
    var latencyMS: Int = 0
    /// The time is not evidence about this answer: audio played, the learner
    /// gave up, or they walked away mid-card.
    var latencyTainted: Bool = false
    /// An ungraded first meeting. Excluded from accuracy and from competence:
    /// being shown a word is not evidence that you can do anything with it.
    var isIntroduction: Bool = false

    init(
        wordID: String, reviewedAt: Date, mode: StudyMode, score: Int, rating: FSRSRating,
        latency: Duration? = nil, latencyTainted: Bool = false, isIntroduction: Bool = false
    ) {
        self.wordID = wordID
        self.reviewedAt = reviewedAt
        self.modeRaw = mode.rawValue
        self.score = score
        self.ratingRaw = rating.rawValue
        self.latencyMS = latency.map(\.milliseconds) ?? 0
        self.latencyTainted = latencyTainted
        self.isIntroduction = isIntroduction
    }

    var mode: StudyMode { StudyMode(rawValue: modeRaw) ?? .multipleChoice }
    var rating: FSRSRating { FSRSRating(rawValue: ratingRaw) ?? .good }

    /// Nil when there is no usable time, which the curriculum reads as "no
    /// opinion" rather than "answered instantly".
    var latency: Duration? {
        guard latencyMS > 0, !latencyTainted else { return nil }
        return .milliseconds(latencyMS)
    }

    var evidence: ReviewEvidence {
        ReviewEvidence(mode: mode, score: score, latency: latency, at: reviewedAt)
    }
}

/// What a model call cost, whatever it was for.
///
/// One table so that one number can be checked before every call. The previous
/// total summed session grading alone, so deep dives and the coach spent money
/// the app never counted.
@Model
final class AICall {
    #Index<AICall>([\.at])

    var at: Date = Date.distantPast
    var kindRaw: String = AICallKind.grading.rawValue
    var usd: Double = 0
    var promptTokens: Int = 0
    var completionTokens: Int = 0

    init(kind: AICallKind, cost: CallCost?, at: Date) {
        self.at = at
        self.kindRaw = kind.rawValue
        self.usd = cost?.usd ?? 0
        self.promptTokens = cost?.promptTokens ?? 0
        self.completionTokens = cost?.completionTokens ?? 0
    }

    var kind: AICallKind { AICallKind(rawValue: kindRaw) ?? .grading }
}

enum AICallKind: String, Codable, CaseIterable {
    case grading, deepDive, mnemonic, coach

    var label: String {
        switch self {
        case .grading: "Grading"
        case .deepDive: "Deep dive"
        case .mnemonic: "Mnemonic"
        case .coach: "Coach"
        }
    }
}

/// Cached deep dives, so a word is only ever paid for once.
@Model
final class DeepDiveRecord {
    #Unique<DeepDiveRecord>([\.wordID])

    var wordID: String = ""
    var etymology: String = ""
    var mnemonic: String = ""
    var nuance: String = ""
    var confusableWith: [String] = []
    var fetchedAt: Date = Date.distantPast

    init(wordID: String, dive: WordDeepDive, fetchedAt: Date) {
        self.wordID = wordID
        self.etymology = dive.etymology
        self.mnemonic = dive.mnemonic
        self.nuance = dive.nuance
        self.confusableWith = dive.confusableWith
        self.fetchedAt = fetchedAt
    }
}

/// A wrong idea this learner actually held, kept so it can be drilled rather
/// than merely corrected once.
///
/// Corrective feedback disappears the moment the card advances. A learner who
/// thinks `enervate` means "energise" will think it again next week unless
/// something remembers that they did, which is what this is for: the confusion
/// drill asks about the pairs that have gone wrong before, and Progress can
/// show what is still being mixed up.
@Model
final class MisconceptionRecord {
    #Index<MisconceptionRecord>([\.wordID])

    var wordID: String = ""
    var kindRaw: String = MisconceptionKind.meaning.rawValue
    /// The misconception line for a graded meaning, or the id of the word
    /// chosen instead for a confusion drill.
    var text: String = ""
    var at: Date = Date.distantPast

    init(wordID: String, kind: MisconceptionKind, text: String, at: Date) {
        self.wordID = wordID
        self.kindRaw = kind.rawValue
        self.text = text
        self.at = at
    }

    var kind: MisconceptionKind { MisconceptionKind(rawValue: kindRaw) ?? .meaning }
}

enum MisconceptionKind: String, Codable, CaseIterable {
    /// The grader matched one of the word's known wrong associations.
    case meaning
    /// A confusion drill was answered with the neighbour.
    case confusion
}

/// One finished test, for the deck's best score.
@Model
final class QuizRecord {
    /// Nil for a test over everything studied.
    var deckID: String?
    var score: Int = 0
    var wordCount: Int = 0
    var takenAt: Date = Date.distantPast

    init(deckID: String?, score: Int, wordCount: Int, takenAt: Date) {
        self.deckID = deckID
        self.score = score
        self.wordCount = wordCount
        self.takenAt = takenAt
    }
}

extension Duration {
    /// Whole milliseconds, sub-second part included -- truncating to whole
    /// seconds would round every quick tap down to nothing.
    var milliseconds: Int {
        let parts = components
        return Int(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
    }
}
