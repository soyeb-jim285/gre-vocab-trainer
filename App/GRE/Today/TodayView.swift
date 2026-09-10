import GRECore
import SwiftData
import SwiftUI

/// The home of the app: what today asks for, and whether the plan still works.
///
/// The session used to run forever with no notion of a day, so there was no way
/// to know whether you were on track, no reason to stop, and nothing to come
/// back to tomorrow. A finish line is the point.
struct TodayView: View {
    @Environment(\.catalog) private var catalog
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(MasteryIndex.self) private var mastery

    @State private var plan: DayPlan?
    @State private var streak = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let plan {
                    DayCard(plan: plan, streak: streak)
                    PaceCard(plan: plan, testDate: settings.testDate)
                    startButton(plan)
                    NavigationLink("Test everything I know") {
                        SessionView(quiz: .everything).navigationTitle("Test")
                    }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
                } else {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle("Today")
        // Recomputed on every appearance rather than held: coming back from a
        // session, the numbers have moved.
        .task { refresh() }
        .onChange(of: settings.resetToken) { _, _ in refresh() }
        .onChange(of: mastery.cards.count) { _, _ in refresh() }
    }

    private func startButton(_ plan: DayPlan) -> some View {
        NavigationLink {
            SessionView().navigationTitle("Study")
        } label: {
            Text(plan.isComplete ? "Study ahead" : "Start")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .font(.headline)
    }

    private func refresh() {
        let now = Date.now
        let today = ReviewRecorder.todaysWork(in: context, since: settings.dayStart(at: now))
        plan = DayPlanner.plan(
            cards: Array(mastery.cards.values), catalog: catalog, profile: settings.profile,
            introducedToday: today.introduced, answeredToday: today.answered, now: now
        )
        streak = ReviewRecorder.streak(in: context, profile: settings.profile, now: now)
    }
}

// MARK: - Pieces

private struct DayCard: View {
    let plan: DayPlan
    let streak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(plan.isComplete ? "Done for today" : "Today")
                    .font(Theme.label)
                    .foregroundStyle(Theme.tertiaryText)
                    .textCase(.uppercase)
                Spacer()
                if streak > 1 {
                    Label("\(streak) days", systemImage: "flame.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.accent)
                }
            }

            if plan.isComplete {
                Text(plan.nextDue.map { "Next review \($0.formatted(.relative(presentation: .named)))." }
                     ?? "Every word in the list has been studied.")
                    .font(Theme.definition)
                    .foregroundStyle(Theme.primaryText)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(plan.remainingAnswers)")
                        .font(Theme.headword())
                        .foregroundStyle(Theme.accent)
                        .monospacedDigit()
                    Text(plan.remainingAnswers == 1 ? "card left" : "cards left")
                        .font(Theme.body)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text("\(plan.dueNow) to review · \(plan.newWordsRemaining) new · about \(plan.estimatedMinutes) min")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiaryText)
            }

            ProgressView(value: plan.progress)
                .tint(Theme.accent)
                .accessibilityLabel("Today's progress")
                .accessibilityValue("\(Int(plan.progress * 100)) percent")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// Whether the deadline is still reachable. Saying so is the point: falling
/// behind quietly is exactly what a test date is supposed to prevent.
private struct PaceCard: View {
    let plan: DayPlan
    let testDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pace")
                .font(Theme.label)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)

            if let testDate, let required = plan.pacing.required {
                Text("Test \(testDate.formatted(.relative(presentation: .named)))")
                    .font(Theme.definition)
                    .foregroundStyle(Theme.primaryText)
                if plan.pacing.isOnTrack {
                    Label("\(required) new words a day keeps you on track",
                          systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.positive)
                } else {
                    Label("The date needs \(required) new words a day; your limit is \(plan.pacing.allowed)",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.caution)
                }
            } else if let done = plan.pacing.completion {
                Text("At \(plan.pacing.allowed) new words a day you will have met every word by \(done.formatted(date: .abbreviated, time: .omitted)).")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("No new words a day, so the list will not finish. Raise the limit in Settings.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondaryText)
            }

            Text("\(plan.pacing.wordsRemaining) words still to meet")
                .font(.footnote)
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
