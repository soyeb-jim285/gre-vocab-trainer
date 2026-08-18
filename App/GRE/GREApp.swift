import GRECore
import SwiftData
import SwiftUI

@main
struct GREApp: App {
    @State private var settings = AppSettings()
    @State private var catalog: WordCatalog?
    @State private var loadError: String?

    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: CardRecord.self, ReviewRecord.self, DeepDiveRecord.self)
        } catch {
            fatalError("Could not open the local store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if let catalog {
                    RootView()
                        .environment(\.catalog, catalog)
                } else if let loadError {
                    Text(loadError)
                        .font(Theme.body)
                        .foregroundStyle(Theme.negative)
                        .padding()
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .environment(settings)
            .preferredColorScheme(.dark)
            .screenBackground()
            .task {
                guard catalog == nil else { return }
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
