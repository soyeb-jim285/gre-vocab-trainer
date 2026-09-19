import GRECore
import SwiftData
import SwiftUI

struct SessionView: View {
    /// A fixed queue instead of the open-ended session.
    var quiz: SessionShape? = nil
    @Environment(\.modelContext) private var context
    @Environment(MasteryIndex.self) private var mastery
    @Environment(AppSettings.self) private var settings
    @Environment(\.catalog) private var catalog

    @State private var model: SessionViewModel?

    /// The learner's typing lives here, not in the view model and not inside the
    /// answer surface. A failed grading call used to replace the whole screen,
    /// which unmounted whatever held the drafts; keeping them on the one view
    /// that is never torn down means an answer survives a dropped connection.
    @State private var typed = ""
    @State private var definitionDraft = ""
    @State private var sentenceDraft = ""
    @AccessibilityFocusState private var feedbackFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

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
            if quiz == nil {
                ToolbarItem(placement: .topBarLeading) {
                    if let model, model.cardsSeen > 0, isAnswerable(model) {
                        Button("Done") { model.stop() }.font(Theme.label)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { modePicker }
            }
        }
        .task {
            guard model == nil else { return }
            let created = SessionViewModel(context: context, catalog: catalog, settings: settings,
                                          index: mastery, quiz: quiz)
            created.start()
            model = created
        }
        // Changing what you're drilling has to rebuild the queue, so the change
        // takes effect on the very next card rather than the next session.
        .onChange(of: settings.forcedMode) { _, _ in if quiz == nil { model?.start() } }
        // A reset deleted the records this session was built from; rebuild
        // rather than grade cards that no longer exist.
        .onChange(of: settings.resetToken) { _, _ in model?.start() }
        // The clock keeps running while the app is merely backgrounded on a
        // device that is awake, which is someone answering the door, not
        // hesitating.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model?.resumeTimer() } else { model?.pauseTimer() }
        }
    }

    private func clearDrafts() {
        typed = ""
        definitionDraft = ""
        sentenceDraft = ""
    }

    /// What the learner has entered, in the shape the judge reads.
    ///
    /// Both written modes fill `definitionDraft`; only `defineAndUse` asks for a
    /// sentence too, and the pretest is its own draft case because it is graded
    /// against the word's grounding rather than one reference line.
    private func draft(for item: SessionItem) -> AnswerDraft {
        switch item.mode {
        case .defineAndUse:
            .written(definition: definitionDraft, sentence: sentenceDraft)
        case .typeMeaning:
            .meaning(definitionDraft)
        default:
            .typed(typed)
        }
    }

    private func isAnswerable(_ model: SessionViewModel) -> Bool {
        switch model.phase {
        // Including the teaching card: someone who has answered a few and then
        // meets a new word should still be able to stop.
        case .answering, .reviewing, .introducing: true
        default: false
        }
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
                ForEach(StudyMode.forceable.filter { settings.hasAPIKey || !$0.needsAI }, id: \.self) { mode in
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

        case let .finished(summary):
            SessionCompleteView(summary: summary, again: { model.start() }, showTestEverything: quiz == nil)

        case let .caughtUp(nextDue):
            CaughtUpView(nextDue: nextDue, keepGoing: { model.keepGoing() })

        case .grading:
            GradingView(word: model.current?.word.word ?? "")

        case .introducing:
            if case let .introduce(word, _)? = model.current {
                VStack(spacing: 0) {
                    ScrollView {
                        IntroduceCard(word: word, accent: settings.accent,
                                      voiceIdentifier: settings.voiceIdentifier)
                            .padding(Theme.gutter)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    GlassEffectContainer(spacing: 16) {
                        Button("Got it") { model.finishIntroduction() }
                            .buttonStyle(.glassProminent)
                            .font(.headline)
                            .padding(.horizontal, Theme.gutter)
                            .padding(.bottom, 12)
                    }
                }
            }

        case .answering, .reviewing:
            if let item = model.current?.item {
                VStack(spacing: 0) {
                    if let progress = model.progress {
                        SessionProgressBar(progress: progress)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            PromptCard(
                                item: item, accent: settings.accent,
                                voiceIdentifier: settings.voiceIdentifier,
                                didPlayAudio: { model.noteAudioPlayed() }
                            )
                            if case let .reviewing(feedback) = model.phase {
                                FeedbackCard(feedback: feedback, item: item,
                                             chosen: model.chosenOptionID)
                                    .accessibilityFocused($feedbackFocused)
                            } else {
                                if let message = model.lastError {
                                    ErrorBanner(message: message)
                                }
                                AnswerSurface(
                                    item: item, options: model.options(for: item),
                                    typed: $typed, definition: $definitionDraft,
                                    sentence: $sentenceDraft
                                ) { chosen in
                                    let draft: AnswerDraft = item.mode == .gist
                                        ? .recalled(chosen == GistReveal.recalled)
                                        : .choice(chosen)
                                    Task { await model.submit(draft) }
                                }
                                if !model.hintsShown.isEmpty {
                                    HintList(hints: model.hintsShown)
                                }
                                // Asked before the reveal, never after: once the
                                // answer is on screen this stops being a report
                                // and becomes a reaction to being told.
                                // A quick round is a single tap; asking first
                                // would double its cost.
                                if !item.mode.isQuickRound {
                                    ConfidenceRow(selected: model.selfReport) { model.note($0) }
                                }
                            }
                        }
                        .padding(Theme.gutter)
                    }
                }
                .safeAreaInset(edge: .bottom) { actionBar(model, item) }
                .onChange(of: model.phase) { _, phase in
                    if case .reviewing = phase {
                        // VoiceOver was on an option that no longer exists.
                        feedbackFocused = true
                    }
                }
            }
        }
    }

    /// The one place Liquid Glass belongs: a floating control layer over content.
    private func actionBar(_ model: SessionViewModel, _ item: SessionItem) -> some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                if isReviewing(model) {
                    Button("Next") {
                        clearDrafts()
                        model.advance()
                    }
                    .buttonStyle(.glassProminent)
                } else if item.mode.isQuickRound {
                    // The answer is the tap; there is nothing to hint at.
                    EmptyView()
                } else {
                    // Available in every mode, including multiple choice --
                    // guessing at random teaches nothing and pollutes the
                    // schedule with answers that were never really known.
                    // Stuck has two branches, and only one of them teaches. A
                    // nudge first, the answer only when the nudges run out.
                    if model.canHint {
                        Button("Hint") { model.takeHint() }
                            .buttonStyle(.glass)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Button("I don't know") {
                            Task { await model.admitNotKnowing() }
                        }
                        .buttonStyle(.glass)
                        .foregroundStyle(Theme.secondaryText)
                    }

                    if !item.mode.isTapToAnswer {
                        let draft = draft(for: item)
                        Button("Check") { Task { await model.submit(draft) } }
                            .buttonStyle(.glassProminent)
                            // The rule for what counts as an answer is stated
                            // once, on the draft, for every mode at once.
                            .disabled(!draft.isSubmittable)
                    }
                }
            }
            .font(.headline)
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 12)
        }
    }

    private func isReviewing(_ model: SessionViewModel) -> Bool {
        if case .reviewing = model.phase { return true }
        return false
    }
}

