import AVFoundation
import GRECore
import SwiftUI

/// Lists the voices actually installed for an accent, best first.
///
/// The premium and enhanced voices are the whole quality story here -- they are
/// neural and sound close to a dictionary recording, while the compact voice
/// that ships by default does not. iOS will not let an app download them, so
/// when only compact is present the screen says where to get the others.
struct VoicePickerView: View {
    let accent: SpeechAccent
    @Binding var selection: String?

    @Environment(\.catalog) private var catalog

    private var voices: [AVSpeechSynthesisVoice] { VoiceCatalog.voices(for: accent) }

    var body: some View {
        List {
            if VoiceCatalog.onlyCompactAvailable(for: accent) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Only the compact voice is installed", systemImage: "waveform")
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                        Text("""
                        Settings → Accessibility → Spoken Content → Voices → English \
                        lists Enhanced and Premium voices. They're a few hundred megabytes \
                        each and a large step up — much closer to a dictionary recording.
                        """)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button {
                    selection = nil
                } label: {
                    row(title: "Best available",
                        subtitle: VoiceCatalog.best(for: accent).map {
                            "\($0.name) · \($0.quality.label)"
                        } ?? "No voice installed",
                        selected: selection == nil)
                }
            } footer: {
                Text("Follows the highest-quality voice installed, so a new download is picked up automatically.")
            }

            Section("Installed for \(accent.label) English") {
                ForEach(voices, id: \.identifier) { voice in
                    Button {
                        selection = voice.identifier
                        Speaker.shared.sample(sampleText, voice: voice)
                    } label: {
                        row(title: voice.name,
                            subtitle: voice.quality.label,
                            selected: selection == voice.identifier,
                            highlight: voice.quality.rank > 1)
                    }
                }
                if voices.isEmpty {
                    Text("No \(accent.label) voice is installed on this device.")
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .navigationTitle("\(accent.label) voice")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .screenBackground()
    }

    /// A word worth hearing: three syllables and a schwa, so the voices differ audibly.
    private var sampleText: String { catalog["obsequious"]?.word ?? "obsequious" }

    private func row(
        title: String, subtitle: String, selected: Bool, highlight: Bool = false
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(Theme.primaryText)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(highlight ? Theme.accent : Theme.tertiaryText)
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
        }
    }
}
