import GRECore
import SwiftData
import SwiftUI

/// The exam's own questions: a sentence with a blank and five or six options.
///
/// Deliberately not built on the session machinery. A study question is about
/// one word and grades one answer; these are about a sentence, and Sentence
/// Equivalence needs two picks before there is anything to grade. Forcing them
/// through the same path would mean a second meaning for every field on the
/// way. They still record a review per answer word, so the schedule hears about
/// them like anything else.
struct DrillView: View {
    @Environment(\.catalog) private var catalog
    @Environment(\.items) private var items
    @Environment(AppSettings.self) private var settings
    @Environment(MasteryIndex.self) private var mastery
    @Environment(\.modelContext) private var context

    @State private var queue: [GREItem] = []
    @State private var index = 0
    @State private var picked: Set<String> = []
    @State private var answered = false
    @State private var correctCount = 0
    /// Questions answered this run, so a second run does not repeat them.
    @State private var seen: Set<String> = []
    /// The learner's own word for the blank, typed before the options appear.
    @State private var prediction = ""
    /// Set once the prediction is in (or skipped); the options show after.
    @State private var predicted = false
    @State private var verdict: PredictionVerdict?

    private var current: GREItem? { index < queue.count ? queue[index] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let item = current {
                    question(item)
                } else if queue.isEmpty {
                    empty
                } else {
                    finished
                }
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle("GRE drill")
        .task { if queue.isEmpty { load() } }
    }

    // MARK: - One question

    @ViewBuilder private func question(_ item: GREItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(index + 1) of \(queue.count) · \(item.kind.label)")
                .font(Theme.label).foregroundStyle(Theme.tertiaryText).textCase(.uppercase)
            Text(item.kind.instruction)
                .font(.footnote).foregroundStyle(Theme.tertiaryText)
        }
        Text(item.stem)
            .font(Theme.definition)
            .foregroundStyle(Theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

        // Predict first, on a completion: the habit high scorers credit most,
        // and a generation task rather than a recognition one. An equivalence
        // is about the pair, so it goes straight to the options.
        if item.kind == .textCompletion && !predicted {
            predictionField(item)
        } else {
            if let verdict {
                Label("\(verdict.headline): \u{201C}\(prediction.trimmingCharacters(in: .whitespaces))\u{201D}",
                      systemImage: verdict.isOnTarget ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(verdict.isOnTarget ? Theme.positive
                                     : verdict == .unknown ? Theme.secondaryText : Theme.caution)
            }
            VStack(spacing: 10) {
                ForEach(item.options, id: \.self) { option in
                    optionRow(item, option)
                }
            }
        }

        if answered {
            explanation(item)
            Button(index + 1 < queue.count ? "Next" : "Finish") { advance() }
                .buttonStyle(.glassProminent)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
    }

    private func predictionField(_ item: GREItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your word for the blank")
                .font(Theme.label).foregroundStyle(Theme.tertiaryText).textCase(.uppercase)
            TextField("Any word that fits, before you see the choices", text: $prediction)
                .font(Theme.headword(.title3))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { reveal(item) }
            HStack(spacing: 12) {
                Button("Skip") { predicted = true }
                    .buttonStyle(.glass)
                    .foregroundStyle(Theme.secondaryText)
                Button("Show the choices") { reveal(item) }
                    .buttonStyle(.glassProminent)
                    .disabled(prediction.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func reveal(_ item: GREItem) {
        guard !prediction.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let answer = item.answers.first.flatMap({ catalog[$0] }) {
            verdict = PredictionCheck.judge(prediction, answer: answer, catalog: catalog)
        }
        predicted = true
    }

    private func optionRow(_ item: GREItem, _ option: String) -> some View {
        let isPicked = picked.contains(option)
        let isAnswer = item.answers.contains(option)
        return Button {
            choose(item, option)
        } label: {
            HStack {
                Text(catalog[option]?.word ?? option)
                    .font(Theme.headword(.body))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                if answered, isAnswer {
                    Image(systemName: "checkmark").foregroundStyle(Theme.positive)
                } else if answered, isPicked {
                    Image(systemName: "xmark").foregroundStyle(Theme.negative)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .stroke(isPicked ? Theme.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(answered)
        .accessibilityLabel(catalog[option]?.word ?? option)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func explanation(_ item: GREItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.isCorrect(picked) ? "Correct" : "Not quite")
                .font(Theme.headword(.title3))
                .foregroundStyle(item.isCorrect(picked) ? Theme.positive : Theme.negative)
            Text(item.explanation)
                .font(Theme.body).foregroundStyle(Theme.primaryText)
            // The words the question was really about, so a wrong answer leads
            // somewhere rather than just being wrong.
            ForEach(item.testedWordIDs, id: \.self) { id in
                if let word = catalog[id] {
                    NavigationLink { WordDetailView(word: word) } label: {
                        Text("\(word.word) — \(word.teachingDefinition)")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Ends

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing to drill yet").font(Theme.headword(.title2))
                .foregroundStyle(Theme.primaryText)
            Text(items.items.isEmpty
                 ? "This build ships without exam questions."
                 : "Exam questions use words you have already met. Study a few and they appear here.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Text("\(correctCount) of \(queue.count)")
                .font(Theme.headword(.largeTitle)).foregroundStyle(Theme.primaryText)
            Text("Answers counted toward each word's schedule.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            Button("Another set") { load() }
                .buttonStyle(.glassProminent).font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.gutter)
    }

    // MARK: - Behaviour

    private func load() {
        queue = DrillPlanner.session(
            from: items, cards: Array(mastery.cards.values), scheduler: settings.scheduler,
            recentItemIDs: seen, seed: UInt64(Date.now.timeIntervalSince1970), now: .now
        )
        index = 0
        correctCount = 0
        picked = []
        answered = false
        resetPrediction()
    }

    private func resetPrediction() {
        prediction = ""
        predicted = false
        verdict = nil
    }

    /// One tap for a completion; a pair for an equivalence, graded on the
    /// second, since half a pair is not an answer.
    private func choose(_ item: GREItem, _ option: String) {
        guard !answered else { return }
        if picked.contains(option) {
            picked.remove(option)
            return
        }
        picked.insert(option)
        if picked.count == item.kind.answerCount { grade(item) }
    }

    private func grade(_ item: GREItem) {
        answered = true
        seen.insert(item.id)
        let correct = item.isCorrect(picked)
        if correct { correctCount += 1 }
        let grade = Grade(score: correct ? 100 : 0)
        // Every word the question tested hears the same verdict: the learner
        // either read the sentence or did not, and the pair was the answer.
        for id in item.testedWordIDs {
            ReviewRecorder.record(
                wordID: id, mode: .greItem, grade: grade,
                rating: AnswerAppraisal.rate(grade: grade, mode: .greItem,
                                             strictness: settings.strictness),
                scheduler: settings.scheduler, in: context, index: mastery
            )
        }
    }

    private func advance() {
        index += 1
        picked = []
        answered = false
        resetPrediction()
    }
}