/// How sure the learner is, asked before anything is revealed.
///
/// Three buttons rather than a slider: the distinction that matters is guess
/// versus shaky versus sure, and a continuous control invites the learner to
/// think about calibration instead of about the word.
private struct ConfidenceRow: View {
    let selected: SelfReport?
    let choose: (SelfReport) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How sure are you?")
                .font(.footnote)
                .foregroundStyle(Theme.tertiaryText)
            HStack(spacing: 8) {
                ForEach(SelfReport.allCases, id: \.self) { report in
                    Button(label(report)) { choose(report) }
                        .buttonStyle(.glass)
                        .font(Theme.label)
                        .foregroundStyle(report == selected ? Theme.accent : Theme.secondaryText)
                        .accessibilityAddTraits(report == selected ? [.isSelected] : [])
                }
            }
        }
    }

    private func label(_ report: SelfReport) -> String {
        switch report {
        case .guess: "Guessing"
        case .unsure: "Not sure"
        case .confident: "Confident"
        }
    }
}

/// The rungs of the ladder the learner has taken, kept on screen so a hint read
/// three seconds ago is still there when they start typing.
private struct HintList: View {
    let hints: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(hint)
                        .font(Theme.body)
                        .foregroundStyle(Theme.primaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A failed call, above the answer rather than instead of it.
private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.negative)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(Theme.body)
                    .foregroundStyle(Theme.primaryText)
                // Nothing was scheduled, so the answer is still there to resubmit.
                Text("Nothing was recorded. Your answer is still here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.negative.opacity(0.12), in: .rect(cornerRadius: 14))
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
///
/// The question and what to show above it are both properties of the mode now.
/// They used to be written here and again in the answer view, in slightly
/// different words.
private struct PromptCard: View {
    let item: SessionItem
    let accent: SpeechAccent
    let voiceIdentifier: String?
    let didPlayAudio: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.mode.question)
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)

