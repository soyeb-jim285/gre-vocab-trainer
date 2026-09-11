import GRECore
import SwiftUI

/// Every word in the dataset, searchable.
///
/// What is left of the Library once the deck grid goes. Decks were a unit of
/// progress the learner never chose and could not finish out of order: the
/// schedule decides what comes next, and a grid of numbered tiles only invited
/// second-guessing it. The words themselves are still worth looking up.
struct WordsView: View {
    @Environment(\.catalog) private var catalog
    @Environment(MasteryIndex.self) private var mastery
    @State private var search = ""

    private var matches: [Word] {
        let pool = search.isEmpty
            ? catalog.words
            : catalog.words.filter { $0.word.localizedCaseInsensitiveContains(search) }
        return pool.sorted { $0.zipf != $1.zipf ? $0.zipf > $1.zipf : $0.id < $1.id }
    }

    var body: some View {
        List(matches) { word in
            NavigationLink {
                WordDetailView(word: word)
            } label: {
                row(word)
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $search, prompt: "Search \(catalog.words.count) words")
        .screenBackground()
        .navigationTitle("Words")
    }

    private func row(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(word.word).font(Theme.headword(.title3)).foregroundStyle(Theme.primaryText)
                DifficultyBadge(difficulty: word.difficulty)
                MasteryDot(level: Mastery(card: mastery[word.id]))
            }
            Text(word.teachingDefinition)
                .font(.footnote).foregroundStyle(Theme.tertiaryText).lineLimit(2)
        }
    }
}

/// The whole catalog's mastery as one bar. Lives here with the dot it is built
/// from, rather than back in the deck screen that used to own both.
struct MasteryBar: View {
    let counts: [Mastery: Int]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Mastery.allCases, id: \.self) { level in
                        let n = counts[level] ?? 0
                        if n > 0 {
                            MasteryDot.color(level)
                                .frame(width: max(2, geo.size.width * Double(n) / Double(max(total, 1))))
                        }
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            // The bar carries its meaning entirely in colour and segment width,
            // so it says nothing at all without this.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mastery")
            .accessibilityValue(spokenBreakdown)
            HStack(spacing: 12) {
                ForEach(Mastery.allCases, id: \.self) { level in
                    HStack(spacing: 4) {
                        MasteryDot(level: level)
                        Text("\(counts[level] ?? 0) \(level.label.lowercased())")
                            .font(.caption2).foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var spokenBreakdown: String {
        Mastery.allCases
            .compactMap { level in
                let n = counts[level] ?? 0
                return n > 0 ? "\(n) \(level.label.lowercased())" : nil
            }
            .joined(separator: ", ")
    }
}

/// One small dot per mastery level.
struct MasteryDot: View {
    let level: Mastery

    var body: some View {
        Circle().fill(MasteryDot.color(level)).frame(width: 8, height: 8)
            .accessibilityLabel(level.label)
    }

    static func color(_ level: Mastery) -> Color {
        switch level {
        case .new: Theme.hairline
        case .learning: Theme.negative
        case .familiar: Theme.accent.opacity(0.6)
        case .known: Theme.accent
        case .mastered: Theme.positive
        }
    }
}
