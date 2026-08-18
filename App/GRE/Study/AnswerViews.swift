import GRECore
import SwiftUI

struct MultipleChoiceAnswer: View {
    let options: [Word]
    let choose: (Word) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(options) { option in
                Button { choose(option) } label: {
                    Text(option.primarySense.definition)
                        .font(Theme.definition)
                        .foregroundStyle(Theme.primaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Theme.raised, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SpellingAnswer: View {
    @Binding var typed: String

    var body: some View {
        AnswerField(
            title: "Spelling",
            prompt: "Type what you heard",
            text: $typed,
            autocorrect: false
        )
    }
}

struct RecallAnswer: View {
    @Binding var typed: String

    var body: some View {
        AnswerField(title: "The word", prompt: "Type the word", text: $typed, autocorrect: false)
    }
}

struct DefineAndUseAnswer: View {
    @Binding var definition: String
    @Binding var sentence: String

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            AnswerEditor(
                title: "Your definition",
                prompt: "What does it mean? Your own words are fine.",
                text: $definition
            )
            AnswerEditor(
                title: "Your sentence",
                prompt: "Use it in a sentence that shows you mean it.",
                text: $sentence
            )
        }
    }
}

// MARK: - Inputs

private struct AnswerField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var autocorrect = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)
            TextField(prompt, text: $text)
                .font(Theme.headword(26))
                .foregroundStyle(Theme.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(!autocorrect)
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
                    .frame(minHeight: 96)
            }
            .padding(10)
            .background(Theme.raised, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
        }
    }
}

// MARK: - Feedback

struct FeedbackCard: View {
    let feedback: AnswerFeedback
    let item: SessionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(feedback.headline)
                    .font(Theme.headword(26))
                    .foregroundStyle(Theme.tint(forScore: feedback.score))
                Spacer()
                Text("\(feedback.score)")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.tint(forScore: feedback.score))
            }

            if !feedback.detail.isEmpty {
                Text(feedback.detail)
                    .font(Theme.definition)
                    .foregroundStyle(Theme.primaryText)
            }

            if let sentenceFeedback = feedback.sentenceFeedback, !sentenceFeedback.isEmpty {
                Divider().overlay(Theme.hairline)
                LabelledBlock(title: "Your sentence", text: sentenceFeedback)
            }

            if let corrected = feedback.correctedSentence, !corrected.isEmpty {
                LabelledBlock(title: "Tightened up", text: corrected, italic: true)
            }

            if !feedback.missedNuances.isEmpty {
                Divider().overlay(Theme.hairline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Worth noticing")
                        .font(Theme.label)
                        .foregroundStyle(Theme.tertiaryText)
                        .textCase(.uppercase)
                    ForEach(feedback.missedNuances, id: \.self) { nuance in
                        Label(nuance, systemImage: "circle.fill")
                            .font(Theme.body)
                            .foregroundStyle(Theme.secondaryText)
                            .labelStyle(BulletLabelStyle())
                    }
                }
            }

            Divider().overlay(Theme.hairline)
            NextReviewNote(word: item.word.word, rating: feedback.rating)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct LabelledBlock: View {
    let title: String
    let text: String
    var italic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)
            Text(text)
                .font(italic ? Theme.definition.italic() : Theme.body)
                .foregroundStyle(Theme.primaryText)
        }
    }
}

private struct NextReviewNote: View {
    let word: String
    let rating: FSRSRating

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Theme.tertiaryText)
    }

    private var message: String {
        switch rating {
        case .again: "\(word) will come back very soon."
        case .hard: "\(word) will come back sooner than usual."
        case .good: "\(word) is scheduled as normal."
        case .easy: "\(word) won't be back for a while."
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(Theme.accent)
            configuration.title
        }
    }
}
