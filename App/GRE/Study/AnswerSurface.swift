import GRECore
import SwiftUI

/// One tappable answer. The identity is what gets graded and the text is what
/// gets read: for a definition they are the same string, for a cloze word they
/// are not.
struct AnswerOption: Identifiable, Equatable {
    let id: String
    let text: String

    init(_ definition: String) {
        self.id = definition
        self.text = definition
    }

    init(_ word: Word) {
        self.id = word.id
        self.text = word.word
    }
}

/// Everything a question needs beyond the word itself, worked out once by the
/// view model rather than recomputed while the view redraws.
struct AnswerOptions: Equatable {
    var choices: [AnswerOption] = []
    var sentence: String = ""
    /// Short answers get the serif and long ones read as prose.
    var choicesAreWords = false
}

/// The one place the mode decides what the learner sees.
///
/// There used to be five switches on `StudyMode` that had to agree with each
/// other: view construction, check dispatch, submit validation, prompt layout
/// and prompt wording. Four of them are gone -- the wording and the layout are
/// properties on the mode, validation is a property on the draft, and dispatch
/// is a single submit. This is the one that is left, and it only builds views.
struct AnswerSurface: View {
    let item: SessionItem
    let options: AnswerOptions
    @Binding var typed: String
    @Binding var definition: String
    @Binding var sentence: String
    let choose: (String) -> Void

    var body: some View {
        switch item.mode {
        case .multipleChoice:
            OptionList(options: options, choose: choose)

        case .contextCloze, .senseInContext:
            VStack(alignment: .leading, spacing: 18) {
                SentenceCard(text: options.sentence)
                OptionList(options: options, choose: choose)
            }

        case .spelling:
            AnswerField(title: "Spelling", prompt: "Type what you heard", text: $typed)

        case .reverseRecall:
            AnswerField(title: "The word", prompt: "Type the word", text: $typed)

        case .defineAndUse:
            VStack(alignment: .leading, spacing: 22) {
                AnswerEditor(title: "Your definition",
                             prompt: "What does it mean? Your own words are fine.",
                             text: $definition)
                AnswerEditor(title: "Your sentence",
                             prompt: "Use it in a sentence that shows you mean it.",
                             text: $sentence)
            }
        }
    }
}

/// Four tappable answers.
///
/// One list for all three tap-to-answer modes. They previously had three
/// different corner radii, paddings, fonts and stack spacings, for no reason
/// beyond having been written months apart.
private struct OptionList: View {
    let options: AnswerOptions
    let choose: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(options.choices) { option in
                Button { choose(option.id) } label: {
                    Text(option.text)
                        .font(options.choicesAreWords ? Theme.headword(.title3) : Theme.definition)
                        .foregroundStyle(Theme.primaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Theme.raised, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The sentence a question is asked about. It carries the weight in both modes
/// that use it: the learner meets the word doing its job rather than sitting
/// beside a definition.
private struct SentenceCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.definition)
            .foregroundStyle(Theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

// MARK: - Inputs

private struct AnswerField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)
            TextField(prompt, text: $text)
                .font(Theme.headword(.title))
                .foregroundStyle(Theme.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 12)
            Rectangle()
                .fill(Theme.accent.opacity(0.6))
                .frame(height: 1)
        }
    }
}

private struct AnswerEditor: View {
    let title: String
    let prompt: String
    @Binding var text: String
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(prompt)
                        .font(Theme.body)
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.top, 10)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(Theme.body)
                    .foregroundStyle(Theme.primaryText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight)
            }
            .padding(10)
            .background(Theme.raised, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
        }
    }
}
