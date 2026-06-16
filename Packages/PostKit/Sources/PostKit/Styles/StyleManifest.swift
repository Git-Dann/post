import Foundation

/// A named one-tap look. The look *is* an `EditState` recipe, so applying a style and then
/// fine-tuning on the dials is the same code path — and styles are pure data, so new looks can
/// ship later via a remote manifest without an app update.
public nonisolated struct Style: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let recipe: EditState

    public init(id: String, name: String, recipe: EditState) {
        self.id = id
        self.name = name
        self.recipe = recipe
    }
}

/// The versioned collection of styles, decoded from `styles.json` (bundled) or, later, a remote feed.
public nonisolated struct StyleManifest: Codable, Sendable {
    public let version: Int
    public let styles: [Style]

    public init(version: Int, styles: [Style]) {
        self.version = version
        self.styles = styles
    }
}
