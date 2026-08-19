import GRECore
import SwiftData
import SwiftUI

struct SessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(\.catalog) private var catalog

    @State private var model: SessionViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().tint(Theme.accent)
            }
        }
        .screenBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { modePicker }
        }
        .task {
            guard model == nil else { return }
            let created = SessionViewModel(context: context, catalog: catalog, settings: settings)
            created.start()
            model = created
        }
        // Changing what you're drilling has to rebuild the queue, so the change
        // takes effect on the very next card rather than the next session.
        .onChange(of: settings.forcedMode) { _, _ in model?.start() }
    }

    /// Auto follows the ladder: recognise, recall, spell, use. Picking a mode
    /// drills that one skill across every card in the session.
    private var modePicker: some View {
        @Bindable var settings = settings
        return Menu {
            Picker("Mode", selection: $settings.forcedMode) {
                Label("Auto", systemImage: "wand.and.stars").tag(StudyMode?.none)
                Divider()
                // Writing is left out entirely without a key rather than shown
                // selected while the planner quietly substitutes something else.
                ForEach(StudyMode.allCases.filter { settings.hasAPIKey || !$0.needsAI }, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.systemImage)
                        .tag(StudyMode?.some(mode))
                }
            }
        } label: {
            Label(
                settings.forcedMode?.label ?? "Auto",
                systemImage: settings.forcedMode?.systemImage ?? "wand.and.stars"
            )
            .font(Theme.label)
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func content(_ model: SessionViewModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView().tint(Theme.accent)

        case .finished:
            SessionCompleteView(answered: model.answeredCount) { model.start() }

        case let .failed(message):
            SessionErrorView(message: message) { model.retryAfterFailure() }

        case .grading:
            GradingView(word: model.current?.word.word ?? "")

        case .answering, .reviewing:
            if let item = model.current {
                VStack(spacing: 0) {
                    SessionProgressBar(progress: model.progress)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            PromptCard(item: item, accent: settings.accent, voiceIdentifier: settings.voiceIdentifier)
                            if case let .reviewing(feedback) = model.phase {
                                FeedbackCard(feedback: feedback, item: item)
                            } else {
                                answerArea(model, item)
                            }
                        }
                        .padding(Theme.gutter)
                    }
                }
                .safeAreaInset(edge: .bottom) { actionBar(model) }
            }
        }
    }

    @ViewBuilder
    private func answerArea(_ model: SessionViewModel, _ item: SessionItem) -> some View {
        @Bindable var model = model
        switch item.mode {
        case .multipleChoice:
            MultipleChoiceAnswer(options: model.multipleChoiceOptions(for: item)) {
                model.submitMultipleChoice($0)
            }
        case .spelling:
            SpellingAnswer(typed: $model.typedAnswer)
        case .reverseRecall:
            RecallAnswer(typed: $model.typedAnswer)
        case .defineAndUse:
            DefineAndUseAnswer(definition: $model.definitionDraft, sentence: $model.sentenceDraft)
        }
    }

    /// The one place Liquid Glass belongs: a floating control layer over content.
    @ViewBuilder
    private func actionBar(_ model: SessionViewModel) -> some View {
        if let item = model.current {
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    if isReviewing(model) {
                        Button("Next") { model.advance() }
                            .buttonStyle(.glassProminent)
                    } else {
                        // Available in every mode, including multiple choice --
                        // guessing at random teaches nothing and pollutes the
                        // schedule with answers that were never really known.
                        Button("I don't know") { model.admitNotKnowing() }
                            .buttonStyle(.glass)
                            .foregroundStyle(Theme.secondaryText)

                        if item.mode != .multipleChoice {
                            Button("Check") {
                                switch item.mode {
                                case .spelling: model.submitSpelling()
                                case .reverseRecall: model.submitRecall()
                                case .defineAndUse: Task { await model.submitDefineAndUse() }
                                case .multipleChoice: break
                                }
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(!canSubmit(model, item))
                        }
                    }
                }
                .font(.headline)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 12)
            }
        }
    }

    private func isReviewing(_ model: SessionViewModel) -> Bool {
        if case .reviewing = model.phase { return true }
        return false
    }

    private func canSubmit(_ model: SessionViewModel, _ item: SessionItem) -> Bool {
        switch item.mode {
        case .defineAndUse:
            !model.definitionDraft.trimmingCharacters(in: .whitespaces).isEmpty
                && !model.sentenceDraft.trimmingCharacters(in: .whitespaces).isEmpty
        case .multipleChoice:
            true
        default:
            !model.typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

// MARK: - Pieces

private struct SessionProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Theme.hairline
                Theme.accent.frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 2)
        .animation(.smooth, value: progress)
    }
}

/// The card under study. Solid, not glass -- glass is for the layer above.
private struct PromptCard: View {
    let item: SessionItem
    let accent: SpeechAccent
    let voiceIdentifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(promptLabel)
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)

            switch item.mode {
            case .spelling:
                Button {
                    Speaker.shared.say(item.word, accent: accent, voiceIdentifier: voiceIdentifier)
                } label: {
                    Label("Play the word", systemImage: "speaker.wave.3.fill")
                        .font(Theme.headword(28))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

            case .reverseRecall:
                Text(item.word.primarySense.definition)
                    .font(Theme.definition)
                    .foregroundStyle(Theme.primaryText)

            case .multipleChoice, .defineAndUse:
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.word.word)
                        .font(Theme.headword())
                        .foregroundStyle(Theme.primaryText)
                    Button {
                        Speaker.shared.say(item.word, accent: accent, voiceIdentifier: voiceIdentifier)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                if !item.word.ipa.isEmpty {
                    Text(item.word.ipa)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.tertiaryText)
                }
                Text(item.word.primarySense.pos.rawValue)
                    .font(Theme.label)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var promptLabel: String {
        switch item.mode {
        case .multipleChoice: "Which definition fits?"
        case .spelling: "Listen and spell"
        case .reverseRecall: "Which word means this?"
        case .defineAndUse: "Define it, then use it"
        }
    }
}

private struct GradingView: View {
    let word: String

    var body: some View {
        VStack(spacing: 18) {
            ProgressView().tint(Theme.accent)
            Text("Grading your answer for \(word)…")
                .font(Theme.body)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct SessionErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(Theme.negative)
            Text(message)
                .font(Theme.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            // Nothing was scheduled, so the answer is still there to resubmit.
            Text("Your answer was kept and nothing was recorded.")
                .font(.footnote)
                .foregroundStyle(Theme.tertiaryText)
            Button("Try again", action: retry)
                .buttonStyle(.glassProminent)
        }
        .padding(Theme.gutter * 1.5)
    }
}

private struct SessionCompleteView: View {
    let answered: Int
    let again: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(answered == 0 ? "Nothing due" : "Session complete")
                .font(Theme.headword(30))
                .foregroundStyle(Theme.primaryText)
            Text(answered == 0
                 ? "You're caught up. Come back when cards fall due."
                 : "\(answered) \(answered == 1 ? "word" : "words") reviewed.")
                .font(Theme.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Start another", action: again)
                .buttonStyle(.glassProminent)
                .padding(.top, 8)
        }
        .padding(Theme.gutter * 1.5)
    }
}
