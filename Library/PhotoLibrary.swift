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

    /// Save edited image data into the user's Photos library (Recents / All Photos — not a separate
    /// folder). Add-only: requests just the lightweight "add" permission, never full read access.
    /// Returns false if the user declines or the write fails.
    static func save(imageData: Data) async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: imageData, options: nil)
            } completionHandler: { success, _ in cont.resume(returning: success) }
        }
    }

    /// For limited access: let the user add more photos to the selection Post can see.
    static func presentAddMore() {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }
}
