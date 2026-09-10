import GRECore
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.catalog) private var catalog
    @Environment(MasteryIndex.self) private var mastery

    @State private var keyDraft = ""
    @State private var showingKey = false
    @State private var confirmingReset = false
    @State private var resetError: String?
    @State private var spentToday: Double = 0
    @State private var spentEver: Double = 0

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                if settings.hasAPIKey {
                    LabeledContent("API key") {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.positive)
                            Text("Saved").foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Button("Remove key", role: .destructive) {
                        settings.setAPIKey(nil)
                        keyDraft = ""
                    }
                } else {
                    HStack {
                        if showingKey {
                            TextField("sk-or-v1-…", text: $keyDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("sk-or-v1-…", text: $keyDraft)
                        }
                        Button {
                            showingKey.toggle()
                        } label: {
                            Image(systemName: showingKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.secondaryText)
                    }
                    Button("Save key") { settings.setAPIKey(keyDraft) }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("OpenRouter")
            } footer: {
                Text(settings.hasAPIKey
                     ? "Stored in the Keychain, on this device only."
                     : "Without a key, spelling, recall and multiple choice all still work. Only the graded write-it-yourself mode needs one.")
            }

            Section("Models") {
                NavigationLink {
                    ModelPickerView(title: "Grading", selection: $settings.gradingModel)
                } label: {
                    LabeledContent("Grading", value: short(settings.gradingModel))
                }
                NavigationLink {
                    ModelPickerView(title: "Deep dive", selection: $settings.deepDiveModel)
                } label: {
                    LabeledContent("Deep dive", value: short(settings.deepDiveModel))
                }
                NavigationLink {
                    ModelPickerView(title: "Coach", selection: $settings.coachModel)
                } label: {
                    LabeledContent("Coach", value: short(settings.coachModel))
                }
            }

            Section {
                Picker("Accent", selection: $settings.accent) {
                    ForEach(SpeechAccent.allCases) { Text($0.label).tag($0) }
                }
                NavigationLink {
                    VoicePickerView(accent: settings.accent, selection: $settings.voiceIdentifier)
                } label: {
                    LabeledContent("Voice", value: currentVoiceLabel)
                }
                Button("Hear a sample") {
                    if let word = sampleWord {
                        Speaker.shared.say(word, accent: settings.accent, voiceIdentifier: settings.voiceIdentifier)
                    }
                }
            } header: {
                Text("Pronunciation")
            } footer: {
                if VoiceCatalog.onlyCompactAvailable(for: settings.accent) {
                    Text("Only the compact voice is installed. Enhanced and Premium voices sound far closer to a dictionary recording — see the Voice screen for where to get them.")
                }
            }

            Section {
                Toggle("Studying for a date", isOn: Binding(
                    get: { settings.testDate != nil },
                    set: { settings.testDate = $0 ? Date.now.addingTimeInterval(60 * 86_400) : nil }
                ))
                if let date = settings.testDate {
                    DatePicker(
                        "Test date",
                        selection: Binding(get: { date }, set: { settings.testDate = $0 }),
                        displayedComponents: .date
                    )
                }
                Stepper("New words a day: \(settings.newWordsPerDayCap)",
                        value: $settings.newWordsPerDayCap, in: 0...60)
                    .monospacedDigit()
                Picker("Day starts at", selection: $settings.dayStartHour) {
                    Text("Midnight").tag(0)
                    Text("2am").tag(2)
                    Text("4am").tag(4)
                    Text("6am").tag(6)
                }
            } header: {
                Text("Goal")
            } footer: {
                Text(goalFooter)
            }

            Section {
                Picker("Daily limit", selection: $settings.dailyBudgetUSD) {
                    Text("No limit").tag(-1.0)
                    Text("10¢").tag(0.10)
                    Text("25¢").tag(0.25)
                    Text("50¢").tag(0.50)
                    Text("$1").tag(1.0)
                    Text("$2").tag(2.0)
                }
                Picker("Total limit", selection: $settings.lifetimeBudgetUSD) {
                    Text("No limit").tag(-1.0)
                    Text("$5").tag(5.0)
                    Text("$10").tag(10.0)
                    Text("$25").tag(25.0)
                }
                LabeledContent("Spent today", value: money(spentToday))
                LabeledContent("Spent in total", value: money(spentEver))
            } header: {
                Text("Spending")
            } footer: {
                Text("Every model call counts against these: grading, deep dives and the coach. A call that would go over the limit is refused before it is made, not after.")
            }

            Section {
                Picker("Grading", selection: $settings.strictness) {
                    ForEach(GradingStrictness.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
                Picker("Start writing after", selection: $settings.writingModeAfterReviews) {
                    Text("Straight away").tag(0)
                    Text("1 review").tag(1)
                    Text("2 reviews").tag(2)
                    Text("3 reviews").tag(3)
                    Text("5 reviews").tag(5)
                }
                .disabled(!settings.hasAPIKey)
            } header: {
                Text("Study")
            } footer: {
                Text(settings.hasAPIKey
                     ? "Writing out a definition and a sentence is the real exercise. Set this to \u{201C}straight away\u{201D} to skip the warmups entirely."
                     : "Writing practice needs an OpenRouter key. Without one, words cycle through multiple choice, recall and spelling.")
            }

            Section {
                VStack(alignment: .leading) {
                    Text("Target retention: \(Int(settings.desiredRetention * 100))%")
                    Slider(value: $settings.desiredRetention, in: 0.75...0.97, step: 0.01)
                }
            } header: {
                Text("Scheduling")
            } footer: {
                Text("How much you want to remember at review time. Higher means more reviews for the same words.")
            }

            Section {
                Toggle("Read answer speed", isOn: $settings.confidenceEnabled)
                if settings.confidenceEnabled {
                    VStack(alignment: .leading) {
                        Text("Patience: \(String(format: "%.1f", settings.confidenceScale))×")
                        Slider(value: $settings.confidenceScale, in: 0.5...3, step: 0.1)
                    }
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Multiple choice, in-context and which-meaning score right or wrong and nothing in between, so the scheduler cannot tell an instant answer from a twenty-second one. Switch this on and a slow correct answer counts for less. It can only ever shorten an interval, never lengthen one. Raise the patience if it feels impatient.")
            }

            Section {
                Button("Reset everything", role: .destructive) { confirmingReset = true }
            } header: {
                Text("Reset")
            } footer: {
                Text(resetError ?? "Deletes every word you have studied, your review history, test scores and cached deep dives, and puts these settings back to their defaults. Your API key is kept. This cannot be undone.")
                    .foregroundStyle(resetError == nil ? Theme.secondaryText : Theme.negative)
            }
        }
        .confirmationDialog(
            "Reset everything?", isPresented: $confirmingReset, titleVisibility: .visible
        ) {
            Button("Delete my progress", role: .destructive) { reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every studied word, review, test score and setting goes. Your API key stays. There is no undo.")
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .tint(Theme.accent)
        .task { refreshSpend() }
    }

    private func refreshSpend() {
        spentToday = AILedger.spentToday(in: context, since: settings.dayStart())
        spentEver = AILedger.spentLifetime(in: context)
    }

    private func money(_ usd: Double) -> String {
        // Plain currency formatting shows every call as $0.00.
        usd > 0 && usd < 0.01
            ? String(format: "%.2f¢", usd * 100)
            : String(format: "$%.2f", usd)
    }

    private var goalFooter: String {
        let met = mastery.cards.values.filter { $0.reviewCount > 0 }.count
        let advice = Pacing.advise(
            remaining: max(0, catalog.words.count - met), profile: settings.profile
        )
        if let required = advice.required {
            return advice.isOnTrack
                ? "Your date needs \(required) new words a day, which your limit covers."
                : "Your date needs \(required) new words a day and your limit is \(advice.allowed). You will not cover the whole list by then."
        }
        guard let done = advice.completion else {
            return "At no new words a day the list will never finish."
        }
        return "At \(advice.allowed) a day you will have met every word by \(done.formatted(date: .abbreviated, time: .omitted))."
    }


    /// Progress first, then preferences: if the delete throws, the settings are
    /// left alone and the learner is told, rather than half-reset.
    private func reset() {
        do {
            try ReviewRecorder.eraseAllProgress(in: context, index: mastery)
            settings.resetToDefaults()
            refreshSpend()
            resetError = nil
        } catch {
            resetError = "Could not reset: \(error.localizedDescription)"
        }
    }

    private var sampleWord: Word? { catalog["abate"] ?? catalog.words.first }

    private var currentVoiceLabel: String {
        guard let voice = VoiceCatalog.voice(
            identifier: settings.voiceIdentifier, accent: settings.accent
        ) else { return "None installed" }
        return settings.voiceIdentifier == nil
            ? "Best · \(voice.quality.label)"
            : "\(voice.name) · \(voice.quality.label)"
    }

    private func short(_ id: String) -> String {
        id.split(separator: "/").last.map(String.init) ?? id
    }
}
