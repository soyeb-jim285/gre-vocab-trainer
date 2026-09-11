import Foundation

/// The verdict on a typed meaning, graded against the word's ``Grounding``.
///
/// Deliberately not ``GradeResult``. That one judges two things at once, a
/// definition and a sentence, and returns eight fields to say so. This judges
/// one free answer and returns what the model needs back: how close it was,
/// which known misconception it matched if any, and one or two sentences that
/// correct rather than mark.
public struct MeaningResult: Equatable, Sendable, Codable {
    /// 0 to 4. Zero is nothing usable, four is precise including the nuance.
    public let score: Int
    /// The `misconception` label of the matched incorrect association, or empty
    /// when the answer was not one the word's grounding anticipated.
    ///
    /// This is what makes a wrong answer teachable: "confuses evasiveness with
    /// lying" can be corrected, where "wrong" can only be marked.
    public let matchedMisconception: String
    /// One or two sentences addressed to the learner, correcting the gap.
    public let feedback: String

    /// True when the answer was confident and wrong in a way the grounding
    /// predicted, which is the state worth treating as worse than never seen.
    public var isConfidentlyWrong: Bool { score <= 1 && !matchedMisconception.isEmpty }

    public init(score: Int, matchedMisconception: String, feedback: String) {
        // The schema cannot enforce a numeric range across providers, so the
        // clamp lives here. A model that answers 7 must not become a grade of
        // 175 downstream.
        self.score = min(max(score, 0), 4)
        self.matchedMisconception = matchedMisconception
        self.feedback = feedback
    }

    /// The 0-100 grade the rest of the app already speaks.
    public var percentage: Int { score * 25 }

    private enum CodingKeys: String, CodingKey {
        case score
        case matchedMisconception = "matched_misconception"
        case feedback
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            score: try c.decode(Int.self, forKey: .score),
            matchedMisconception: try c.decodeIfPresent(String.self, forKey: .matchedMisconception) ?? "",
            feedback: try c.decodeIfPresent(String.self, forKey: .feedback) ?? ""
        )
    }
}
