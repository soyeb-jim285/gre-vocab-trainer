import GRECore
import SwiftUI

/// Three questions, asked once.
///
/// Without them the app has no idea what a day should hold, so it either runs
/// forever or invents a number. The test date and the daily limit are what turn
/// 2,898 words into today's work.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.catalog) private var catalog

    @State private var step = 0
    @State private var hasDeadline = true
    @State private var testDate = Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now
    @State private var newWordsPerDay = 15
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ProgressView(value: Double(step + 1), total: 3)
                .tint(Theme.accent)
                .accessibilityLabel("Setup progress")

            Group {
                switch step {
                case 0: goalStep
                case 1: paceStep
                default: keyStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }.buttonStyle(.glass)
                }
                Spacer()
                Button(step == 2 ? "Start studying" : "Next") { advance() }
                    .buttonStyle(.glassProminent)
            }
            .font(.headline)
        }
        .padding(Theme.gutter)
        .screenBackground()
    }

    // MARK: Steps

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Title("When is the test?", subtitle: "It sets how many new words a day you need. You can change it later, or study without one.")
            Toggle("I have a test date", isOn: $hasDeadline)
                .tint(Theme.accent)
            if hasDeadline {
                DatePicker("Test date", selection: $testDate, in: Date.now..., displayedComponents: .date)
                    .tint(Theme.accent)
            }
        }
    }

    private var paceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Title("How many new words a day?",
                  subtitle: "A ceiling, not a target. Meeting forty new words in one sitting is how people quit on day three.")
            Stepper("\(newWordsPerDay) a day", value: $newWordsPerDay, in: 0...60)
                .tint(Theme.accent)
                .monospacedDigit()
            Text(paceAdvice)
                .font(.footnote)
                .foregroundStyle(onTrack ? Theme.secondaryText : Theme.caution)
        }
    }

    private var keyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Title("Grade your writing?",
                  subtitle: "Five of the six ways this app asks a question work offline and free. The sixth has you write a definition and a sentence, and needs an OpenRouter key to grade them. You can add one later.")
            SecureField("sk-or-…", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(Theme.raised, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    // MARK: Behaviour

    private var remaining: Int { catalog.words.count }

    private var required: Int? {
        guard hasDeadline else { return nil }
        return Pacing.newWordsPerDay(remaining: remaining, testDate: testDate)
    }

    private var onTrack: Bool {
        guard let required else { return true }
        return required <= newWordsPerDay
    }

    private var paceAdvice: String {
        if let required {
            return onTrack
                ? "Your date needs \(required) a day, so this is comfortable."
                : "Your date needs \(required) a day to cover the whole list. At \(newWordsPerDay) you will not finish it — which is fine if you would rather know the common words well than meet all of them."
        }
        guard newWordsPerDay > 0 else { return "At none a day the list will never finish." }
        let done = Pacing.completionDate(remaining: remaining, newWordsPerDay: newWordsPerDay)
        return done.map { "You will have met every word by \($0.formatted(date: .abbreviated, time: .omitted))." }
            ?? ""
    }

    private func advance() {
        switch step {
        case 0:
            settings.testDate = hasDeadline ? testDate : nil
            // Start them where their own deadline points rather than at a
            // number the app made up.
            if let required { newWordsPerDay = min(max(required, 5), 40) }
            step = 1
        case 1:
            settings.newWordsPerDayCap = newWordsPerDay
            step = 2
        default:
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { settings.setAPIKey(trimmed) }
            settings.hasOnboarded = true
        }
    }
}

private struct Title: View {
    let text: String
    let subtitle: String

    init(_ text: String, subtitle: String) {
        self.text = text
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(Theme.headword(.title))
                .foregroundStyle(Theme.primaryText)
            Text(subtitle)
                .font(Theme.body)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
