import SwiftUI
import SwiftData
import PostKit

@main
struct PostApp: App {
    /// Shared SwiftData container in the App Group container — the same store the Share and Photos
    /// extensions write to, so edits made there appear in the library. File-protected at rest.
    let modelContainer = ProjectStore.makeContainer()

    /// Receives MetricKit performance + crash diagnostics, stored on device only (no upload).
    private let metrics = MetricsMonitor()

    /// Drives a live re-tint of the whole tree when the accent is changed in Settings.
    @AppStorage(AccentChoice.storageKey) private var accentRaw = AccentChoice.amber.rawValue

    var body: some Scene {
        WindowGroup {
            GalleryView()
                .preferredColorScheme(.dark)
                .tint((AccentChoice(rawValue: accentRaw) ?? .amber).color)
        }
        .modelContainer(modelContainer)
    }
}
