import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Study", systemImage: "brain.head.profile") {
                NavigationStack { SessionView().navigationTitle("Study") }
            }
            Tab("Decks", systemImage: "square.stack.3d.up") {
                NavigationStack { DecksView().navigationTitle("Decks") }
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
