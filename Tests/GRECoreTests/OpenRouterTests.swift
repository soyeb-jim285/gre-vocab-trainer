import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import GRECore

// MARK: - Test transport

/// Records the request it was given and replays a canned response.
private enum StubError: Error { case noRequestBody }

private actor StubTransport: HTTPTransport {
    private let status: Int
    private let body: Data
    private(set) var lastRequest: URLRequest?

    init(status: Int = 200, body: Data) {
        self.status = status
        self.body = body
    }
    init(status: Int = 200, json: String) {
        self.init(status: status, body: Data(json.utf8))
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lastRequest = request
        return (body, status)
    }

    /// Returns Data rather than the parsed dictionary: [String: Any] isn't
    /// Sendable, so it can't cross the actor boundary.
    func requestBodyData() throws -> Data {
        guard let data = lastRequest?.httpBody else { throw StubError.noRequestBody }
        return data
    }
}

private func parseBody(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw StubError.noRequestBody
    }
    return object
}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

/// A chat-completions envelope whose message content is `payload`, as the real
/// API returns it -- structured output arrives as a JSON *string*, not an object.
private func completion(_ payload: String, usage: String? = nil) -> String {
    let escaped = String(data: try! JSONEncoder().encode(payload), encoding: .utf8)!
    let usagePart = usage.map { ",\"usage\":\($0)" } ?? ""
    return #"{"id":"gen-1","choices":[{"message":{"role":"assistant","content":\#(escaped)}}]\#(usagePart)}"#
}

private let usageBlock = #"{"prompt_tokens":412,"completion_tokens":96,"total_tokens":508,"cost":0.00031}"#

private let validGradePayload = """
{"definition_score":82,"definition_feedback":"Close, but you missed the intensity.",\
"sentence_score":70,"sentence_feedback":"Grammatical but the word is doing no work.",\
"corrected_sentence":"The storm abated by morning.","overall_rating":3,\
"missed_nuances":["implies gradual decrease"],\
"memorable_sentence":"By dawn the gale had abated to a whisper against the shutters."}
"""

// MARK: - Model listing

@Suite struct OpenRouterModelTests {

    @Test func decodesTheModelsEndpoint() throws {
        let models = try OpenRouterClient.decodeModels(from: fixture("openrouter_models"))
        #expect(models.count == 5)
        let first = try #require(models.first)
        #expect(first.id.isEmpty == false)
        #expect(first.contextLength > 0)
    }

    @Test func decodesPricingWhichTheApiSendsAsStrings() throws {
        let models = try OpenRouterClient.decodeModels(from: fixture("openrouter_models"))
        // Every price must parse; a nil here would silently sort free models wrong.
        let allPricesParsed = models.allSatisfy { $0.pricing.promptPerToken >= 0 }
        #expect(allPricesParsed)
        let hasFree = models.contains { $0.pricing.promptPerToken == 0 }
        #expect(hasFree, "expected a free model in the fixture")
        let hasPaid = models.contains { $0.pricing.promptPerToken > 0 }
        #expect(hasPaid)
    }

    @Test func flagsWhichModelsCanDoStructuredOutputs() throws {
        let models = try OpenRouterClient.decodeModels(from: fixture("openrouter_models"))
        let capable = models.filter(\.supportsStructuredOutputs)
        #expect(capable.count == 3)
        let allFlagged = capable.allSatisfy { $0.supportedParameters.contains("structured_outputs") }
        #expect(allFlagged)
    }

    @Test func availableModelsHidesModelsThatCannotHonourTheSchema() async throws {
        let transport = StubTransport(body: try fixture("openrouter_models"))
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        let models = try await client.availableModels()
        // Offering a model that can't do structured outputs would fail at grade time.
        #expect(models.count == 3)
        let allCapable = models.allSatisfy(\.supportsStructuredOutputs)
        #expect(allCapable)
    }

    @Test func listingModelsDoesNotRequireAnApiKey() async throws {
        let transport = StubTransport(body: try fixture("openrouter_models"))
        let client = OpenRouterClient(apiKey: "", transport: transport)
        _ = try await client.availableModels()
        let auth = await transport.lastRequest?.value(forHTTPHeaderField: "Authorization")
        #expect(auth == nil)
    }
}

