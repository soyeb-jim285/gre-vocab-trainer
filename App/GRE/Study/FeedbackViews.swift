import GRECore
import SwiftUI

struct FeedbackCard: View {
    let feedback: AnswerFeedback
    let item: SessionItem
    /// What the learner picked, when they picked something.
    var chosen: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(feedback.headline)
                    .font(Theme.headword(.title))
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

            // Seeing the wrong answer named is how the learner works out what
            // they confused it with. The app tracked this and never showed it.
            if let wrong = wrongChoice {
                LabelledBlock(title: "You chose", text: wrong)
                    .foregroundStyle(Theme.negative)
            }

            if let sentenceFeedback = feedback.extras.sentenceFeedback, !sentenceFeedback.isEmpty {
                Divider().overlay(Theme.hairline)
                LabelledBlock(title: "Your sentence", text: sentenceFeedback)
            }

            if let corrected = feedback.extras.correctedSentence, !corrected.isEmpty {
                LabelledBlock(title: "Tightened up", text: corrected, italic: true)
            }

            if let memorable = feedback.extras.memorableSentence, !memorable.isEmpty {
                LabelledBlock(title: "Worth remembering", text: memorable, italic: true)
            }

            if !feedback.extras.missedNuances.isEmpty {
                Divider().overlay(Theme.hairline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Worth noticing")
                        .font(Theme.label)
                        .foregroundStyle(Theme.tertiaryText)
                        .textCase(.uppercase)
                    ForEach(feedback.extras.missedNuances, id: \.self) { nuance in
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

    /// Nil when they were right, or when the mode had nothing to pick.
    private var wrongChoice: String? {
        guard let chosen, chosen != AnswerJudge.correctChoice(for: item),
              item.mode.isTapToAnswer
        else { return nil }
        // Cloze options are identified by the word itself; the other two by the
        // definition text. Either way the identity is what to show.
        return chosen
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
            BulletDot(icon: configuration.icon)
            configuration.title
        }
    }
}

/// A view of its own rather than a `@ScaledMetric` on the style: the scaling
/// wrappers only track the environment inside a View or ViewModifier. A dot
/// pinned at 5pt beside body text scaled to 50pt reads as a rendering fault.
private struct BulletDot<Icon: View>: View {
    let icon: Icon
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 5

    var body: some View {
        icon
            .font(.system(size: size))
            .foregroundStyle(Theme.accent)
            .accessibilityHidden(true)
    }
}
