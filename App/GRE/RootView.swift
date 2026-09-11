import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        // Until the app knows the deadline and the daily limit, it has no idea
        // what a day should hold, so there is nothing honest to show first.
        if settings.hasOnboarded {
            tabs
        } else {
            OnboardingView()
        }
    }

    private var tabs: some View {
        TabView {
            // Learning leads: the session is what you do, but the day is what
            // you came to find out about.
            Tab("Learn", systemImage: "sun.horizon") {
                NavigationStack { TodayView() }
            }
            Tab("Challenge", systemImage: "target") {
                NavigationStack { ChallengeView() }
            }
            Tab("Drill", systemImage: "doc.text") {
                NavigationStack { DrillView() }
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") {
                NavigationStack { ProgressScreen().navigationTitle("Progress") }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack { SettingsView().navigationTitle("Settings") }
            }
        }
        .tint(Theme.accent)
    }
}
