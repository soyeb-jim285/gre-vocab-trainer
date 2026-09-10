import Foundation
import GRECore
import SwiftData
import SwiftUI

@main
struct GREApp: App {
    @State private var settings = AppSettings()
    @State private var catalog: WordCatalog?
    @State private var mastery = MasteryIndex()
    @State private var loadError: String?

    private let container: ModelContainer = {
        let schema = Schema([
            CardRecord.self, ReviewRecord.self, DeepDiveRecord.self,
            QuizRecord.self, AICall.self,
        ])
        do {
            return try ModelContainer(for: schema)
        } catch {
            // A store written by an older schema cannot be opened, and CI only
            // ever launches on a clean simulator, so this never shows up before
            // a device does. Progress is rebuildable and the alternative is a
            // crash loop the learner can only escape by reinstalling.
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            for path in [url, url.appendingPathExtension("shm"), url.appendingPathExtension("wal")] {
                try? FileManager.default.removeItem(at: path)
            }
            do {
                return try ModelContainer(for: schema)
            } catch {
                fatalError("Could not open the local store after resetting it: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if let catalog {
                    RootView()
                        .environment(\.catalog, catalog)
                } else if let loadError {
                    // Previously a dead end: unstyled red text with no way out.
                    VStack(spacing: 16) {
                        Text(loadError)
                            .font(Theme.body)
                            .foregroundStyle(Theme.negative)
                            .multilineTextAlignment(.center)
                        Button("Try again") { self.loadError = nil }
                            .buttonStyle(.glassProminent)
                    }
                    .padding(Theme.gutter)
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .environment(settings)
            .environment(mastery)
            .screenBackground()
            .task(id: loadError == nil) {
                guard catalog == nil else { return }
                mastery.reload(from: container.mainContext)
                do { catalog = try WordCatalog.bundled() }
                catch { loadError = "Could not load the word list: \(error)" }
            }
        }
        .modelContainer(container)
    }
}

private struct CatalogKey: EnvironmentKey {
    // Replaced with the real catalog once it loads; empty is a safe placeholder.
    static let defaultValue: WordCatalog = .empty
}

extension EnvironmentValues {
    var catalog: WordCatalog {
        get { self[CatalogKey.self] }
        set { self[CatalogKey.self] = newValue }
    }
}
