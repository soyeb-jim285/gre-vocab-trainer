import Charts
import GRECore
import SwiftData
import SwiftUI

struct ProgressScreen: View {
    @Environment(\.catalog) private var catalog
    @Environment(AppSettings.self) private var settings
    @Query private var cards: [CardRecord]
    @Query(sort: \ReviewRecord.reviewedAt, order: .reverse) private var reviews: [ReviewRecord]

    @State private var coach: CoachSummary?
    @State private var coachError: String?
    @State private var loadingCoach = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                StatRow(cards: cards, catalog: catalog, reviews: reviews)
                LevelCard(reviews: reviews)
                if !reviews.isEmpty {
                    AccuracyChart(reviews: reviews)
                    UpcomingChart(cards: cards)
                }
                CoachCard(
                    coach: coach, error: coachError, loading: loadingCoach,
                    enabled: settings.hasAPIKey, run: runCoach
                )
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
    }

    private func runCoach() {
        guard !loadingCoach else { return }
        loadingCoach = true
        coachError = nil
        Task {
            defer { loadingCoach = false }
            let recent = reviews.prefix(60)
            let misses = recent.filter { $0.rating == .again || $0.rating == .hard }
                .prefix(15).map(\.wordID)
            let wins = recent.filter { $0.rating == .easy }.prefix(15).map(\.wordID)
            guard !misses.isEmpty || !wins.isEmpty else {
                coachError = "Review a few words first and there'll be something to go on."
                return
            }
            do {
                coach = try await settings.client().weeklyCoach(
                    recentMisses: Array(misses), recentWins: Array(wins),
                    model: settings.coachModel
                )
            } catch {
                coachError = (error as? OpenRouterError)?.description ?? error.localizedDescription
            }
        }
    }
}

// MARK: - Pieces

private struct StatRow: View {
    let cards: [CardRecord]
    let catalog: WordCatalog
    let reviews: [ReviewRecord]

    private var byID: [String: StudyCard] {
        Dictionary(cards.map { ($0.wordID, $0.studyCard) }, uniquingKeysWith: { a, _ in a })
    }
    private var due: Int { cards.filter { $0.due <= .now }.count }

    var body: some View {
        let byID = byID
        let levels = Dictionary(catalog.words.map { (Mastery(card: byID[$0.id]), 1) }, uniquingKeysWith: +)
        let decksDone = catalog.decks.filter { DeckProgress(deck: $0, cards: byID).isComplete }.count
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mastery").font(Theme.label).foregroundStyle(Theme.tertiaryText).textCase(.uppercase)
                MasteryBar(counts: levels, total: catalog.words.count)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                Stat(value: "\(decksDone)", label: "Decks done", of: "of \(catalog.decks.count)")
                Stat(value: "\(due)", label: "Due now", of: due == 0 ? "all caught up" : "ready to review")
                Stat(value: "\((levels[.known] ?? 0) + (levels[.mastered] ?? 0))", label: "Known",
                     of: "3+ weeks' recall")
                Stat(value: "\(reviews.count)", label: "Reviews", of: "all time")
            }
        }
    }
}

/// Recent accuracy, which sets the learning load, and what grading has cost.
private struct LevelCard: View {
    let reviews: [ReviewRecord]

    private var accuracy: Double? {
        let recent = reviews.prefix(40)
        guard recent.count >= 5 else { return nil }
        return Double(recent.map(\.score).reduce(0, +)) / Double(recent.count)
    }

    private var spend: Double { reviews.compactMap(\.costUSD).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Level")
                    .font(Theme.label)
                    .foregroundStyle(Theme.tertiaryText)
                    .textCase(.uppercase)
                Spacer()
                Text(spendLabel)
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiaryText)
                    .monospacedDigit()
            }

            if let accuracy {
                Text("\(Int(accuracy))%")
                    .font(Theme.headword(28))
                    .foregroundStyle(Theme.tint(forScore: Int(accuracy)))
                Text("Recent accuracy over your last \(min(reviews.count, 40)) answers. Above 85% and new words come faster; below 60% and reviews take priority.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Answer a few more and this will show your recent accuracy, which sets how many new words you juggle at once.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var spendLabel: String {
        guard spend > 0 else { return "no grading cost yet" }
        return spend < 1
            ? String(format: "%.1f¢ spent on grading", spend * 100)
            : String(format: "$%.2f spent on grading", spend)
    }
}

private struct Stat: View {
    let value: String
    let label: String
    let of: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.headword(30))
                .foregroundStyle(Theme.accent)
            Text(label)
                .font(Theme.label)
                .foregroundStyle(Theme.primaryText)
                .textCase(.uppercase)
            Text(of)
                .font(.footnote)
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct AccuracyChart: View {
    let reviews: [ReviewRecord]

    private var byDay: [(day: Date, score: Double)] {
        let groups = Dictionary(grouping: reviews.prefix(400)) {
            Calendar.current.startOfDay(for: $0.reviewedAt)
        }
        return groups
            .map { (day: $0.key, score: Double($0.value.map(\.score).reduce(0, +)) / Double($0.value.count)) }
            .sorted { $0.day < $1.day }
            .suffix(21)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Average score")
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)
            Chart(byDay, id: \.day) { point in
                LineMark(x: .value("Day", point.day, unit: .day),
                         y: .value("Score", point.score))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Day", point.day, unit: .day),
                          y: .value("Score", point.score))
                    .foregroundStyle(Theme.accent)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 150)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct UpcomingChart: View {
    let cards: [CardRecord]

    private var byDay: [(day: Date, count: Int)] {
        let today = Calendar.current.startOfDay(for: .now)
        let upcoming = cards.filter { $0.due >= today }
        return Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.due) }
            .map { (day: $0.key, count: $0.value.count) }
            .sorted { $0.day < $1.day }
            .prefix(14)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Coming up")
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)
            Chart(byDay, id: \.day) { point in
                BarMark(x: .value("Day", point.day, unit: .day),
                        y: .value("Cards", point.count))
                    .foregroundStyle(Theme.accent.opacity(0.75))
                    .cornerRadius(4)
            }
            .frame(height: 130)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct CoachCard: View {
    let coach: CoachSummary?
    let error: String?
    let loading: Bool
    let enabled: Bool
    let run: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Coach")
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)

            if !enabled {
                Text("Add an OpenRouter key in Settings to get a read on what's tripping you up.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondaryText)
            } else if let coach {
                Text(coach.summary)
                    .font(Theme.definition)
                    .foregroundStyle(Theme.primaryText)
                ForEach(coach.focusAreas, id: \.self) { area in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "arrow.right")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                        Text(area).font(Theme.body).foregroundStyle(Theme.secondaryText)
                    }
                }
                Text(coach.encouragement)
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiaryText)
            } else if let error {
                Text(error).font(Theme.body).foregroundStyle(Theme.negative)
            }

            if enabled {
                Button(loading ? "Thinking…" : (coach == nil ? "Ask the coach" : "Ask again"), action: run)
                    .buttonStyle(.glassProminent)
                    .disabled(loading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
