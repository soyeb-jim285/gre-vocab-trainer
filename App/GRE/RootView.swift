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
            // Today leads: the session is what you do, but the day is what you
            // came to find out about.
            Tab("Today", systemImage: "sun.horizon") {
                NavigationStack { TodayView() }
            }
            Tab("Library", systemImage: "square.stack.3d.up") {
                NavigationStack { DecksView().navigationTitle("Library") }
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
