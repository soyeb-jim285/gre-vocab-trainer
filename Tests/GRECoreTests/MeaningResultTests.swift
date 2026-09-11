import Foundation
import Testing
@testable import GRECore

/// The verdict on a typed meaning, and the draft that carries one.
@Suite struct MeaningResultTests {

    private func decode(_ json: String) throws -> MeaningResult {
        try JSONDecoder().decode(MeaningResult.self, from: Data(json.utf8))
    }

    @Test func decodesTheGradedFields() throws {
        let result = try decode("""
        {"score": 3, "matched_misconception": "", "feedback": "Nearly. You missed the nuance."}
        """)
        #expect(result.score == 3)
        #expect(result.matchedMisconception.isEmpty)
        #expect(result.feedback == "Nearly. You missed the nuance.")
    }

    @Test func aScoreOutsideTheScaleIsClamped() throws {
        // The schema cannot carry numeric bounds reliably across providers, so
        // a model answering 7 must not become a grade of 175.
        #expect(try decode(#"{"score": 7, "matched_misconception": "", "feedback": ""}"#).score == 4)
        #expect(try decode(#"{"score": -2, "matched_misconception": "", "feedback": ""}"#).score == 0)
    }

    @Test func missingOptionalFieldsDecodeAsEmpty() throws {
        // Strict mode asks for every key, but a provider that drops one should
        // cost the learner a label, not the whole answer.
        let result = try decode(#"{"score": 2}"#)
        #expect(result.matchedMisconception.isEmpty)
        #expect(result.feedback.isEmpty)
    }

    @Test func scoresMapOntoTheHundredPointScaleTheAppSpeaks() throws {
        #expect(try decode(#"{"score": 0}"#).percentage == 0)
        #expect(try decode(#"{"score": 2}"#).percentage == 50)
        #expect(try decode(#"{"score": 4}"#).percentage == 100)
    }

    @Test func confidentlyWrongNeedsBothAWrongAnswerAndANamedMisconception() throws {
        // An answer that is merely wrong is weak evidence of a weak memory. One
        // that matches a misconception the word's grounding predicted is a wrong
        // memory competing with the right one, which is worse.
        let confident = try decode("""
        {"score": 1, "matched_misconception": "confuses evasiveness with lying", "feedback": ""}
        """)
        #expect(confident.isConfidentlyWrong)
        #expect(!(try decode(#"{"score": 1, "matched_misconception": "", "feedback": ""}"#)
            .isConfidentlyWrong))
        #expect(!(try decode("""
        {"score": 3, "matched_misconception": "confuses evasiveness with lying", "feedback": ""}
        """).isConfidentlyWrong))
    }

    @Test func aTypedMeaningIsItsOwnKindOfAnswer() {
        // Not `.written` with an empty sentence: that would be unsubmittable,
        // because the graded mode requires both halves.
        #expect(AnswerDraft.meaning("to lessen").isSubmittable)
        #expect(!AnswerDraft.meaning("   ").isSubmittable)
        #expect(!AnswerDraft.written(definition: "to lessen", sentence: "").isSubmittable)
    }

    @Test func aTypedMeaningNeedsTheModel() throws {
        let catalog = try WordCatalog.bundled()
        let word = try #require(catalog["abate"])
        let item = SessionItem(card: StudyCard(wordID: word.id), word: word, mode: .typeMeaning)
        // Nil is the judge saying "this one is not mine", which is what routes
        // the answer to the grounded grader.
        #expect(AnswerJudge.judge(.meaning("to lessen"), item: item) == nil)
    }

    @Test func givingUpIsStillJudgedLocally() throws {
        // Paying a model to confirm that an empty answer is wrong would be absurd.
        let catalog = try WordCatalog.bundled()
        let word = try #require(catalog["abate"])
        let item = SessionItem(card: StudyCard(wordID: word.id), word: word, mode: .typeMeaning)
        let judgement = try #require(AnswerJudge.judge(.gaveUp, item: item))
        #expect(judgement.rating == .again)
    }
}
