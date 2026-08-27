import GRECore
import SwiftData
import SwiftUI

/// Writing practice for one chosen word, outside the scheduled session.
///
/// The scheduled session eases a word in through the warmup modes before asking
/// for a definition and a sentence. That is right for learning but wrong for
/// discovering the app, so any word can be practised directly. The result is
/// scheduled exactly as a session answer would be.
struct WritingPracticeView: View {
    let word: Word

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var definition = ""
    @State private var sentence = ""
    @State private var result: GradeResult?
    @State private var cost: CallCost?
    @State private var error: String?
    @State private var grading = false

    private var canSubmit: Bool {
        !definition.trimmingCharacters(in: .whitespaces).isEmpty
            && !sentence.trimmingCharacters(in: .whitespaces).isEmpty
            && !grading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if let result {
                        FeedbackCard(
                            feedback: AnswerFeedback(
                                score: result.combinedScore,
                                rating: result.rating,
                                headline: headline(result.combinedScore),
                                detail: result.definitionFeedback,
                                sentenceFeedback: result.sentenceFeedback,
                                correctedSentence: result.correctedSentence,
                                missedNuances: result.missedNuances,
                                memorableSentence: result.memorableSentence,
                                cost: cost,
                                showsReference: true
                            ),
                            item: SessionItem(
                                card: StudyCard(wordID: word.id), word: word, mode: .defineAndUse
                            )
                        )
                    } else {
                        DefineAndUseAnswer(definition: $definition, sentence: $sentence)
                        if let error {
                            Text(error).font(Theme.body).foregroundStyle(Theme.negative)
                            Text("Nothing was recorded — your answer is still here.")
                                .font(.footnote)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }
                .padding(Theme.gutter)
            }
            .screenBackground()
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if result == nil {
                        Button(grading ? "Grading…" : "Check") { Task { await grade() } }
                            .disabled(!canSubmit)
                    } else {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.word)
                .font(Theme.headword(34))
                .foregroundStyle(Theme.primaryText)
            if !word.ipa.isEmpty {
                Text(word.ipa).font(Theme.mono).foregroundStyle(Theme.tertiaryText)
            }
            Text(word.primaryPartOfSpeech.rawValue)
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)
        }
    }

    private func grade() async {
        guard !grading else { return }
        grading = true
        error = nil
        defer { grading = false }
        do {
            let (graded, spent) = try await settings.client().gradeWithCost(
                word: word.word,
                referenceDefinition: word.teachingDefinition,
                partOfSpeech: word.primaryPartOfSpeech.rawValue,
                learnerDefinition: definition,
                learnerSentence: sentence,
                model: settings.gradingModel
            )
            cost = spent
            ReviewRecorder.record(
                wordID: word.id, mode: .defineAndUse,
                grade: Grade(score: graded.combinedScore), rating: graded.rating,
                scheduler: settings.scheduler, in: context, cost: spent
            )
            result = graded
        } catch {
            // Not scheduled: a failed call says nothing about the learner.
            self.error = (error as? OpenRouterError)?.description ?? error.localizedDescription
        }
    }

    private func headline(_ score: Int) -> String {
        switch score {
        case 90...: "Excellent"
        case 70..<90: "Good"
        case 50..<70: "Shaky"
        default: "Needs work"
        }
    }
}
