import Foundation

public struct SpellingResult: Equatable, Sendable {
    public let grade: Grade
    public let isExact: Bool
    public let editDistance: Int
}

/// Grading for the modes that don't need a model: spelling and word recall.
///
/// The two modes deliberately treat a typo differently. Spelling is *about*
/// getting the letters right, so a near miss still fails. Recall is about
/// retrieving the word at all, so a near miss passes.
public enum LocalGrader {

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func gradeSpelling(typed: String, expected: String) -> SpellingResult {
        let typed = normalize(typed), expected = normalize(expected)
        guard !typed.isEmpty else {
            return SpellingResult(grade: Grade(score: 0), isExact: false, editDistance: expected.count)
        }
        if typed == expected {
            return SpellingResult(grade: Grade(score: 100), isExact: true, editDistance: 0)
        }

        let distance = levenshtein(typed, expected)
        // Scores stay under the .good band on purpose: a misspelling is a
        // misspelling. Closer attempts still score higher so they come back
        // sooner rather than being lumped in with a blank.
        let score = switch distance {
        case 1: 50
        case 2: 25
        default: 0
        }
        return SpellingResult(grade: Grade(score: score), isExact: false, editDistance: distance)
    }

    public static func gradeRecall(typed: String, expected: String) -> Grade {
        let typed = normalize(typed), expected = normalize(expected)
        guard !typed.isEmpty else { return Grade(score: 0) }
        if typed == expected { return Grade(score: 100) }

        // ponytail: flat bands by edit distance. If longer words start being
        // judged too harshly, scale the tolerance by expected.count.
        return switch levenshtein(typed, expected) {
        case 1: Grade(score: 80)
        case 2: Grade(score: 55)
        default: Grade(score: 0)
        }
    }
}
