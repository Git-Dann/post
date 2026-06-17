import Foundation

/// Persists the user's saved looks as Codable JSON in the App Group container (so they can later
/// ride iCloud sync alongside the project library). A saved look is just a `Style` whose recipe is
/// the captured `EditState` — same type as the bundled looks. (MainActor — only the StyleProvider
/// touches it.)
public enum UserStyleStore {
    /// Collection name that groups user looks into the "Yours" section of the styles strip.
    public static let collection = "Yours"

    private static var url: URL { Storage.baseDirectory.appendingPathComponent("UserStyles.json") }

    public static func load() -> [Style] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Style].self, from: data)) ?? []
    }

    public static func save(_ styles: [Style]) {
        Storage.ensureDirectories()
        guard let data = try? JSONEncoder().encode(styles) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
