import Foundation

/// How many times a new word has to be got right on the day it is met.
///
/// Rawson and Dunlosky's successive relearning: practise to a criterion of
/// three correct recalls in the first session, then relearn in spaced sessions.
/// FSRS already does the spacing. Its learning steps graduate a word after two
/// passes, which is one short of the criterion and can be as little as one
/// lucky tap, so the session holds on to the word until it has earned three.
public enum LearningCriterion {

    public static let correctAnswersOnFirstDay = 3

    /// Words met today that are still owed a correct answer.
    ///
    /// - Parameters:
    ///   - introducedToday: words first met since the day rolled over.
    ///   - correctToday: correct answers per word since the day rolled over.
    public static func unmet(
        introducedToday: Set<String>, correctToday: [String: Int]
    ) -> Set<String> {
        introducedToday.filter { (correctToday[$0] ?? 0) < correctAnswersOnFirstDay }
    }

    /// Whether an answer counts toward the criterion. Quick rounds do not: a
    /// self-rated gloss and a charge guess are not recall of the meaning.
    public static func counts(score: Int, mode: StudyMode) -> Bool {
        score >= 70 && !mode.isQuickRound
    }
}
