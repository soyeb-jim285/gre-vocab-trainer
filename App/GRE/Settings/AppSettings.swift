import Foundation
import GRECore
import Observation
import SwiftUI

/// User-facing settings. The API key lives in the Keychain; everything else is
/// small and non-secret, so UserDefaults is the right amount of machinery.
@Observable
final class AppSettings {

    private enum Key {
        static let gradingModel = "gradingModel"
        static let deepDiveModel = "deepDiveModel"
        static let coachModel = "coachModel"
        static let accent = "speechAccent"
        static let voiceIdentifier = "voiceIdentifier"
        static let writingAfter = "writingModeAfterReviews"
        static let forcedMode = "forcedMode"
        static let newWordOrder = "newWordOrder"
        static let dailyNewWordLimit = "dailyNewWordLimit"
        static let sessionLength = "sessionLength"
        static let strictness = "gradingStrictness"
        static let desiredRetention = "desiredRetention"
    }

    private let defaults: UserDefaults

    var gradingModel: String { didSet { defaults.set(gradingModel, forKey: Key.gradingModel) } }
    var deepDiveModel: String { didSet { defaults.set(deepDiveModel, forKey: Key.deepDiveModel) } }
    var coachModel: String { didSet { defaults.set(coachModel, forKey: Key.coachModel) } }
    var accent: SpeechAccent {
        didSet {
            defaults.set(accent.rawValue, forKey: Key.accent)
            // A voice pinned for the old accent would keep speaking in it.
            if oldValue != accent { voiceIdentifier = nil }
        }
    }
    /// Pins a specific installed voice; nil follows the best one available.
    var voiceIdentifier: String? {
        didSet { defaults.set(voiceIdentifier, forKey: Key.voiceIdentifier) }
    }
    var writingModeAfterReviews: Int {
        didSet { defaults.set(writingModeAfterReviews, forKey: Key.writingAfter) }
    }
    /// Drills one mode for the whole session; nil follows the automatic ladder.
    var forcedMode: StudyMode? {
        didSet { defaults.set(forcedMode?.rawValue, forKey: Key.forcedMode) }
    }
    var newWordOrder: NewWordOrder {
        didSet { defaults.set(newWordOrder.rawValue, forKey: Key.newWordOrder) }
    }
    var dailyNewWordLimit: Int { didSet { defaults.set(dailyNewWordLimit, forKey: Key.dailyNewWordLimit) } }
    var sessionLength: Int { didSet { defaults.set(sessionLength, forKey: Key.sessionLength) } }
    var strictness: GradingStrictness { didSet { defaults.set(strictness.rawValue, forKey: Key.strictness) } }
    var desiredRetention: Double { didSet { defaults.set(desiredRetention, forKey: Key.desiredRetention) } }

    /// Mirrors the Keychain so views can react; the Keychain stays the source of truth.
    var hasAPIKey: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A cheap, widely-available model that does structured outputs.
        let fallbackModel = "google/gemini-3.7-flash"
        gradingModel = defaults.string(forKey: Key.gradingModel) ?? fallbackModel
        deepDiveModel = defaults.string(forKey: Key.deepDiveModel) ?? fallbackModel
        coachModel = defaults.string(forKey: Key.coachModel) ?? fallbackModel
        accent = SpeechAccent(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .american
        voiceIdentifier = defaults.string(forKey: Key.voiceIdentifier)
        writingModeAfterReviews = defaults.object(forKey: Key.writingAfter) as? Int ?? 3
        forcedMode = StudyMode(rawValue: defaults.string(forKey: Key.forcedMode) ?? "")
        newWordOrder = NewWordOrder(rawValue: defaults.string(forKey: Key.newWordOrder) ?? "") ?? .adaptive
        dailyNewWordLimit = defaults.object(forKey: Key.dailyNewWordLimit) as? Int ?? 10
        sessionLength = defaults.object(forKey: Key.sessionLength) as? Int ?? 20
        strictness = GradingStrictness(rawValue: defaults.string(forKey: Key.strictness) ?? "") ?? .standard
        desiredRetention = defaults.object(forKey: Key.desiredRetention) as? Double ?? 0.9
        hasAPIKey = KeychainStore.hasKey
    }

    func setAPIKey(_ key: String?) {
        KeychainStore.apiKey = key
        hasAPIKey = KeychainStore.hasKey
        // Otherwise the picker stays pinned to a mode that can no longer run.
        if !hasAPIKey, forcedMode?.needsAI == true { forcedMode = nil }
    }

    var sessionSettings: SessionSettings {
        SessionSettings(
            dailyNewWordLimit: dailyNewWordLimit,
            sessionLength: sessionLength,
            strictness: strictness,
            aiEnabled: hasAPIKey,
            writingModeAfterReviews: writingModeAfterReviews,
            forcedMode: forcedMode,
            newWordOrder: newWordOrder
        )
    }

    var scheduler: FSRS { FSRS(desiredRetention: desiredRetention) }

    func client() -> OpenRouterClient {
        OpenRouterClient(apiKey: KeychainStore.apiKey ?? "")
    }
}
