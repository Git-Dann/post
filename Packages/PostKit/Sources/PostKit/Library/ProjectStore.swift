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
    ///
    /// When iCloud sync is enabled we open the *same* store file with a private CloudKit database so
    /// projects mirror across the user's devices. If that fails — e.g. the entitlement isn't
    /// provisioned yet — we fall back to the local on-disk store so the library stays fully intact
    /// (sync simply doesn't start). Sync is opt-in and off by default.
    public static func makeContainer() -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        Storage.ensureDirectories()

        if SyncPrefs.iCloudEnabled {
            let cloudConfig = ModelConfiguration(
                url: Storage.storeURL,
                cloudKitDatabase: .private(SyncPrefs.cloudContainerID)
            )
            if let cloud = try? ModelContainer(for: Project.self, configurations: cloudConfig) {
                Storage.protectStoreFiles()
                cachedContainer = cloud
                return cloud
            }
            // CloudKit unavailable (entitlement not provisioned / signed out) — keep data local.
        }

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

    /// The original image bytes for a project, wherever they live: in-store (`originalData`, used
    /// when syncing) or on disk (`originalFileName`, the disk-backed default). One accessor so every
    /// caller is agnostic to the storage location.
    public static func originalData(for project: Project) -> Data? {
        if let data = project.originalData { return data }
        guard !project.originalFileName.isEmpty else { return nil }
        return Storage.readOriginal(fileName: project.originalFileName)
    }

    /// One-time, non-destructive: pull any disk-backed originals into the store so iCloud can sync
    /// them (the on-disk file is kept as a local backstop). Safe to call repeatedly; run when the
    /// user enables sync. Returns how many projects were migrated.
    @discardableResult
    public static func migrateOriginalsIntoStore(in context: ModelContext) -> Int {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var migrated = 0
        for project in projects where project.originalData == nil && !project.originalFileName.isEmpty {
            if let data = Storage.readOriginal(fileName: project.originalFileName) {
                project.originalData = data
                migrated += 1
            }
        }
        if migrated > 0 { try? context.save() }
        return migrated
    }

    /// Persist a freshly imported/edited image: write the original to disk and create the record.
    @discardableResult
    public static func create(
        originalData: Data,
        state: EditState,
        thumbnail: Data?,
        originalName: String? = nil,
        in context: ModelContext
    ) -> Project? {
        let id = UUID()
        let project: Project

        if SyncPrefs.iCloudEnabled {
            // Syncing: keep the original inside the store so it mirrors to iCloud as a CKAsset.
            project = Project(
                id: id,
                originalData: originalData,
                originalName: originalName,
                recipeData: (try? encoder.encode(state)) ?? Data(),
                thumbnailData: thumbnail
            )
            context.insert(project)
            guard (try? context.save()) != nil else { context.delete(project); return nil }
            return project
        }

        // Local (default): original on disk in the App Group container.
        let fileName = "\(id.uuidString).img"
        do {
            try Storage.writeOriginal(originalData, fileName: fileName)
        } catch {
            return nil
        }
        project = Project(
            id: id,
            originalFileName: fileName,
            originalName: originalName,
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
        if !project.originalFileName.isEmpty {
            Storage.deleteOriginal(fileName: project.originalFileName)  // in-store originals go with the model
        }
        context.delete(project)
        return (try? context.save()) != nil
    }
}
