import GRECore
import SwiftData
import SwiftUI

/// Meeting a word, rather than being tested on one.
///
/// A brand-new word used to arrive as a graded multiple-choice question, which
/// is a coin flip: a guaranteed lapse, a wasted review, and a zero for something
/// the learner was never shown. Worse, it taught the scheduler a fact about the
/// app rather than about the learner. Nothing here is graded.
struct IntroduceCard: View {
    let word: Word
    let accent: SpeechAccent
    let voiceIdentifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("A new word")
                    .font(Theme.label)
                    .foregroundStyle(Theme.tertiaryText)
                    .textCase(.uppercase)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(word.word)
                        .font(Theme.headword())
                        .foregroundStyle(Theme.primaryText)
                    Button {
                        Speaker.shared.say(word, accent: accent, voiceIdentifier: voiceIdentifier)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hear \(word.word) pronounced")
                }

                if !word.ipa.isEmpty {
                    Text(word.ipa)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.tertiaryText)
                }
                Text(word.primaryPartOfSpeech.rawValue)
                    .font(Theme.label)
                    .foregroundStyle(Theme.tertiaryText)

                Text(word.teachingDefinition)
                    .font(Theme.definition)
                    .foregroundStyle(Theme.primaryText)
                    .padding(.top, 4)

                // A trap word's whole difficulty is that the meaning the learner
                // already has is the wrong one. Say so before they meet it in a
                // question and assume otherwise.
                if word.isTrap {
                    Text("You may know this word already. The exam uses it in a different sense — the one above.")
                        .font(.footnote)
                        .foregroundStyle(Theme.caution)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            if let sentence = word.gre?.sentences.first, !sentence.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("In use")
                        .font(Theme.label)
                        .foregroundStyle(Theme.tertiaryText)
                        .textCase(.uppercase)
                    Text(sentence)
                        .font(Theme.definition)
                        .foregroundStyle(Theme.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }

            MnemonicCard(word: word)

            if let synonyms = word.gre?.synonyms, !synonyms.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Close to")
                        .font(Theme.label)
                        .foregroundStyle(Theme.tertiaryText)
                        .textCase(.uppercase)
                    Text(synonyms.prefix(6).joined(separator: " · "))
                        .font(Theme.body)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
    }
}

/// A hook to hang the word on, fetched once and then owned.
///
/// The moment a word is first met is where a mnemonic is worth most and costs
/// least: one call per word, ever, cached, and the same row pays for the word's
/// deep dive later. Silent when there is no key, because five of the six ways
/// this app asks a question work without one and this is not the screen to
/// start nagging on.
private struct MnemonicCard: View {
    let word: Word

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var dive: WordDeepDive?
    @State private var loading = false

    var body: some View {
        // The task hangs off the Group, not off a branch. Setting `loading`
        // swaps the branch, and a task attached to a branch would be cancelled
        // by its own side effect before the call it started could return.
        Group {
            if let mnemonic = dive?.mnemonic, !mnemonic.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A way to remember it")
                        .font(Theme.label)
                        .foregroundStyle(Theme.tertiaryText)
                        .textCase(.uppercase)
                    Text(mnemonic)
                        .font(Theme.body)
                        .foregroundStyle(Theme.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            } else if loading {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        // Never blocks: the word, its definition and its sentence are already
        // readable above this.
        .task { await load() }
    }

    private func load() async {
        guard dive == nil, !loading else { return }
        if let cached = ReviewRecorder.deepDive(for: word.id, in: context) {
            dive = WordDeepDive(etymology: cached.etymology, mnemonic: cached.mnemonic,
                                nuance: cached.nuance, confusableWith: cached.confusableWith)
            return
        }
        guard settings.hasAPIKey else { return }
        loading = true
        defer { loading = false }
        // A failure is silent on purpose. The mnemonic is a bonus; a red banner
        // on the screen where someone meets a new word is not.
        let result = try? await AILedger.spend(
            .mnemonic, budget: settings.profile.budget,
            dayStart: settings.dayStart(), in: context
        ) {
            try await settings.client().deepDiveWithCost(
                word: word.word, definition: word.teachingDefinition,
                model: settings.deepDiveModel
            )
        }
        guard let fetched = result?.0 else { return }
        context.insert(DeepDiveRecord(wordID: word.id, dive: fetched, fetchedAt: .now))
        try? context.save()
        dive = fetched
    }
}