// MARK: - Strict schema

@Suite struct OpenRouterStrictSchemaTests {

    private func gradeRequestBody() async throws -> [String: Any] {
        let transport = StubTransport(json: completion(validGradePayload))
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        _ = try await client.grade(
            word: "abate", referenceDefinition: "make less active or intense",
            partOfSpeech: "verb", learnerDefinition: "to lessen",
            learnerSentence: "The storm abated.", model: "test/model"
        )
        return try parseBody(try await transport.requestBodyData())
    }

    @Test func asksForStrictJsonSchema() async throws {
        let body = try await gradeRequestBody()
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["json_schema"] as? [String: Any])
        #expect(schema["strict"] as? Bool == true)
        #expect((schema["name"] as? String)?.isEmpty == false)
    }

    @Test func routesOnlyToProvidersThatHonourTheSchema() async throws {
        let body = try await gradeRequestBody()
        let provider = try #require(body["provider"] as? [String: Any])
        // Without this an endpoint may silently ignore response_format.
        #expect(provider["require_parameters"] as? Bool == true)
    }

    @Test func everyObjectInTheSchemaClosesItselfAndRequiresEveryProperty() async throws {
        let body = try await gradeRequestBody()
        let root = try #require(
            ((body["response_format"] as? [String: Any])?["json_schema"] as? [String: Any])?["schema"] as? [String: Any]
        )

        // Strict mode demands both of these on every object, at every depth.
        func check(_ object: [String: Any], path: String) {
            guard object["type"] as? String == "object" else { return }
            #expect(object["additionalProperties"] as? Bool == false, "\(path): additionalProperties must be false")
            let properties = (object["properties"] as? [String: Any]) ?? [:]
            let required = Set((object["required"] as? [String]) ?? [])
            #expect(required == Set(properties.keys), "\(path): every property must be required")
            for (key, value) in properties {
                if let nested = value as? [String: Any] {
                    check(nested, path: "\(path).\(key)")
                    if let items = nested["items"] as? [String: Any] { check(items, path: "\(path).\(key)[]") }
                }
            }
        }
        check(root, path: "schema")
    }

    @Test func schemaAvoidsNumericBoundsBecauseStrictModeDoesNotCarryThem() async throws {
        let body = try await gradeRequestBody()
        let json = try #require(try? JSONSerialization.data(withJSONObject: body))
        let text = String(decoding: json, as: UTF8.self)
        #expect(text.contains("\"minimum\"") == false)
        #expect(text.contains("\"maximum\"") == false)
    }

    @Test func ratingUsesAnEnumWhichStrictModeDoesSupport() async throws {
        let body = try await gradeRequestBody()
        let properties = try #require(
            (((body["response_format"] as? [String: Any])?["json_schema"] as? [String: Any])?["schema"]
                as? [String: Any])?["properties"] as? [String: Any]
        )
        let rating = try #require(properties["overall_rating"] as? [String: Any])
        #expect(rating["enum"] as? [Int] == [1, 2, 3, 4])
    }

    @Test func theSchemaAsksForAMemorableSentence() async throws {
        let body = try await gradeRequestBody()
        let properties = try #require(
            (((body["response_format"] as? [String: Any])?["json_schema"] as? [String: Any])?["schema"]
                as? [String: Any])?["properties"] as? [String: Any]
        )
        #expect(properties["memorable_sentence"] != nil)
    }

    @Test func thePromptAsksForASentenceWorthRemembering() async throws {
        let body = try await gradeRequestBody()
        let messages = try #require(body["messages"] as? [[String: Any]])
        let text = messages.compactMap { $0["content"] as? String }.joined(separator: "\n").lowercased()
        #expect(text.contains("memorable") || text.contains("remember"))
    }

    @Test func sendsTheChosenModelAndTheApiKey() async throws {
        let transport = StubTransport(json: completion(validGradePayload))
        let client = OpenRouterClient(apiKey: "sk-secret", transport: transport)
        _ = try await client.grade(
            word: "abate", referenceDefinition: "d", partOfSpeech: "verb",
            learnerDefinition: "x", learnerSentence: "y", model: "vendor/model-name"
        )
        let body = try parseBody(try await transport.requestBodyData())
        #expect(body["model"] as? String == "vendor/model-name")
        let auth = await transport.lastRequest?.value(forHTTPHeaderField: "Authorization")
        #expect(auth == "Bearer sk-secret")
    }

    @Test func includesTheReferenceDefinitionSoTheModelGradesAgainstItNotItsOwnRecall() async throws {
        let transport = StubTransport(json: completion(validGradePayload))
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        _ = try await client.grade(
            word: "abate", referenceDefinition: "make less active or intense",
            partOfSpeech: "verb", learnerDefinition: "to lessen",
            learnerSentence: "The storm abated.", model: "test/model"
        )
        let body = try parseBody(try await transport.requestBodyData())
        let messages = try #require(body["messages"] as? [[String: Any]])
        let text = messages.compactMap { $0["content"] as? String }.joined(separator: "\n")
        #expect(text.contains("make less active or intense"))
        #expect(text.contains("abate"))
        #expect(text.contains("to lessen"))
        #expect(text.contains("The storm abated."))
    }
}

