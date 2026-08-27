import GRECore
import SwiftData
import SwiftUI

/// Tiers → decks of ~25, each with a mastery ring. Search flattens to words.
struct DecksView: View {
    @Environment(\.catalog) private var catalog
    @Environment(AppSettings.self) private var settings
    @Query private var records: [CardRecord]
    @State private var search = ""

    private var cards: [String: StudyCard] {
        Dictionary(records.map { ($0.wordID, $0.studyCard) }, uniquingKeysWith: { a, _ in a })
    }

    private var matches: [Word] {
        catalog.words
            .filter { $0.word.localizedCaseInsensitiveContains(search) }
            .sorted { $0.zipf != $1.zipf ? $0.zipf > $1.zipf : $0.id < $1.id }
    }

    var body: some View {
        Group {
            if search.isEmpty { deckGrid } else { searchResults }
        }
        .searchable(text: $search, prompt: "Search \(catalog.words.count) words")
        .screenBackground()
    }

    private var deckGrid: some View {
        let cards = cards
        return ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                ForEach(WordTier.allCases.sorted(), id: \.self) { tier in
                    TierSection(tier: tier, decks: catalog.decks(inTier: tier), cards: cards,
                                currentDeckID: settings.currentDeckID)
                }
            }
            .padding(Theme.gutter)
        }
    }

    private var searchResults: some View {
        let cards = cards
        return List(matches) { word in
            NavigationLink {
                WordDetailView(word: word)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(word.word).font(Theme.headword(19)).foregroundStyle(Theme.primaryText)
                        DifficultyBadge(difficulty: word.difficulty)
                        MasteryDot(level: Mastery(card: cards[word.id]))
                    }
                    Text(word.primarySense.definition)
                        .font(.footnote).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct TierSection: View {
    let tier: WordTier
    let decks: [Deck]
    let cards: [String: StudyCard]
    let currentDeckID: String?

    private var progress: [DeckProgress] { decks.map { DeckProgress(deck: $0, cards: cards) } }

    var body: some View {
        let progress = progress
        let fraction = progress.isEmpty ? 0 : progress.map(\.fraction).reduce(0, +) / Double(progress.count)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.label).font(Theme.headword(24)).foregroundStyle(Theme.primaryText)
                Spacer()
                Text("\(progress.filter(\.isComplete).count)/\(decks.count) decks · \(Int(fraction * 100))%")
                    .font(Theme.label).foregroundStyle(Theme.tertiaryText).monospacedDigit()
            }
            Text(subtitle).font(.footnote).foregroundStyle(Theme.tertiaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                ForEach(Array(zip(decks, progress)), id: \.0.id) { deck, p in
                    NavigationLink {
                        DeckDetailView(deck: deck)
                    } label: {
                        DeckTile(deck: deck, progress: p, isCurrent: deck.id == currentDeckID)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var subtitle: String {
        switch tier {
        case .core: "On three or more prep lists — the words most worth knowing."
        case .common: "On two lists."
        case .extended: "On one list. Broad coverage once the rest is solid."
        }
    }
}

private struct DeckTile: View {
    let deck: Deck
    let progress: DeckProgress
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(progress.isComplete ? Theme.positive : Theme.accent,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress.fraction * 100))")
                    .font(Theme.label).foregroundStyle(Theme.secondaryText).monospacedDigit()
            }
            .frame(width: 52, height: 52)
            Text("\(deck.index)").font(Theme.headword(18)).foregroundStyle(Theme.primaryText)
            Text("\(progress.count(atLeast: .known))/\(progress.total) known")
                .font(.caption2).foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .cardSurface()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(isCurrent ? Theme.accent : .clear, lineWidth: 1.5)
        )
        .accessibilityLabel("\(deck.title), \(Int(progress.fraction * 100)) percent")
    }
}

/// One small dot per mastery level; the legend is in the deck header.
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
