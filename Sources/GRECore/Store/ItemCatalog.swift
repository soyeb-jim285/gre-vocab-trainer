import Foundation

/// The bundled GRE questions, indexed by the words they test.
public struct ItemCatalog: Sendable {

    public static let empty = ItemCatalog(items: [])

    public let items: [GREItem]
    private let byID: [String: GREItem]
    private let byWord: [String: [GREItem]]

    public init(items: [GREItem]) {
        self.items = items
        self.byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.byWord = Dictionary(
            grouping: items.flatMap { item in item.testedWordIDs.map { ($0, item) } },
            by: \.0
        ).mapValues { $0.map(\.1) }
    }

    /// Load the questions shipped inside GRECore.
    ///
    /// Missing is not an error: the dataset is written in passes, and a build
    /// without questions yet is a build with the drill screen empty rather than
    /// a build that will not start.
    public static func bundled() throws -> ItemCatalog {
        guard let url = Bundle.module.url(forResource: "items", withExtension: "json") else {
            return .empty
        }
        return ItemCatalog(items: try JSONDecoder().decode([GREItem].self, from: Data(contentsOf: url)))
    }

    public subscript(id: String) -> GREItem? { byID[id] }

    /// Questions whose answer is this word.
    public func items(testing wordID: String) -> [GREItem] { byWord[wordID] ?? [] }

    public func items(ofKind kind: GREItem.Kind) -> [GREItem] {
        items.filter { $0.kind == kind }
    }
}