// MARK: - Responses and failures

@Suite struct OpenRouterResponseTests {

    @Test func parsesAGradeOutOfTheMessageContent() async throws {
        let transport = StubTransport(json: completion(validGradePayload))
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        let result = try await client.grade(
            word: "abate", referenceDefinition: "d", partOfSpeech: "verb",
            learnerDefinition: "x", learnerSentence: "y", model: "m"
        )
        #expect(result.definitionScore == 82)
        #expect(result.sentenceScore == 70)
        #expect(result.correctedSentence == "The storm abated by morning.")
        #expect(result.missedNuances == ["implies gradual decrease"])
        #expect(result.rating == .good)
        // A vivid sentence to remember the word by, asked for in the same call
        // rather than a second one.
        #expect(result.memorableSentence == "By dawn the gale had abated to a whisper against the shutters.")
    }

    @Test func aGradeWithoutAMemorableSentenceStillDecodes() throws {
        // Older cached payloads, and providers that drop an optional field.
        let payload = #"{"definition_score":50,"sentence_score":50,"overall_rating":2}"#
        let result = try JSONDecoder().decode(GradeResult.self, from: Data(payload.utf8))
        #expect(result.memorableSentence.isEmpty)
    }

    @Test func clampsScoresAModelPutOutOfRange() async throws {
        let payload = validGradePayload
            .replacingOccurrences(of: "\"definition_score\":82", with: "\"definition_score\":140")
            .replacingOccurrences(of: "\"sentence_score\":70", with: "\"sentence_score\":-30")
        let transport = StubTransport(json: completion(payload))
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        let result = try await client.grade(
            word: "abate", referenceDefinition: "d", partOfSpeech: "verb",
            learnerDefinition: "x", learnerSentence: "y", model: "m"
        )
        #expect(result.definitionScore == 100)
        #expect(result.sentenceScore == 0)
    }

    @Test func combinedScoreAveragesDefinitionAndSentence() {
        let result = GradeResult(
            definitionScore: 80, definitionFeedback: "", sentenceScore: 60,
            sentenceFeedback: "", correctedSentence: "", rating: .good, missedNuances: []
        )
        #expect(result.combinedScore == 70)
    }

    @Test func reportsHttpFailuresInsteadOfGuessingAGrade() async throws {
        let transport = StubTransport(status: 429, json: #"{"error":{"message":"rate limited"}}"#)
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        await #expect(throws: OpenRouterError.self) {
            _ = try await client.grade(
                word: "a", referenceDefinition: "d", partOfSpeech: "verb",
                learnerDefinition: "x", learnerSentence: "y", model: "m"
            )
        }
    }

