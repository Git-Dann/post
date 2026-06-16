import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import CoreGraphics

/// Decodes image data into Core Image, handling orientation and producing a downscaled
/// preview for interactive editing. Orientation is baked in exactly once, here, so the rest
/// of the pipeline treats every image as upright.
public enum ImageLoader {

    /// A loaded image: the full-resolution oriented source plus a downscaled preview that the
    /// live editor scrubs against, and the source's metadata (preserved for export).
    public nonisolated struct Loaded: Sendable {
        public let preview: CIImage
        public let pixelSize: CGSize     // full-resolution pixel size (after orientation)
        public let previewScale: CGFloat // preview edge ÷ full edge (≤ 1)

        public init(preview: CIImage, pixelSize: CGSize, previewScale: CGFloat) {
            self.preview = preview
            self.pixelSize = pixelSize
            self.previewScale = previewScale
        }
    }

    /// Full-resolution, orientation-applied `CIImage` from encoded data (HEIC/JPEG/PNG…).
    public static nonisolated func fullImage(from data: Data) -> CIImage? {
        CIImage(data: data, options: [.applyOrientationProperty: true])
    }

    /// Build a downscaled preview whose longest edge is ~`maxEdge` points × scale, for fast,
    /// flicker-free scrubbing. The full-res original is re-rendered only on export.
    public static nonisolated func makeLoaded(from data: Data, maxPreviewEdge: CGFloat = 2048) -> Loaded? {
        guard let full = fullImage(from: data) else { return nil }
        let extent = full.extent
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty else { return nil }

        let longest = max(extent.width, extent.height)
        let scale = longest > maxPreviewEdge ? maxPreviewEdge / longest : 1

        let preview: CIImage
        if scale < 1 {
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = full
            lanczos.scale = Float(scale)
            lanczos.aspectRatio = 1
            preview = (lanczos.outputImage ?? full)
                .transformed(by: CGAffineTransform(translationX: -extent.origin.x * scale,
                                                   y: -extent.origin.y * scale))
        } else {
            preview = full.transformed(by: CGAffineTransform(translationX: -extent.origin.x,
                                                             y: -extent.origin.y))
        }

        return Loaded(
            preview: preview,
            pixelSize: CGSize(width: extent.width, height: extent.height),
            previewScale: scale
        )
    }

    /// Source image properties (EXIF/TIFF/GPS) for re-attachment on export.
    public static nonisolated func properties(from data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return [:]
        }
        return props
    }
}
