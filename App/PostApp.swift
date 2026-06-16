import SwiftUI
import SwiftData
import PostKit

@main
struct PostApp: App {
    /// Shared SwiftData container in the App Group container — the same store the Share and Photos
    /// extensions write to, so edits made there appear in the library. File-protected at rest.
    let modelContainer = ProjectStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            GalleryView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(modelContainer)
    }
}
