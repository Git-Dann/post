import SwiftUI
import SwiftData
import PostKit

@main
struct PostApp: App {
    /// Shared SwiftData container. Stored with complete file protection so projects are
    /// encrypted at rest — privacy and security are first-class here.
    let modelContainer: ModelContainer

    init() {
        do {
            let config = ModelConfiguration(
                "Post",
                schema: Schema([Project.self]),
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(for: Project.self, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            GalleryView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(modelContainer)
    }
}
