import GRECore
import SwiftData
import SwiftUI

struct DeckDetailView: View {
    let deck: Deck

    @Environment(\.catalog) private var catalog
    @Query private var records: [CardRecord]
    @Query private var quizzes: [QuizRecord]

    private var cards: [String: StudyCard] {
        Dictionary(records.map { ($0.wordID, $0.studyCard) }, uniquingKeysWith: { a, _ in a })
    }
    private var bestScore: Int? { quizzes.filter { $0.deckID == deck.id }.map(\.score).max() }

    var body: some View {
        let cards = cards
        let progress = DeckProgress(deck: deck, cards: cards)
        let studiedCount = deck.wordIDs.filter { (cards[$0]?.reviewCount ?? 0) > 0 }.count
        List {
            Section {
                header(progress: progress, studiedCount: studiedCount)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                ForEach(deck.wordIDs.compactMap { catalog[$0] }) { word in
                    NavigationLink {
                        WordDetailView(word: word)
                    } label: {
                        let level = Mastery(card: cards[word.id])
                        HStack(spacing: 10) {
                            MasteryDot(level: level)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(word.word).font(Theme.headword(18)).foregroundStyle(Theme.primaryText)
                                Text(word.teachingDefinition)
                                    .font(.footnote).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                            }
                            Spacer()
                            Text(level.label).font(.caption2).foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(deck.title)
    }

    private func header(progress: DeckProgress, studiedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            MasteryBar(counts: progress.counts, total: progress.total)
            HStack {
                Text("\(Int(progress.fraction * 100))% mastered")
                    .font(Theme.label).foregroundStyle(Theme.secondaryText)
                Spacer()
                if let bestScore {
                    Text("Best test \(bestScore)%")
                        .font(Theme.label).foregroundStyle(Theme.tint(forScore: bestScore))
                }
            }
            HStack(spacing: 12) {
                NavigationLink {
                    SessionView(deck: deck).navigationTitle("Study")
                } label: {
                    Label("Study this deck", systemImage: "brain.head.profile")
                }
                .buttonStyle(.glassProminent)

                NavigationLink {
                    SessionView(quiz: .deck(deck)).navigationTitle("Test \(deck.title)")
                } label: {
                    Label("Test", systemImage: "checkmark.seal")
                }
                .buttonStyle(.glass)
                .disabled(studiedCount < QuizPlanner.minimumWords)
            }
            .font(.headline)
            if studiedCount < QuizPlanner.minimumWords {
                Text("Study at least \(QuizPlanner.minimumWords) words here to unlock the test.")
                    .font(.footnote).foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(Theme.gutter)
        .cardSurface()
    }
}

/// Five segments, new → mastered, each sized by count. Shared with Progress.
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
            HStack(spacing: 12) {
                ForEach(Mastery.allCases, id: \.self) { level in
                    HStack(spacing: 4) {
                        MasteryDot(level: level)
                        Text("\(counts[level] ?? 0) \(level.label.lowercased())")
                            .font(.caption2).foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
        }
    }
}