    @Test func reportsUnparseableContentInsteadOfGuessingAGrade() async throws {
        // A provider that ignored the schema and answered in prose.
        let transport = StubTransport(json: completion("Sure! Here's my assessment: pretty good."))
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        await #expect(throws: OpenRouterError.self) {
            _ = try await client.grade(
                word: "a", referenceDefinition: "d", partOfSpeech: "verb",
                learnerDefinition: "x", learnerSentence: "y", model: "m"
            )
        }
    }

    @Test func reportsAnEmptyChoicesArray() async throws {
        let transport = StubTransport(json: #"{"id":"gen-1","choices":[]}"#)
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        await #expect(throws: OpenRouterError.self) {
            _ = try await client.grade(
                word: "a", referenceDefinition: "d", partOfSpeech: "verb",
                learnerDefinition: "x", learnerSentence: "y", model: "m"
            )
        }
    }

    @Test func refusesToGradeWithoutAnApiKey() async throws {
        let transport = StubTransport(json: completion(validGradePayload))
        let client = OpenRouterClient(apiKey: "  ", transport: transport)
        await #expect(throws: OpenRouterError.missingAPIKey) {
            _ = try await client.grade(
                word: "a", referenceDefinition: "d", partOfSpeech: "verb",
                learnerDefinition: "x", learnerSentence: "y", model: "m"
            )
        }
    }
}


@Suite struct OpenRouterCostTests {

    @Test func asksTheApiToReportWhatTheCallCost() async throws {
        let transport = StubTransport(json: completion(validGradePayload, usage: usageBlock))
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        _ = try await client.gradeWithCost(
            word: "abate", referenceDefinition: "d", partOfSpeech: "verb",
            learnerDefinition: "x", learnerSentence: "y", model: "m"
        )
        let body = try parseBody(try await transport.requestBodyData())
        // Without this OpenRouter omits cost from the response entirely.
        let usage = try #require(body["usage"] as? [String: Any])
        #expect(usage["include"] as? Bool == true)
    }

    @Test func reportsTokensAndDollarsSpent() async throws {
        let transport = StubTransport(json: completion(validGradePayload, usage: usageBlock))
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        let (result, cost) = try await client.gradeWithCost(
            word: "abate", referenceDefinition: "d", partOfSpeech: "verb",
            learnerDefinition: "x", learnerSentence: "y", model: "m"
        )
        #expect(result.definitionScore == 82)
        let spent = try #require(cost)
        #expect(spent.promptTokens == 412)
        #expect(spent.completionTokens == 96)
        #expect(spent.usd == 0.00031)
    }

    @Test func aResponseWithoutUsageStillGrades() async throws {
        // Not every provider reports usage; that must not fail the grade.
        let transport = StubTransport(json: completion(validGradePayload))
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        let (result, cost) = try await client.gradeWithCost(
            word: "abate", referenceDefinition: "d", partOfSpeech: "verb",
            learnerDefinition: "x", learnerSentence: "y", model: "m"
        )
        #expect(result.definitionScore == 82)
        #expect(cost == nil)
    }

    @Test func usageWithoutACostFigureStillReportsTokens() async throws {
        let noCost = #"{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}"#
        let transport = StubTransport(json: completion(validGradePayload, usage: noCost))
        let client = OpenRouterClient(apiKey: "sk-test", transport: transport)
        let (_, cost) = try await client.gradeWithCost(
            word: "a", referenceDefinition: "d", partOfSpeech: "verb",
            learnerDefinition: "x", learnerSentence: "y", model: "m"
        )
        let spent = try #require(cost)
        #expect(spent.promptTokens == 10)
        #expect(spent.usd == nil)
    }

    @Test func formatsTinyAmountsWithoutRoundingThemToZero() {
        // A grade costs a fraction of a cent; "$0.00" would be useless.
        #expect(CallCost(promptTokens: 1, completionTokens: 1, usd: 0.00031).displayCost == "0.031¢")
        #expect(CallCost(promptTokens: 1, completionTokens: 1, usd: 0.0245).displayCost == "2.45¢")
        #expect(CallCost(promptTokens: 1, completionTokens: 1, usd: 1.5).displayCost == "$1.50")
        #expect(CallCost(promptTokens: 1, completionTokens: 1, usd: 0).displayCost == "free")
        #expect(CallCost(promptTokens: 1, completionTokens: 1, usd: nil).displayCost == "—")
    }
}
