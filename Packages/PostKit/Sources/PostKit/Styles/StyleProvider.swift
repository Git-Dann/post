import Foundation
import Observation

/// Where styles come from. Bundled today; the `RemoteStyleSource` seam lets us push new looks
/// later — a read-only download of a manifest, never an upload, so privacy is preserved.
public protocol StyleSource: Sendable {
    func load() async throws -> StyleManifest
}

/// Loads the looks shipped inside the app. Always available, fully offline.
public struct BundledStyleSource: StyleSource {
    public init() {}

    public func load() async throws -> StyleManifest {
        guard let url = Bundle.module.url(forResource: "styles", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StyleManifest.self, from: data)
    }
}

/// Read-only remote manifest fetch (future use). Downloads looks; sends nothing about the user.
/// Falls back to bundled styles on any failure so the app is never blocked by the network.
public struct RemoteStyleSource: StyleSource {
    let url: URL
    let fallback: StyleSource

    public init(url: URL, fallback: StyleSource = BundledStyleSource()) {
        self.url = url
        self.fallback = fallback
    }

    public func load() async throws -> StyleManifest {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(StyleManifest.self, from: data)
        } catch {
            return try await fallback.load()
        }
    }
}

/// Observable holder the UI binds to. Defaults to bundled styles.
@Observable
public final class StyleProvider {
    public private(set) var styles: [Style] = []
    private let source: StyleSource

    public init(source: StyleSource = BundledStyleSource()) {
        self.source = source
    }

    public func loadIfNeeded() async {
        guard styles.isEmpty else { return }
        do {
            styles = try await source.load().styles
        } catch {
            styles = []
        }
    }
}
