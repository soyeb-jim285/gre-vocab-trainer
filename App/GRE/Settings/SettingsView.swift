import GRECore
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var keyDraft = ""
    @State private var showingKey = false

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
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .tint(Theme.accent)
    }

    @Environment(\.catalog) private var catalog
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
