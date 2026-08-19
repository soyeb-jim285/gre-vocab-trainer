import Foundation

/// What one model call actually cost.
///
/// OpenRouter only reports this when the request asks for it, and not every
/// provider fills in a dollar figure, so `usd` is optional while the token
/// counts generally are not.
public struct CallCost: Equatable, Sendable, Codable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let usd: Double?

    public init(promptTokens: Int, completionTokens: Int, usd: Double?) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.usd = usd
    }

    public var totalTokens: Int { promptTokens + completionTokens }

    /// A grade costs a fraction of a cent, so plain currency formatting would
    /// render every call as "$0.00". Small amounts are shown in cents instead.
    public var displayCost: String {
        guard let usd else { return "—" }
        if usd == 0 { return "free" }
        if usd < 0.01 { return String(format: "%.3f¢", usd * 100) }
        if usd < 1 { return String(format: "%.2f¢", usd * 100) }
        return String(format: "$%.2f", usd)
    }
}
