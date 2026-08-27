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
        static let strictness = "gradingStrictness"
        static let desiredRetention = "desiredRetention"
        static let currentDeckID = "currentDeckID"
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
    var strictness: GradingStrictness { didSet { defaults.set(strictness.rawValue, forKey: Key.strictness) } }
    var desiredRetention: Double { didSet { defaults.set(desiredRetention, forKey: Key.desiredRetention) } }
    /// Deck new words are drawn from. Nil means start at the first deck.
    var currentDeckID: String? {
        didSet { defaults.set(currentDeckID, forKey: Key.currentDeckID) }
    }

    /// Mirrors the Keychain so views can react; the Keychain stays the source of truth.
    var hasAPIKey: Bool

    /// Bumped by ``resetToDefaults()``. A session in progress holds cards in
    /// memory, so it has to be told to rebuild -- otherwise it would go on
    /// grading words whose records were just deleted. Not persisted: it only
    /// has to outlive a screen, not a launch.
    private(set) var resetToken = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        gradingModel = defaults.string(forKey: Key.gradingModel) ?? Self.fallbackModel
        deepDiveModel = defaults.string(forKey: Key.deepDiveModel) ?? Self.fallbackModel
        coachModel = defaults.string(forKey: Key.coachModel) ?? Self.fallbackModel
        accent = SpeechAccent(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .american
        voiceIdentifier = defaults.string(forKey: Key.voiceIdentifier)
        writingModeAfterReviews = defaults.object(forKey: Key.writingAfter) as? Int ?? 3
        forcedMode = StudyMode(rawValue: defaults.string(forKey: Key.forcedMode) ?? "")
        strictness = GradingStrictness(rawValue: defaults.string(forKey: Key.strictness) ?? "") ?? .standard
        desiredRetention = defaults.object(forKey: Key.desiredRetention) as? Double ?? 0.9
        currentDeckID = defaults.string(forKey: Key.currentDeckID)
        hasAPIKey = KeychainStore.hasKey
    }

    /// A cheap, widely-available model that does structured outputs.
    private static let fallbackModel = "google/gemini-3.7-flash"

    /// Put every preference back where a fresh install would have it.
    ///
    /// Deliberately leaves the Keychain alone: wiping progress should not also
    /// lock the learner out of the graded mode and make them find their key again.
    /// Assigning through the properties means each `didSet` writes to
    /// UserDefaults, so nothing stale survives.
    func resetToDefaults() {
        resetToken += 1
        gradingModel = Self.fallbackModel
        deepDiveModel = Self.fallbackModel
        coachModel = Self.fallbackModel
        accent = .american
        voiceIdentifier = nil
        writingModeAfterReviews = 3
        forcedMode = nil
        strictness = .standard
        desiredRetention = 0.9
        currentDeckID = nil
    }

    func setAPIKey(_ key: String?) {
        KeychainStore.apiKey = key
        hasAPIKey = KeychainStore.hasKey
        // Otherwise the picker stays pinned to a mode that can no longer run.
        if !hasAPIKey, forcedMode?.needsAI == true { forcedMode = nil }
    }

    var sessionSettings: SessionSettings {
        SessionSettings(
            strictness: strictness,
            aiEnabled: hasAPIKey,
            writingModeAfterReviews: writingModeAfterReviews,
            forcedMode: forcedMode,
            currentDeckID: currentDeckID
        )
    }

    var scheduler: FSRS { FSRS(desiredRetention: desiredRetention) }

    func client() -> OpenRouterClient {
        OpenRouterClient(apiKey: KeychainStore.apiKey ?? "")
    }
}
