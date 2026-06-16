import Foundation
import SwiftData

/// Bridges SwiftData projects, on-disk originals, and the engine's `EditState` recipe. Shared by
/// the app (gallery) and the extensions (which persist new projects into the same store).
@MainActor
public enum ProjectStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Builds (or opens) the shared SwiftData container in the App Group container.
    public static func makeContainer() -> ModelContainer {
        Storage.ensureDirectories()
        do {
            let config = ModelConfiguration(url: Storage.storeURL)
            return try ModelContainer(for: Project.self, configurations: config)
        } catch {
            // Last-resort fallback so the app never fails to launch.
            return try! ModelContainer(for: Project.self)
        }
    }

    /// Persist a freshly imported/edited image: write the original to disk and create the record.
    @discardableResult
    public static func create(
        originalData: Data,
        state: EditState,
        thumbnail: Data?,
        in context: ModelContext
    ) -> Project? {
        let id = UUID()
        let fileName = "\(id.uuidString).img"
        do {
            try Storage.writeOriginal(originalData, fileName: fileName)
        } catch {
            return nil
        }
        let project = Project(
            id: id,
            originalFileName: fileName,
            recipeData: (try? encoder.encode(state)) ?? Data(),
            thumbnailData: thumbnail
        )
        context.insert(project)
        try? context.save()
        return project
    }

    public static func update(
        _ project: Project,
        state: EditState,
        thumbnail: Data?,
        in context: ModelContext
    ) {
        if let encoded = try? encoder.encode(state) {
            project.recipeData = encoded
        }
        if let thumbnail {
            project.thumbnailData = thumbnail
        }
        project.modifiedAt = .now
        try? context.save()
    }

    public static func recipe(for project: Project) -> EditState {
        (try? decoder.decode(EditState.self, from: project.recipeData)) ?? EditState()
    }

    public static func delete(_ project: Project, in context: ModelContext) {
        Storage.deleteOriginal(fileName: project.originalFileName)
        context.delete(project)
        try? context.save()
    }
}
