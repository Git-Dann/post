import Foundation
import SwiftData

/// A re-editable project: the original image lives on disk (in the App Group container),
/// and the non-destructive recipe is stored as encoded `EditState` JSON. Reopening a
/// project restores the recipe exactly. Persisted with file protection (see `PostApp`).
@Model
final class Project {
    /// Stable identifier; also used to name the on-disk original.
    var id: UUID
    var createdAt: Date
    var modifiedAt: Date

    /// File name (within the originals directory) of the source image.
    var originalFileName: String

    /// Encoded `EditState` recipe. Stored as `Data` so the model stays decoupled
    /// from the engine module and migrates cleanly.
    var recipeData: Data

    /// Small JPEG thumbnail for the gallery grid.
    @Attribute(.externalStorage) var thumbnailData: Data?

    init(
        id: UUID = UUID(),
        originalFileName: String,
        recipeData: Data = Data(),
        thumbnailData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.recipeData = recipeData
        self.thumbnailData = thumbnailData
        self.createdAt = createdAt
        self.modifiedAt = createdAt
    }
}
