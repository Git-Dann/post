import Foundation

/// A named one-tap look. The look *is* an `EditState` recipe, so applying a style and then
/// fine-tuning on the dials is the same code path — and styles are pure data, so new looks can
/// ship later via a remote manifest without an app update.
public nonisolated struct Style: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let recipe: EditState
    /// Optional attribution for artist styles / collaborations — shown in the editor when set.
    public let artist: String?
    /// Optional pack/collection name (e.g. a collab) for grouping styles. Omitted = house style.
    public let collection: String?

    public init(id: String, name: String, recipe: EditState,
                artist: String? = nil, collection: String? = nil) {
        self.id = id
        self.name = name
        self.recipe = recipe
        self.artist = artist
        self.collection = collection
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
