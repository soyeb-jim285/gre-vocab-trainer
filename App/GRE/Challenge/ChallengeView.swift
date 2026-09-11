import GRECore
import SwiftData
import SwiftUI

/// Twenty questions over words already met, fixed for the day.
///
/// Separate from the day's plan on purpose. The plan is scheduled work and its
/// finish line moves with the schedule; the challenge is the same twenty
/// questions however many times it is opened, so it is a thing you either did
/// or did not do today. It needs no API key either, which makes it the screen
/// that still works on a train.
struct ChallengeView: View {
    @Environment(\.catalog) private var catalog
    @Environment(AppSettings.self) private var settings
    @Environment(MasteryIndex.self) private var mastery
    @Environment(\.modelContext) private var context

    @Query(sort: \QuizRecord.takenAt, order: .reverse) private var results: [QuizRecord]

    private var today: QuizRecord? {
        results.first { $0.takenAt >= settings.dayStart() }
    }

    private var questions: Int {
        QuizPlanner.dailyChallenge(
            cards: Array(mastery.cards.values), catalog: catalog,
            scheduler: settings.scheduler, dayStart: settings.dayStart(), now: .now
        ).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                card
                if !results.isEmpty { history }
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle("Challenge")
    }

    @ViewBuilder private var card: some View {
        let count = questions
        VStack(alignment: .leading, spacing: 14) {
            Text(count == 0 ? "Nothing to challenge yet" : "\(count) questions")
                .font(Theme.headword(.title2)).foregroundStyle(Theme.primaryText)
            Text(subtitle(count: count))
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            if count > 0 {
                NavigationLink {
                    SessionView(quiz: .dailyChallenge).navigationTitle("Challenge")
                } label: {
                    Text(today == nil ? "Start" : "Take it again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func subtitle(count: Int) -> String {
        guard count > 0 else {
            return "Study \(QuizPlanner.minimumWords) words and the day's challenge appears here."
        }
        if let today {
            return "Done today — \(today.score)%. The same set stays until tomorrow."
        }
        return "Mixed questions on words you have already met. No key needed."
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past challenges").font(Theme.label)
                .foregroundStyle(Theme.tertiaryText).textCase(.uppercase)
            ForEach(results.prefix(10)) { result in
                HStack {
                    Text(result.takenAt, format: .dateTime.weekday().day().month())
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text("\(result.score)%")
                        .font(Theme.label).monospacedDigit()
                        .foregroundStyle(result.score >= 80 ? Theme.positive : Theme.primaryText)
                    Text("· \(result.wordCount)")
                        .font(.caption).foregroundStyle(Theme.tertiaryText).monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
