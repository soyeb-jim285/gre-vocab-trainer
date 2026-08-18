import Foundation

public enum OpenRouterError: Error, Equatable, CustomStringConvertible {
    case missingAPIKey
    case http(status: Int, message: String)
    case noChoices
    /// The provider answered, but not with the JSON the schema asked for.
    case unparseableContent(String)
    case transport(String)

    public var description: String {
        switch self {
        case .missingAPIKey:
            "No OpenRouter API key. Add one in Settings."
        case let .http(status, message):
            "OpenRouter returned \(status): \(message)"
        case .noChoices:
            "OpenRouter returned no choices."
        case let .unparseableContent(snippet):
            "Could not read the model's answer as JSON: \(snippet)"
        case let .transport(message):
            "Network error: \(message)"
        }
    }

    /// Whether retrying the same request could plausibly work.
    public var isRetryable: Bool {
        switch self {
        case .missingAPIKey: false
        case let .http(status, _): status == 429 || status >= 500
        case .noChoices, .unparseableContent, .transport: true
        }
    }
}
