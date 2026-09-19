import Foundation

public struct ConfidenceSettings: Codable, Equatable, Sendable {
    /// Off until there is real answer-time data to calibrate against. A loose
    /// threshold rates every quick answer Easy, which stretches intervals across
    /// the whole deck, and the learner would not find out for weeks.
    public var isEnabled: Bool
    /// Scales every mode's thresholds. Above 1 is more forgiving of a slow answer.
    public var scale: Double

    public init(isEnabled: Bool = false, scale: Double = 1) {
        self.isEnabled = isEnabled
        self.scale = scale
    }
}