            switch item.mode.promptSubject {
            case .audio:
                Button(action: play) {
                    Label("Play the word", systemImage: "speaker.wave.3.fill")
                        .font(Theme.headword(.title))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

            case .definition:
                Text(item.word.teachingDefinition)
                    .font(Theme.definition)
                    .foregroundStyle(Theme.primaryText)

            case .word:
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.word.word)
                        .font(Theme.headword())
                        .foregroundStyle(Theme.primaryText)
                    Button(action: play) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityLabel("Hear \(item.word.word) pronounced")
                    .buttonStyle(.plain)
                }
                if !item.word.ipa.isEmpty {
                    Text(item.word.ipa)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.tertiaryText)
                }
                Text(item.word.primaryPartOfSpeech.rawValue)
                    .font(Theme.label)
                    .foregroundStyle(Theme.tertiaryText)

            case .nothing:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func play() {
        Speaker.shared.say(item.word, accent: accent, voiceIdentifier: voiceIdentifier)
        didPlayAudio()
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

private struct SessionCompleteView: View {
    let summary: SessionSummary
    let again: () -> Void
    let showTestEverything: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: summary.isQuiz ? "rosette" : "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(summary.isQuiz ? "\(summary.meanScore)%" : "Nice work")
                .font(Theme.headword(summary.isQuiz ? .largeTitle : .title))
                .foregroundStyle(summary.isQuiz ? Theme.tint(forScore: summary.meanScore) : Theme.primaryText)
            Text(summary.answered == 0
                 ? (summary.isQuiz ? "Study at least \(QuizPlanner.minimumWords) words first." : "Nothing answered yet.")
                 : "\(summary.answered) \(summary.answered == 1 ? "word" : "words") · \(summary.meanScore)% average")
                .font(Theme.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button(summary.isQuiz ? "Test again" : "Keep studying", action: again)
                .buttonStyle(.glassProminent)
                .padding(.top, 8)
            if showTestEverything {
                NavigationLink("Take today's challenge") { SessionView(quiz: .dailyChallenge).navigationTitle("Challenge") }
                    .buttonStyle(.glass)
            }
        }
        .padding(Theme.gutter * 1.5)
    }
}

private struct CaughtUpView: View {
    let nextDue: Date?
    let keepGoing: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "moon.stars")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("All caught up")
                .font(Theme.headword(.title))
                .foregroundStyle(Theme.primaryText)
            Text(nextDue.map { "Next review \($0.formatted(.relative(presentation: .named)))." }
                 ?? "Every word in the list has been studied.")
                .font(Theme.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            // Reviewing early is a little wasteful and a lot better than stopping
            // someone who wants to keep going.
            Button("Keep going anyway", action: keepGoing)
                .buttonStyle(.glassProminent)
            NavigationLink("Take today's challenge") { SessionView(quiz: .dailyChallenge).navigationTitle("Challenge") }
                .buttonStyle(.glass)
        }
        .padding(Theme.gutter * 1.5)
    }
}
