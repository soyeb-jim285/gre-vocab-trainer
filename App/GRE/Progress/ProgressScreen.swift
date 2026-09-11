import Charts
import GRECore
import SwiftData
import SwiftUI

/// Newest first, graded only, and bounded. Unbounded this materialised every
/// review ever answered each time the tab appeared, and introductions would drag
/// the average down with zeroes for questions never asked.
private let recentGradedReviews: FetchDescriptor<ReviewRecord> = {
    var descriptor = FetchDescriptor<ReviewRecord>(
        predicate: #Predicate { !$0.isIntroduction },
        sortBy: [SortDescriptor(\.reviewedAt, order: .reverse)]
    )
    descriptor.fetchLimit = 400
    return descriptor
}()

struct ProgressScreen: View {
    @Environment(\.catalog) private var catalog
    @Environment(AppSettings.self) private var settings
    @Environment(MasteryIndex.self) private var mastery
    @Environment(\.modelContext) private var context

    @Query(recentGradedReviews) private var reviews: [ReviewRecord]

    @State private var totalReviews = 0
    /// Words with at least one wrong idea on record. Separate from accuracy:
    /// this is what is being confused rather than what is being forgotten.
    @State private var mixedUp = 0
    @State private var spend: Double = 0
    @State private var coach: CoachSummary?
    @State private var coachError: String?
    @State private var loadingCoach = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                StatRow(cards: mastery.cards, catalog: catalog, totalReviews: totalReviews,
                        alreadyKnown: mastery.alreadyKnownIDs.count, mixedUp: mixedUp)
                LevelCard(reviews: reviews, spend: spend)
                if !reviews.isEmpty {
                    AccuracyChart(reviews: reviews)
                    UpcomingChart(cards: mastery.cards)
                }
                CoachCard(
                    coach: coach, error: coachError, loading: loadingCoach,
                    enabled: settings.hasAPIKey, run: runCoach
                )
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .task {
            // Counted, not fetched: the all-time total does not need the rows.
            totalReviews = (try? context.fetchCount(
                FetchDescriptor<ReviewRecord>(predicate: #Predicate { !$0.isIntroduction })
            )) ?? 0
            spend = AILedger.spentLifetime(in: context)
            mixedUp = Set(
                ((try? context.fetch(FetchDescriptor<MisconceptionRecord>())) ?? []).map(\.wordID)
            ).count
        }
    }

    /// What the coach needs to say something about the plan rather than only
    /// about the words.
    private var paceSummary: String? {
        let met = mastery.cards.values.filter(\.isIntroduced).count
        let advice = Pacing.advise(
            remaining: max(0, catalog.words.count - met), profile: settings.profile
        )
        guard let required = advice.required else { return nil }
        return advice.isOnTrack
            ? "on track; the test date needs \(required) new words a day and their limit is \(advice.allowed)"
            : "behind; the test date needs \(required) new words a day and their limit is \(advice.allowed), so the list will not be covered"
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
                (coach, _) = try await AILedger.spend(
                    .coach, budget: settings.profile.budget,
                    dayStart: settings.dayStart(), in: context
                ) {
                    try await settings.client().weeklyCoachWithCost(
                        recentMisses: Array(misses), recentWins: Array(wins),
                        pace: paceSummary, model: settings.coachModel
                    )
                }
                spend = AILedger.spentLifetime(in: context)
            } catch {
                coachError = (error as? OpenRouterError)?.description ?? error.localizedDescription
            }
        }
    }
}

// MARK: - Pieces

private struct StatRow: View {
    let cards: [String: StudyCard]
    let catalog: WordCatalog
    let totalReviews: Int
    /// Proved on first contact, never taught.
    let alreadyKnown: Int
    let mixedUp: Int

    private var due: Int { cards.values.filter { $0.fsrs.due <= .now }.count }

    var body: some View {
        let byID = cards
        let levels = Dictionary(catalog.words.map { (Mastery(card: byID[$0.id]), 1) }, uniquingKeysWith: +)
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mastery").font(Theme.label).foregroundStyle(Theme.tertiaryText).textCase(.uppercase)
                MasteryBar(counts: levels, total: catalog.words.count)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                Stat(value: "\((levels[.known] ?? 0) + (levels[.mastered] ?? 0))", label: "Known",
                     of: "3+ weeks' recall")
                Stat(value: "\(due)", label: "Due now", of: due == 0 ? "all caught up" : "ready to review")
                // The two halves of the model that are not a review count: what
                // the learner turned out to own already, and what they are still
                // getting wrong on purpose rather than by forgetting.
                Stat(value: "\(alreadyKnown)", label: "Already knew", of: "never taught")
                Stat(value: "\(mixedUp)", label: "Mixed up", of: mixedUp == 0 ? "nothing tangled" : "words to untangle")
                Stat(value: "\(totalReviews)", label: "Reviews", of: "all time")
            }
        }
    }
}

/// Recent accuracy, which sets the learning load, and what grading has cost.
private struct LevelCard: View {
    let reviews: [ReviewRecord]
    /// Every model call, not just the ones made while grading an answer.
    let spend: Double

    private var accuracy: Double? {
        let recent = reviews.prefix(40)
        guard recent.count >= 5 else { return nil }
        return Double(recent.map(\.score).reduce(0, +)) / Double(recent.count)
    }


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
                    .font(Theme.headword(.title))
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
        guard spend > 0 else { return "nothing spent yet" }
        return spend < 1
            ? String(format: "%.1f¢ spent so far", spend * 100)
            : String(format: "$%.2f spent so far", spend)
    }
}

private struct Stat: View {
    let value: String
    let label: String
    let of: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.headword(.title))
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
    let cards: [String: StudyCard]

    private var byDay: [(day: Date, count: Int)] {
        let today = Calendar.current.startOfDay(for: .now)
        let upcoming = cards.values.filter { $0.fsrs.due >= today }
        return Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.fsrs.due) }
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
