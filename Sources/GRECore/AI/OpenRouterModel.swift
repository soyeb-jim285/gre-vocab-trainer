import Foundation

/// One entry from `GET /api/v1/models`.
public struct OpenRouterModel: Codable, Identifiable, Hashable, Sendable {

    /// Prices arrive as decimal *strings* ("0.00000045"), so they decode by hand.
    public struct Pricing: Codable, Hashable, Sendable {
        public let promptPerToken: Double
        public let completionPerToken: Double

        private enum CodingKeys: String, CodingKey { case prompt, completion }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            promptPerToken = Double(try c.decodeIfPresent(String.self, forKey: .prompt) ?? "0") ?? 0
            completionPerToken = Double(try c.decodeIfPresent(String.self, forKey: .completion) ?? "0") ?? 0
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(String(promptPerToken), forKey: .prompt)
            try c.encode(String(completionPerToken), forKey: .completion)
        }
    }

    public let id: String
    public let name: String
    public let contextLength: Int
    public let pricing: Pricing
    public let supportedParameters: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, pricing
        case contextLength = "context_length"
        case supportedParameters = "supported_parameters"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        contextLength = try c.decodeIfPresent(Int.self, forKey: .contextLength) ?? 0
        pricing = try c.decode(Pricing.self, forKey: .pricing)
        supportedParameters = try c.decodeIfPresent([String].self, forKey: .supportedParameters) ?? []
    }

    /// Only these models can be offered for grading -- the rest would ignore the
    /// response schema and hand back prose.
    public var supportsStructuredOutputs: Bool {
        supportedParameters.contains("structured_outputs")
    }
}
