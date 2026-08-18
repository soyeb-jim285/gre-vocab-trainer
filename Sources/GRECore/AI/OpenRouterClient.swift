import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct WordDeepDive: Decodable, Equatable, Sendable {
    public let etymology: String
    public let mnemonic: String
    public let nuance: String
    public let confusableWith: [String]

    private enum CodingKeys: String, CodingKey {
        case etymology, mnemonic, nuance
        case confusableWith = "confusable_with"
    }
}

public struct CoachSummary: Decodable, Equatable, Sendable {
    public let summary: String
    public let focusAreas: [String]
    public let encouragement: String

    private enum CodingKeys: String, CodingKey {
        case summary, encouragement
        case focusAreas = "focus_areas"
    }
}

/// Talks to OpenRouter's OpenAI-compatible chat completions endpoint using
/// strict structured outputs.
public struct OpenRouterClient: Sendable {

    private static let base = URL(string: "https://openrouter.ai/api/v1")!

    private let apiKey: String
    private let transport: HTTPTransport

    public init(apiKey: String, transport: HTTPTransport = URLSession.shared) {
        self.apiKey = apiKey
        self.transport = transport
    }

    // MARK: - Models

    /// Models that can honour a strict schema. Anything else would return prose.
    public func availableModels() async throws -> [OpenRouterModel] {
        var request = URLRequest(url: Self.base.appendingPathComponent("models"))
        request.httpMethod = "GET"
        // Deliberately unauthenticated: the catalogue is public, and the model
        // picker has to work before the user has pasted a key.
        let (data, status) = try await send(request)
        try Self.checkStatus(status, data)
        return try Self.decodeModels(from: data).filter(\.supportsStructuredOutputs)
    }

    static func decodeModels(from data: Data) throws -> [OpenRouterModel] {
        struct Envelope: Decodable { let data: [OpenRouterModel] }
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }

    // MARK: - Calls

    public func grade(
        word: String, referenceDefinition: String, partOfSpeech: String,
        learnerDefinition: String, learnerSentence: String, model: String
    ) async throws -> GradeResult {
        try await complete(
            messages: Prompts.grade(
                word: word, referenceDefinition: referenceDefinition,
                partOfSpeech: partOfSpeech, learnerDefinition: learnerDefinition,
                learnerSentence: learnerSentence
            ),
            schemaName: "gre_grade", schema: Schemas.grade, model: model
        )
    }

    public func deepDive(word: String, definition: String, model: String) async throws -> WordDeepDive {
        try await complete(
            messages: Prompts.deepDive(word: word, definition: definition),
            schemaName: "word_deep_dive", schema: Schemas.deepDive, model: model
        )
    }

    public func weeklyCoach(
        recentMisses: [String], recentWins: [String], model: String
    ) async throws -> CoachSummary {
        try await complete(
            messages: Prompts.coach(recentMisses: recentMisses, recentWins: recentWins),
            schemaName: "weekly_coach", schema: Schemas.coach, model: model
        )
    }

    // MARK: - Plumbing

    private func complete<T: Decodable>(
        messages: [[String: String]], schemaName: String, schema: [String: Any], model: String
    ) async throws -> T {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.missingAPIKey
        }

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            // Without require_parameters a provider may quietly drop response_format
            // and answer in prose instead.
            "provider": ["require_parameters": true],
            "response_format": Schemas.responseFormat(name: schemaName, schema: schema),
        ]

        var request = URLRequest(url: Self.base.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, status) = try await send(request)
        try Self.checkStatus(status, data)
        return try Self.decodeContent(from: data)
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            return try await transport.send(request)
        } catch let error as OpenRouterError {
            throw error
        } catch {
            throw OpenRouterError.transport(error.localizedDescription)
        }
    }

    private static func checkStatus(_ status: Int, _ data: Data) throws {
        guard !(200...299).contains(status) else { return }
        struct Failure: Decodable { struct Body: Decodable { let message: String }; let error: Body }
        let message = (try? JSONDecoder().decode(Failure.self, from: data).error.message)
            ?? String(decoding: data.prefix(200), as: UTF8.self)
        throw OpenRouterError.http(status: status, message: message)
    }

    /// The structured payload arrives as a JSON *string* inside the message, so
    /// it needs a second decode pass.
    private struct CompletionEnvelope: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private static func decodeContent<T: Decodable>(from data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(CompletionEnvelope.self, from: data)
        guard let content = envelope.choices.first?.message.content, !content.isEmpty else {
            throw OpenRouterError.noChoices
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(content.utf8))
        } catch {
            throw OpenRouterError.unparseableContent(String(content.prefix(200)))
        }
    }
}
