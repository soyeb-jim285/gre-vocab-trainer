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

    var wordID: String = ""
    var stability: Double?
    var difficulty: Double?
    var due: Date = Date.distantPast
    var lastReview: Date?
    var stateRaw: Int = FSRSState.learning.rawValue
    var step: Int?
    var reviewCount: Int = 0
    var lapses: Int = 0

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
        StudyCard(wordID: wordID, fsrs: fsrs, reviewCount: reviewCount)
    }
}

/// Every graded answer, kept for the stats screen and the coach prompt.
@Model
final class ReviewRecord {
    var wordID: String = ""
    var reviewedAt: Date = Date.distantPast
    var modeRaw: String = StudyMode.multipleChoice.rawValue
    var score: Int = 0
    var ratingRaw: Int = FSRSRating.good.rawValue

    init(wordID: String, reviewedAt: Date, mode: StudyMode, score: Int, rating: FSRSRating) {
        self.wordID = wordID
        self.reviewedAt = reviewedAt
        self.modeRaw = mode.rawValue
        self.score = score
        self.ratingRaw = rating.rawValue
    }

    var mode: StudyMode { StudyMode(rawValue: modeRaw) ?? .multipleChoice }
    var rating: FSRSRating { FSRSRating(rawValue: ratingRaw) ?? .good }
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
