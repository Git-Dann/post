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

public extension Style {
    /// The original, untouched image — a no-op recipe (geometry is kept; tone/colour/film cleared).
    static let original = Style(id: "og", name: "OG", recipe: EditState())

    /// A flat "Process Zero" baseline: Apple's punchy computational look (contrast, vibrancy, HDR
    /// lift) pulled back toward a more natural, film-like starting point you can build from.
    static let processZero: Style = {
        var recipe = EditState()
        recipe.contrast = -0.18
        recipe.saturation = -0.12
        recipe.fade = 0.10
        return Style(id: "zero", name: "ZERO", recipe: recipe)
    }()

    /// The two baselines shown before the divider in the styles picker.
    static let baselines: [Style] = [.original, .processZero]
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
