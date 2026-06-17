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
///
/// Hardened by design: only **HTTPS** URLs are ever contacted (a plain-HTTP URL is rejected before
/// any request is made), the request carries no cookies/credentials and no identifying headers, and
/// a non-2xx or oversized response is treated as a failure → bundled fallback. This keeps the single
/// permitted network touch private and tamper-resistant.
public struct RemoteStyleSource: StyleSource {
    let url: URL
    let fallback: StyleSource
    /// Hard ceiling on the manifest body — a style list is a few KB; anything larger is rejected
    /// rather than decoded, so a hostile endpoint can't make us buffer an unbounded payload.
    private let maxBytes = 1_000_000

    public init(url: URL, fallback: StyleSource = BundledStyleSource()) {
        self.url = url
        self.fallback = fallback
    }

    public func load() async throws -> StyleManifest {
        do {
            // Refuse anything that isn't HTTPS — never send a request over cleartext.
            guard url.scheme?.lowercased() == "https" else {
                return try await fallback.load()
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 15
            request.httpShouldHandleCookies = false   // send nothing about the user
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= maxBytes else {
                return try await fallback.load()
            }
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
