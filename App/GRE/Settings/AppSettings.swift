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
        static let testDate = "testDate"
        static let dailyMinutes = "dailyMinutes"
        static let newWordsPerDayCap = "newWordsPerDayCap"
        static let dayStartHour = "dayStartHour"
        static let confidenceEnabled = "confidenceEnabled"
        static let confidenceScale = "confidenceScale"
        static let dailyBudgetUSD = "dailyBudgetUSD"
        static let lifetimeBudgetUSD = "lifetimeBudgetUSD"
        static let hasOnboarded = "hasOnboarded"
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

    // MARK: The goal

    /// Nil for anyone studying without a deadline.
    var testDate: Date? { didSet { defaults.set(testDate, forKey: Key.testDate) } }
    var dailyMinutes: Int { didSet { defaults.set(dailyMinutes, forKey: Key.dailyMinutes) } }
    var newWordsPerDayCap: Int { didSet { defaults.set(newWordsPerDayCap, forKey: Key.newWordsPerDayCap) } }
    /// When a study day rolls over, so finishing at half past midnight completes
    /// the day the learner thinks they are in.
    var dayStartHour: Int { didSet { defaults.set(dayStartHour, forKey: Key.dayStartHour) } }
    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) } }

    // MARK: Advanced

    var confidenceEnabled: Bool { didSet { defaults.set(confidenceEnabled, forKey: Key.confidenceEnabled) } }
    var confidenceScale: Double { didSet { defaults.set(confidenceScale, forKey: Key.confidenceScale) } }
    /// Negative means no limit. A separate "unlimited" flag would be a second
    /// thing to keep in step with the number it guards.
    var dailyBudgetUSD: Double { didSet { defaults.set(dailyBudgetUSD, forKey: Key.dailyBudgetUSD) } }
    var lifetimeBudgetUSD: Double { didSet { defaults.set(lifetimeBudgetUSD, forKey: Key.lifetimeBudgetUSD) } }

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
        testDate = defaults.object(forKey: Key.testDate) as? Date
        dailyMinutes = defaults.object(forKey: Key.dailyMinutes) as? Int ?? 20
        newWordsPerDayCap = defaults.object(forKey: Key.newWordsPerDayCap) as? Int ?? 15
        dayStartHour = defaults.object(forKey: Key.dayStartHour) as? Int ?? 4
        hasOnboarded = defaults.bool(forKey: Key.hasOnboarded)
        confidenceEnabled = defaults.bool(forKey: Key.confidenceEnabled)
        confidenceScale = defaults.object(forKey: Key.confidenceScale) as? Double ?? 1
        dailyBudgetUSD = defaults.object(forKey: Key.dailyBudgetUSD) as? Double ?? 0.50
        lifetimeBudgetUSD = defaults.object(forKey: Key.lifetimeBudgetUSD) as? Double ?? -1
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
        testDate = nil
        dailyMinutes = 20
        newWordsPerDayCap = 15
        dayStartHour = 4
        confidenceEnabled = false
        confidenceScale = 1
        dailyBudgetUSD = 0.50
        lifetimeBudgetUSD = -1
        // Left alone on purpose, like the Keychain: someone wiping their
        // progress is starting the word list again, not the app.
        // hasOnboarded stays as it is.
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

    var profile: LearnerProfile {
        LearnerProfile(
            testDate: testDate,
            dailyMinutes: dailyMinutes,
            newWordsPerDayCap: newWordsPerDayCap,
            dayStartHour: dayStartHour,
            desiredRetention: desiredRetention,
            strictness: strictness,
            confidence: ConfidenceSettings(isEnabled: confidenceEnabled, scale: confidenceScale),
            budget: AIBudget(
                dailyUSD: dailyBudgetUSD < 0 ? nil : dailyBudgetUSD,
                lifetimeUSD: lifetimeBudgetUSD < 0 ? nil : lifetimeBudgetUSD
            )
        )
    }

    /// The start of the study day the learner is currently in.
    func dayStart(at date: Date = .now) -> Date {
        Pacing.dayStart(containing: date, hour: dayStartHour)
    }

    var scheduler: FSRS { FSRS(desiredRetention: desiredRetention) }

    func client() -> OpenRouterClient {
        OpenRouterClient(apiKey: KeychainStore.apiKey ?? "")
    }
}
