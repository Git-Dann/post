import Foundation
import SwiftData
import PostKit

/// Bridges SwiftData projects, on-disk originals, and the engine's `EditState` recipe.
@MainActor
enum ProjectStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Persist a freshly imported image: write the original to disk and create the project record.
    @discardableResult
    static func create(
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

    /// Save the latest recipe and thumbnail for a project.
    static func update(
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

    static func recipe(for project: Project) -> EditState {
        (try? decoder.decode(EditState.self, from: project.recipeData)) ?? EditState()
    }

    static func delete(_ project: Project, in context: ModelContext) {
        Storage.deleteOriginal(fileName: project.originalFileName)
        context.delete(project)
        try? context.save()
    }
}
