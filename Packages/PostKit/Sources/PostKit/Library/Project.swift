import Foundation
import SwiftData

/// A re-editable project: the original image lives on disk (in the shared App Group container),
/// and the non-destructive recipe is stored as encoded `EditState` JSON. Lives in PostKit so the
/// app and both extensions share one persistence model.
@Model
public final class Project {
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date

    /// File name (within the originals directory) of the source image.
    public var originalFileName: String

    /// Encoded `EditState` recipe (kept as `Data` so the model stays decoupled and migrates cleanly).
    public var recipeData: Data

    /// Small JPEG thumbnail for the gallery grid.
    @Attribute(.externalStorage) public var thumbnailData: Data?

    public init(
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

    /// Whether the saved recipe carries any actual adjustment — drives the "edited" badge in the
    /// gallery. (Transient/computed, not persisted.)
    public var isEdited: Bool {
        guard !recipeData.isEmpty,
              let state = try? JSONDecoder().decode(EditState.self, from: recipeData)
        else { return false }
        return !state.isIdentity
    }
}
