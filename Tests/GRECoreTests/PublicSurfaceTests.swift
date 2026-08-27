import Foundation
import GRECore  // NOT @testable, deliberately: this file sees exactly what the app sees.
import Testing

/// Exercises every GRECore API the app target calls.
///
/// `@testable import` grants internal access, so the rest of the suite cannot
/// catch a type whose memberwise init was never made public -- that only shows
/// up when the app compiles, which happens on a macOS runner minutes away. This
/// file reproduces the app's view of the module and fails in a second instead.
@Suite struct PublicSurfaceTests {

    @Test func everyValueTheAppConstructsIsPubliclyConstructible() {
        _ = FSRSCard(stability: 1, difficulty: 5, due: .now, lastReview: nil, state: .review, step: nil)
        _ = FSRS(desiredRetention: 0.9)
        _ = StudyCard(wordID: "abate", fsrs: FSRSCard(), reviewCount: 0)
        _ = SessionSettings(strictness: .standard, aiEnabled: false)
        _ = Grade(score: 50)
        _ = WordCatalog.empty
        _ = OpenRouterClient(apiKey: "")
        _ = GradeResult(
            definitionScore: 1, definitionFeedback: "", sentenceScore: 1,
            sentenceFeedback: "", correctedSentence: "", rating: .good,
            missedNuances: [], memorableSentence: ""
        ).memorableSentence
        _ = WordDeepDive(etymology: "", mnemonic: "", nuance: "", confusableWith: [])
        _ = CoachSummary(summary: "", focusAreas: [], encouragement: "")
    }

    @Test func sessionItemCanBeBuiltByHandForPracticeOutsideASession() throws {
        // Writing practice reuses the session's feedback view for a single word,
        // so it builds a SessionItem itself rather than getting one from the planner.
        let catalog = try WordCatalog.bundled()
        let word = try #require(catalog["abate"])
        let item = SessionItem(card: StudyCard(wordID: word.id), word: word, mode: .defineAndUse)
        #expect(item.mode == .defineAndUse)
        #expect(item.word.id == "abate")
    }

    @Test func everyPropertyTheAppReadsIsPubliclyReadable() throws {
        let catalog = try WordCatalog.bundled()
        let word = try #require(catalog["abate"])

        // Word rendering
        _ = (word.id, word.word, word.ipa, word.tier, word.listCount, word.sourceLists, word.senses)
        _ = (word.zipf, word.difficulty)
        _ = catalog.words(withDifficulty: .familiar)
        _ = (word.primarySense, word.primaryPartOfSpeech)
        let sense = word.primarySense
        _ = (sense.pos.rawValue, sense.definition, sense.examples, sense.synonyms, sense.antonyms)

        // Catalog queries used by the word list and distractors
        _ = catalog.words
        _ = catalog.words(inTier: .core)
        _ = catalog.words(withPartOfSpeech: .verb)
        _ = DistractorPicker.distractors(for: word, from: catalog, count: 3)

        // Scheduling round trip, as the view model does it
        let card = StudyCard(wordID: word.id)
        let settings = SessionSettings(aiEnabled: false, currentDeckID: catalog.decks.first?.id)
        let item = SessionPlanner.next(
            cards: [card], catalog: catalog, settings: settings, scheduler: FSRS(),
            recentAccuracy: 72, recentWordIDs: [], allowEarly: false, now: .now
        )
        if let item { _ = (item.card, item.word, item.mode) }
        _ = SessionPlanner.nextDue(cards: [card], now: .now)
        _ = SessionPlanner.learningLoadCap(forAccuracy: 72)
        // Decks and mastery, as the Decks tab and Progress read them
        _ = catalog.decks.map { ($0.id, $0.title, $0.tier, $0.index, $0.wordIDs) }
        _ = catalog.decks(inTier: .core)
        _ = catalog.deck(id: "core-1")
        _ = catalog.deck(containing: word.id)
        _ = WordTier.core.label
        _ = Mastery(card: card).label
        _ = Mastery(stability: 5)
        _ = Mastery.allCases.map(\.rawValue)
        let progress = DeckProgress(deck: catalog.decks[0], cards: [word.id: card])
        _ = (progress.counts, progress.total, progress.fraction, progress.isComplete, progress.count(atLeast: .known))
        _ = QuizPlanner.deckTest(deck: catalog.decks[0], cards: [card], catalog: catalog, seed: 1)
        _ = QuizPlanner.globalTest(cards: [card], catalog: catalog, scheduler: FSRS(), seed: 1, now: .now)
        _ = QuizPlanner.minimumWords
        let scheduled = FSRS().review(card.fsrs, rating: .good, at: .now)
        _ = (scheduled.stability, scheduled.difficulty, scheduled.due,
             scheduled.lastReview, scheduled.state, scheduled.step)
        _ = FSRS().retrievability(scheduled, at: .now)

        // Grading
        _ = LocalGrader.gradeSpelling(typed: "abate", expected: "abate").grade.score
        _ = LocalGrader.gradeSpelling(typed: "abate", expected: "abate").isExact
        _ = LocalGrader.gradeSpelling(typed: "abate", expected: "abate").editDistance
        _ = LocalGrader.gradeRecall(typed: "abate", expected: "abate")
        _ = Grade(score: 80).rating(strictness: .strict)

        // Enum surfaces the UI iterates
        _ = StudyMode.allCases.map(\.rawValue)
        _ = StudyMode.allCases.map(\.label)
        _ = StudyMode.allCases.map(\.systemImage)
        _ = SessionSettings(aiEnabled: true, writingModeAfterReviews: 0, forcedMode: .spelling)
        _ = WordDifficulty.allCases.sorted()
        _ = CallCost(promptTokens: 1, completionTokens: 2, usd: 0.001).displayCost
        _ = CallCost(promptTokens: 1, completionTokens: 2, usd: nil).totalTokens
        _ = StudyMode.locallyGraded
        _ = StudyMode.defineAndUse.needsAI
        _ = WordTier.allCases.sorted()
        _ = PartOfSpeech.allCases
        _ = GradingStrictness.allCases.map(\.rawValue)
        _ = FSRSRating.allCases.map(\.rawValue)
        _ = FSRSState.review.rawValue
    }

    @Test func modelListingSurfaceIsPublic() throws {
        // Fields the model picker renders.
        let json = Data("""
        {"data":[{"id":"a/b","name":"A B","context_length":128000,
        "pricing":{"prompt":"0.000001","completion":"0.000002"},
        "supported_parameters":["structured_outputs"]}]}
        """.utf8)
        struct Envelope: Decodable { let data: [OpenRouterModel] }
        let model = try #require(try JSONDecoder().decode(Envelope.self, from: json).data.first)
        _ = (model.id, model.name, model.contextLength, model.supportedParameters)
        _ = (model.pricing.promptPerToken, model.pricing.completionPerToken)
        #expect(model.supportsStructuredOutputs)
    }

    @Test func errorsExposeWhatTheUiShows() {
        let error = OpenRouterError.http(status: 429, message: "slow down")
        _ = error.description
        #expect(error.isRetryable)
        #expect(OpenRouterError.missingAPIKey.isRetryable == false)
    }
}
