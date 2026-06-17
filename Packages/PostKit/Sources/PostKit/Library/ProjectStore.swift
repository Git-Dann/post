import Foundation
import SwiftData

/// Bridges SwiftData projects, on-disk originals, and the engine's `EditState` recipe. Shared by
/// the app (gallery) and the extensions (which persist new projects into the same store).
@MainActor
public enum ProjectStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static var cachedContainer: ModelContainer?

    /// The shared SwiftData container in the App Group container. Cached per process so the app and
    /// each extension open the store at most once (avoids same-process double-open lock contention).
    public static func makeContainer() -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        Storage.ensureDirectories()
        let container: ModelContainer
        do {
            let config = ModelConfiguration(url: Storage.storeURL)
            container = try ModelContainer(for: Project.self, configurations: config)
            Storage.protectStoreFiles()
        } catch {
            // Degrade to an in-memory store rather than crashing on a corrupt/locked on-disk store
            // (in-memory creation is effectively infallible, so we never trap a real device).
            let mem = ModelConfiguration(isStoredInMemoryOnly: true)
            container = (try? ModelContainer(for: Project.self, configurations: mem))
                ?? { fatalError("Unable to create even an in-memory ModelContainer: \(error)") }()
        }
        cachedContainer = container
        return container
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
        do {
            try context.save()
        } catch {
            // Roll back so a failed save doesn't leave an orphaned original on disk.
            context.delete(project)
            Storage.deleteOriginal(fileName: fileName)
            return nil
        }
        return project
    }

    @discardableResult
    public static func update(
        _ project: Project,
        state: EditState,
        thumbnail: Data?,
        in context: ModelContext
    ) -> Bool {
        if let encoded = try? encoder.encode(state) {
            project.recipeData = encoded
        }
        if let thumbnail {
            project.thumbnailData = thumbnail
        }
        project.modifiedAt = .now
        return (try? context.save()) != nil
    }

    public static func recipe(for project: Project) -> EditState {
        (try? decoder.decode(EditState.self, from: project.recipeData)) ?? EditState()
    }

    @discardableResult
    public static func delete(_ project: Project, in context: ModelContext) -> Bool {
        Storage.deleteOriginal(fileName: project.originalFileName)
        context.delete(project)
        return (try? context.save()) != nil
    }
}
