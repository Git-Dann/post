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

    /// All image assets, newest first. (PHAsset isn't Sendable, so this stays on the main actor.)
    static func fetchImageAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    // Boxes to carry non-Sendable UIKit/Foundation types across the async continuation cleanly.
    private struct ImageBox: @unchecked Sendable { let image: UIImage? }
    private struct DataBox: @unchecked Sendable { let data: Data? }

    /// A grid thumbnail. `.fastFormat` => a single callback (safe for one continuation resume).
    static func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<ImageBox, Never>) in
            let opt = PHImageRequestOptions()
            opt.deliveryMode = .fastFormat
            opt.resizeMode = .fast
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

    /// For limited access: let the user add more photos to the selection Post can see.
    static func presentAddMore() {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }
}
