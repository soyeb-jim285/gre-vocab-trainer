import Foundation
import Testing
@testable import GRECore

/// Hits the real API. Opt in with a key:
///
///     OPENROUTER_API_KEY=sk-... GRE_LIVE_MODEL=google/gemini-3.7-flash swift test
///
/// Everything else about the client is covered by the stubbed tests; this exists
/// to catch the one thing they can't -- a provider that accepts our strict schema
/// request and answers with something else.
private let liveKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
private let liveModel = ProcessInfo.processInfo.environment["GRE_LIVE_MODEL"] ?? "google/gemini-3.7-flash"

@Suite(.enabled(if: liveKey?.isEmpty == false, "set OPENROUTER_API_KEY to run"))
struct OpenRouterLiveTests {

    @Test func listsModelsFromTheRealApi() async throws {
        let models = try await OpenRouterClient(apiKey: "").availableModels()
        #expect(models.count > 50)
        let allCapable = models.allSatisfy(\.supportsStructuredOutputs)
        #expect(allCapable)
    }

    @Test func aRealModelHonoursTheStrictGradeSchema() async throws {
        let client = OpenRouterClient(apiKey: try #require(liveKey))
        let result = try await client.grade(
            word: "abate",
            referenceDefinition: "become less in amount or intensity",
            partOfSpeech: "verb",
            learnerDefinition: "to die down or get weaker",
            learnerSentence: "The storm abated by morning.",
            model: liveModel
        )
        #expect((0...100).contains(result.definitionScore))
        #expect((0...100).contains(result.sentenceScore))
        #expect(result.correctedSentence.isEmpty == false)
        // A correct definition and a good sentence should not come back as a fail.
        #expect(result.rating != .again)
    }

    @Test func aWrongAnswerIsGradedDown() async throws {
        let client = OpenRouterClient(apiKey: try #require(liveKey))
        let result = try await client.grade(
            word: "abate",
            referenceDefinition: "become less in amount or intensity",
            partOfSpeech: "verb",
            learnerDefinition: "a type of large sailing ship",
            learnerSentence: "We boarded the abate at dawn.",
            model: liveModel
        )
        #expect(result.definitionScore < 40)
        #expect(result.rating == .again)
    }
}
