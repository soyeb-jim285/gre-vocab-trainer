import Foundation

/// What the model returns when it grades a definition-and-sentence answer.
public struct GradeResult: Equatable, Sendable {
    public let definitionScore: Int
    public let definitionFeedback: String
    public let sentenceScore: Int
    public let sentenceFeedback: String
    public let correctedSentence: String
    public let rating: FSRSRating
    public let missedNuances: [String]
    /// A vivid sentence to hang the word on. Asked for in the grading call
    /// rather than a second one, so it costs nothing extra.
    public let memorableSentence: String

    public init(
        definitionScore: Int, definitionFeedback: String, sentenceScore: Int,
        sentenceFeedback: String, correctedSentence: String, rating: FSRSRating,
        missedNuances: [String], memorableSentence: String = ""
    ) {
        self.definitionScore = Grade(score: definitionScore).score
        self.definitionFeedback = definitionFeedback
        self.sentenceScore = Grade(score: sentenceScore).score
        self.sentenceFeedback = sentenceFeedback
        self.correctedSentence = correctedSentence
        self.rating = rating
        self.missedNuances = missedNuances
        self.memorableSentence = memorableSentence
    }

    /// Knowing the meaning and being able to use it weigh the same.
    public var combinedScore: Int { (definitionScore + sentenceScore) / 2 }
}

extension GradeResult: Decodable {
    private enum CodingKeys: String, CodingKey {
        case definitionScore = "definition_score"
        case definitionFeedback = "definition_feedback"
        case sentenceScore = "sentence_score"
        case sentenceFeedback = "sentence_feedback"
        case correctedSentence = "corrected_sentence"
        case overallRating = "overall_rating"
        case missedNuances = "missed_nuances"
        case memorableSentence = "memorable_sentence"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Scores are clamped rather than validated: strict mode can't carry
        // minimum/maximum, so a model is free to hand back 140.
        let raw = try c.decodeIfPresent(Int.self, forKey: .overallRating) ?? 3
        self.init(
            definitionScore: try c.decode(Int.self, forKey: .definitionScore),
            definitionFeedback: try c.decodeIfPresent(String.self, forKey: .definitionFeedback) ?? "",
            sentenceScore: try c.decode(Int.self, forKey: .sentenceScore),
            sentenceFeedback: try c.decodeIfPresent(String.self, forKey: .sentenceFeedback) ?? "",
            correctedSentence: try c.decodeIfPresent(String.self, forKey: .correctedSentence) ?? "",
            rating: FSRSRating(rawValue: min(max(raw, 1), 4)) ?? .good,
            missedNuances: try c.decodeIfPresent([String].self, forKey: .missedNuances) ?? [],
            memorableSentence: try c.decodeIfPresent(String.self, forKey: .memorableSentence) ?? ""
        )
    }
}
