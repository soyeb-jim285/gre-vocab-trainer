import GRECore
import SwiftUI

struct MultipleChoiceAnswer: View {
    let options: [Word]
    let choose: (Word) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(options) { option in
                Button { choose(option) } label: {
                    Text(option.teachingDefinition)
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

/// A sentence with a gap, and four words that might fill it.
///
/// The sentence carries the weight here: the learner meets the word doing its
/// job rather than sitting beside a definition.
struct ClozeAnswer: View {
    let sentence: String
    let options: [Word]
    let choose: (Word) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(sentence)
                .font(Theme.definition)
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()

            VStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        choose(option)
                    } label: {
                        Text(option.word)
                            .font(Theme.headword(19))
                            .foregroundStyle(Theme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

/// A common word used in its uncommon tested sense, and the meanings it gets
/// confused with. The wrong answers are the everyday senses on purpose.
struct SenseAnswer: View {
    let word: Word
    let sentence: String
    let options: [String]
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Which meaning is used here?")
                    .font(Theme.label)
                    .foregroundStyle(Theme.tertiaryText)
                    .textCase(.uppercase)
                Text(sentence)
                    .font(Theme.definition)
                    .foregroundStyle(Theme.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            VStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    Button {
                        choose(option)
                    } label: {
                        Text(option)
                            .font(Theme.body)
                            .foregroundStyle(Theme.primaryText)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

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

            if let memorable = feedback.memorableSentence, !memorable.isEmpty {
                LabelledBlock(title: "Worth remembering", text: memorable, italic: true)
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

            if feedback.showsReference {
                Divider().overlay(Theme.hairline)
                ReferenceBlock(word: item.word)
            }

            Divider().overlay(Theme.hairline)
            HStack {
                NextReviewNote(word: item.word.word, rating: feedback.rating)
                Spacer()
                if let cost = feedback.cost {
                    // Worth seeing per grade: it is the only recurring cost of
                    // using the app, and it is easy to pick an expensive model
                    // without noticing.
                    Text("\(cost.displayCost) · \(cost.totalTokens) tok")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiaryText)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// What the dictionary actually says, shown after the model's verdict so the
/// learner checks their answer against the source rather than against a
/// paraphrase of it. All of this ships in the bundle, so it costs nothing.
private struct ReferenceBlock: View {
    let word: Word

    private var synonyms: [String] {
        // Deduplicated across senses; the same synonym often appears in several.
        var seen = Set<String>()
        return word.senses.flatMap(\.synonyms).filter { seen.insert($0).inserted }
    }

    private var examples: [String] {
        Array(word.senses.flatMap(\.examples).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let gre = word.gre {
                // The sense the exam tests, in plain English. WordNet's own
                // wording follows below for anyone who wants the detail.
                VStack(alignment: .leading, spacing: 10) {
                    Text(gre.pos.rawValue)
                        .font(.caption2)
                        .foregroundStyle(Theme.accent.opacity(0.8))
                        .textCase(.uppercase)
                    Text(gre.definition)
                        .font(Theme.definition)
                        .foregroundStyle(Theme.primaryText)
                    ForEach(gre.sentences, id: \.self) { sentence in
                        Text(sentence)
                            .font(Theme.body.italic())
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if !gre.synonyms.isEmpty || !gre.antonyms.isEmpty {
                        HStack(alignment: .top, spacing: 18) {
                            if !gre.synonyms.isEmpty {
                                LabelledList(title: "Same", words: gre.synonyms, tint: Theme.positive)
                            }
                            if !gre.antonyms.isEmpty {
                                LabelledList(title: "Opposite", words: gre.antonyms, tint: Theme.negative)
                            }
                        }
                    }
                }
                Divider().overlay(Theme.hairline)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(word.senses.count > 1 ? "Other senses" : "In the dictionary")
                    .font(Theme.label)
                    .foregroundStyle(Theme.tertiaryText)
                    .textCase(.uppercase)
                ForEach(Array(word.senses.enumerated()), id: \.offset) { _, sense in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sense.pos.rawValue)
                            .font(.caption2)
                            .foregroundStyle(Theme.accent.opacity(0.8))
                            .textCase(.uppercase)
                        Text(sense.definition)
                            .font(Theme.definition)
                            .foregroundStyle(Theme.primaryText)
                    }
                }
            }

            if !synonyms.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Synonyms")
                        .font(Theme.label)
                        .foregroundStyle(Theme.tertiaryText)
                        .textCase(.uppercase)
                    Text(synonyms.joined(separator: " · "))
                        .font(Theme.body)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if !examples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In use")
                        .font(Theme.label)
                        .foregroundStyle(Theme.tertiaryText)
                        .textCase(.uppercase)
                    ForEach(examples, id: \.self) { example in
                        Text("\u{201C}\(example)\u{201D}")
                            .font(Theme.definition.italic())
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }
}

/// Synonyms and antonyms side by side, tinted so the two are distinguishable
/// at a glance rather than by reading the headings.
private struct LabelledList: View {
    let title: String
    let words: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)
            Text(words.joined(separator: ", "))
                .font(.footnote)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
