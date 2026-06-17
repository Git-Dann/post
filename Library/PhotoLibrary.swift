import Photos
import UIKit

/// Thin wrapper over the Photos framework for the in-app library browser.
///
/// Everything here is on-device: it reads thumbnails and image data straight from the user's
/// library and never uploads anything. Used only when the user has granted full or limited access;
/// otherwise the app falls back to the out-of-process system picker (no permission needed).
@MainActor
enum PhotoLibrary {

    static var status: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    /// True when the in-app browser can read assets (full or limited selection).
    static var hasAccess: Bool { status == .authorized || status == .limited }

    @discardableResult
    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// The lazy fetch result of all image assets, newest first.
    ///
    /// `PHFetchResult` is database-backed: it loads each `PHAsset` only when indexed (`object(at:)`),
    /// so the grid drives straight off it and we never materialize a 50k-element array on the main
    /// actor (which is what made a large library hitch on open). The call itself just compiles the
    /// query and touches no image data. (PHFetchResult/PHAsset aren't Sendable, so this stays on the
    /// main actor — but it's now cheap.)
    static func fetchImageResult() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    /// The asset's original filename (e.g. "IMG_1234.HEIC"), so edits exported from the in-app
    /// browser can be named after the source photo. Reads the asset's resource metadata on-device.
    static func originalFilename(for asset: PHAsset) -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        return (resources.first { $0.type == .photo } ?? resources.first)?.originalFilename
    }

    /// Resolve a handful of selected identifiers back to assets (preserving the user's tap order).
    /// Fetches only the chosen assets — never the whole library.
    static func assets(withIdentifiers ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var map: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in map[asset.localIdentifier] = asset }
        return ids.compactMap { map[$0] }
    }

    // Boxes to carry non-Sendable UIKit/Foundation types across the async continuation cleanly.
    private struct ImageBox: @unchecked Sendable { let image: UIImage? }
    private struct DataBox: @unchecked Sendable { let data: Data? }

    /// A grid thumbnail. `.fastFormat` => a single callback (safe for one continuation resume).
    static func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<ImageBox, Never>) in
            let opt = PHImageRequestOptions()
            opt.deliveryMode = .highQualityFormat   // sharp (fastFormat returns tiny cached thumbs)
            opt.resizeMode = .exact
            opt.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset, targetSize: size, contentMode: .aspectFill, options: opt
            ) { image, _ in cont.resume(returning: ImageBox(image: image)) }
        }.image
    }

    /// Full-resolution encoded data for import. `.highQualityFormat` => a single callback.
    static func fullData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<DataBox, Never>) in
            let opt = PHImageRequestOptions()
            opt.deliveryMode = .highQualityFormat
            opt.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: opt
            ) { data, _, _, _ in cont.resume(returning: DataBox(data: data)) }
        }.data
    }

    /// The album Post files its exports into, so they're grouped (and easy to clear out en masse).
    nonisolated static let albumTitle = "Post"

    /// Save edited image data to Photos. Always lands in the main library (Recents / All Photos);
    /// when full access is granted it's also filed into a "Post" album so the user can find and
    /// manage their edits together. Add-only at minimum — never escalates to full access just to
    /// save (under add-only we can't read existing albums, so we skip the album to avoid duplicates).
    /// Returns false if the user declines or the write fails.
    /// `nonisolated` is essential: `PHPhotoLibrary.performChanges` runs the change/completion blocks
    /// on its OWN background queue. If this method were MainActor-isolated (the enum is), those
    /// closures would inherit MainActor isolation and Swift's runtime executor check would trap
    /// (`dispatch_assert_queue` on com.apple.PHPhotoLibrary.transaction.high). The Photos APIs are
    /// thread-safe, so we run the whole flow off the main actor.
    nonisolated static func save(imageData: Data) async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { return false }

        // Only manage the album when we already have full read-write access.
        let album: PHAssetCollection? = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
            ? await findOrCreateAlbum() : nil
        let box = AlbumBox(album: album)

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: imageData, options: nil)
                if let album = box.album, let placeholder = request.placeholderForCreatedAsset {
                    PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
                }
            } completionHandler: { success, _ in cont.resume(returning: success) }
        }
    }

    nonisolated private struct AlbumBox: @unchecked Sendable { let album: PHAssetCollection? }
    nonisolated private final class IDBox: @unchecked Sendable { var id: String? }

    /// Find the existing "Post" album, or create it. Requires full access (the caller checks).
    /// `nonisolated` for the same reason as `save` — the creation runs on Photos' own queue.
    nonisolated private static func findOrCreateAlbum() async -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumTitle)
        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
        if let album = existing.firstObject { return album }

        let box = IDBox()
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                box.id = request.placeholderForCreatedAssetCollection.localIdentifier
            } completionHandler: { success, _ in cont.resume(returning: success) }
        }
        guard ok, let id = box.id else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// For limited access: let the user add more photos to the selection Post can see.
    static func presentAddMore() {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }
}
