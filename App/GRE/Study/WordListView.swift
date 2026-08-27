import GRECore
import SwiftData
import SwiftUI

/// A small band marker. The star elsewhere means "on many prep lists", which is
/// a different thing from difficulty and worth not conflating.
struct DifficultyBadge: View {
    let difficulty: WordDifficulty

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: .capsule)
            .foregroundStyle(tint)
    }

    private var label: String {
        switch difficulty {
        case .familiar: "easy"
        case .moderate: "med"
        case .hard: "hard"
        case .rare: "rare"
        }
    }

    private var tint: Color {
        switch difficulty {
        case .familiar: Theme.positive
        case .moderate: Theme.accent
        case .hard: Color(red: 0.90, green: 0.68, blue: 0.35)
        case .rare: Theme.negative
        }
    }
}

struct WordDetailView: View {
    let word: Word

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var dive: WordDeepDive?
    @State private var error: String?
    @State private var loading = false
    @State private var practising = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                practiceButton
                ForEach(Array(word.senses.enumerated()), id: \.offset) { _, sense in
                    SenseBlock(sense: sense)
                }
                deepDiveSection
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle(word.word)
        .navigationBarTitleDisplayMode(.inline)
        .task { dive = cached() }
        .sheet(isPresented: $practising) { WritingPracticeView(word: word) }
    }

    /// Direct route to the mode the app is built around, without waiting for the
    /// scheduler to walk this word up the ladder.
    @ViewBuilder
    private var practiceButton: some View {
        if settings.hasAPIKey {
            Button {
                practising = true
            } label: {
                Label("Practise writing this one", systemImage: "square.and.pencil")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(word.word)
                    .font(Theme.headword())
                    .foregroundStyle(Theme.primaryText)
                Button {
                    Speaker.shared.say(word, accent: settings.accent, voiceIdentifier: settings.voiceIdentifier)
                } label: {
                    Image(systemName: "speaker.wave.2").foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            if !word.ipa.isEmpty {
                Text(word.ipa).font(Theme.mono).foregroundStyle(Theme.tertiaryText)
            }
            Text(word.sourceLists.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(Theme.tertiaryText)
        }
    }

    @ViewBuilder
    private var deepDiveSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Deep dive")
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)

            if let dive {
                Labelled("Etymology", dive.etymology)
                Labelled("Memory hook", dive.mnemonic)
                Labelled("Nuance", dive.nuance)
                if !dive.confusableWith.isEmpty {
                    Labelled("Often confused with", dive.confusableWith.joined(separator: ", "))
                }
            } else if let error {
                Text(error).font(Theme.body).foregroundStyle(Theme.negative)
            } else if !settings.hasAPIKey {
                Text("Add an OpenRouter key in Settings to unlock etymology and memory hooks.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondaryText)
            }

            if settings.hasAPIKey && dive == nil {
                Button(loading ? "Looking it up…" : "Look it up", action: fetch)
                    .buttonStyle(.glassProminent)
                    .disabled(loading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func cached() -> WordDeepDive? {
        let id = word.id
        var descriptor = FetchDescriptor<DeepDiveRecord>(predicate: #Predicate { $0.wordID == id })
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return nil }
        return WordDeepDive(
            etymology: record.etymology, mnemonic: record.mnemonic,
            nuance: record.nuance, confusableWith: record.confusableWith
        )
    }

    private func fetch() {
        guard !loading else { return }
        loading = true
        error = nil
        Task {
            defer { loading = false }
            do {
                let result = try await settings.client().deepDive(
                    word: word.word, definition: word.primarySense.definition,
                    model: settings.deepDiveModel
                )
                // Cached so a word is only ever paid for once.
                context.insert(DeepDiveRecord(wordID: word.id, dive: result, fetchedAt: .now))
                try? context.save()
                dive = result
            } catch {
                self.error = (error as? OpenRouterError)?.description ?? error.localizedDescription
            }
        }
    }
}

private struct SenseBlock: View {
    let sense: Sense

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sense.pos.rawValue)
                .font(Theme.label)
                .foregroundStyle(Theme.accent)
                .textCase(.uppercase)
            Text(sense.definition)
                .font(Theme.definition)
                .foregroundStyle(Theme.primaryText)
            ForEach(sense.examples, id: \.self) { example in
                Text("“\(example)”")
                    .font(Theme.body.italic())
                    .foregroundStyle(Theme.secondaryText)
            }
            if !sense.synonyms.isEmpty {
                Text(sense.synonyms.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct Labelled: View {
    let title: String
    let text: String

    init(_ title: String, _ text: String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.label).foregroundStyle(Theme.tertiaryText).textCase(.uppercase)
            Text(text).font(Theme.body).foregroundStyle(Theme.primaryText)
        }
    }
}
