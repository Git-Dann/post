import Foundation
import SwiftData

/// A re-editable project: the non-destructive recipe is stored as encoded `EditState` JSON, and the
/// original image lives either on disk (in the shared App Group container, `originalFileName`) or —
/// when iCloud sync is enabled — inside the store as an external-storage blob (`originalData`, which
/// SwiftData mirrors to a CKAsset). Lives in PostKit so the app and both extensions share one model.
///
/// Every property is optional or carries an inline default so the schema is CloudKit-compatible
/// (CloudKit forbids required attributes and unique constraints). All changes here are additive, so
/// existing local stores migrate with SwiftData's lightweight path.
@Model
public final class Project {
    public var id: UUID = UUID()
    public var createdAt: Date = Date.now
    public var modifiedAt: Date = Date.now

    /// File name (within the originals directory) of the source image. Empty when the original is
    /// kept in-store (`originalData`) instead — see `ProjectStore.originalData(for:)`.
    public var originalFileName: String = ""

    /// The source photo's display name (e.g. "IMG_1234.HEIC"), when the import gave us one — used to
    /// name exports nicely ("Edited IMG_1234"). `nil` for picker imports that carry no name.
    public var originalName: String?

    /// Original image bytes stored inside the model (external storage). Used when iCloud sync is on
    /// so the original rides along as a CKAsset; `nil` for disk-backed (sync-off) projects.
    @Attribute(.externalStorage) public var originalData: Data?

    /// Encoded `EditState` recipe (kept as `Data` so the model stays decoupled and migrates cleanly).
    public var recipeData: Data = Data()

    /// Small JPEG thumbnail for the gallery grid.
    @Attribute(.externalStorage) public var thumbnailData: Data?

    public init(
        id: UUID = UUID(),
        originalFileName: String = "",
        originalData: Data? = nil,
        originalName: String? = nil,
        recipeData: Data = Data(),
        thumbnailData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.originalData = originalData
        self.originalName = originalName
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
