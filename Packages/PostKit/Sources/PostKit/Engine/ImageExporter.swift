import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import Metal
import CoreGraphics

/// Renders the full-resolution result off the main thread. Takes encoded `Data` (Sendable) and
/// an `EditState` (Sendable) — never a `CIImage` — so nothing non-Sendable crosses the actor
/// boundary. EXIF/GPS metadata is preserved; orientation is reset to "up" because the pipeline
/// already baked it into pixels.
public actor ImageExporter {

    public enum Format: Sendable {
        case heic
        case jpeg

        public var utType: UTType { self == .heic ? .heic : .jpeg }
        // HEIC renders at 16-bit (10-bit-capable container) — a deliberate quality choice: fades and
        // grain band visibly at 8-bit. The wider intermediate costs transient memory on very large
        // photos, but it's a single image rendered off-main and released right after encode. JPEG is
        // 8-bit (its own ceiling), so there's nothing to gain there.
        var ciFormat: CIFormat { self == .heic ? .RGBA16 : .RGBA8 }
        public var fileExtension: String { self == .heic ? "heic" : "jpg" }
    }

    public enum ExportError: Error { case decodeFailed, renderFailed, encodeFailed }

    /// A friendly export filename: "Edited <source name>.<ext>", e.g. "Edited IMG_1234.heic".
    /// Falls back to "Edited Photo" when the original carried no usable name.
    public nonisolated static func suggestedFileName(forOriginal original: String?,
                                                     format: Format) -> String {
        let base = (original as NSString?)?.deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (base?.isEmpty == false) ? base! : "Photo"
        return "Edited \(name).\(format.fileExtension)"
    }

    private let ciContext: CIContext
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

    public init() {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
            .highQualityDownsample: true,
            .cacheIntermediates: false
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: options)
        } else {
            ciContext = CIContext(options: options)
        }
    }

    /// Render `imageData` through `state` and encode to `format`. `maxDimension` (longest edge in px,
    /// nil = full resolution) lets share/export presets cap the output size.
    public func export(
        imageData: Data,
        state: EditState,
        format: Format = .heic,
        quality: Double = 0.92,
        stripLocation: Bool = false,
        maxDimension: CGFloat? = nil
    ) throws -> Data {
        // Wrap the whole render+encode in an autorelease pool: a full-res (especially RAW/ProRAW)
        // pipeline allocates large transient CIImage/CGImage backing stores, and this releases them
        // as soon as the call returns instead of at the next run-loop tick — keeps peak memory down
        // when exporting big photos or a batch back-to-back.
        try autoreleasepool {
        guard let source = ImageLoader.fullImage(from: imageData) else {
            throw ExportError.decodeFailed
        }

        // Selective edits: recompute the subject mask at full resolution so the export matches the
        // preview exactly (the cached preview mask is downscaled). On-device, nothing leaves here.
        let mask = state.scope.isRegional ? SubjectMask.foregroundMask(for: source) : nil

        // Full resolution → native grain (grainScale 1).
        var output = FilterPipeline.makeImage(source: source, state: state, grainScale: 1, mask: mask)
        // Optional resize for export presets (web/medium). High-quality Lanczos.
        if let maxDimension {
            let longest = max(output.extent.width, output.extent.height)
            if longest > maxDimension {
                let f = CIFilter.lanczosScaleTransform()
                f.inputImage = output
                f.scale = Float(maxDimension / longest)
                f.aspectRatio = 1
                output = f.outputImage ?? output
            }
        }
        guard let cgImage = ciContext.createCGImage(
            output,
            from: output.extent,
            format: format.ciFormat,
            colorSpace: outputColorSpace
        ) else {
            throw ExportError.renderFailed
        }

        // Preserve source metadata; reset orientation (pixels already upright).
        var properties = ImageLoader.properties(from: imageData)
        properties[kCGImagePropertyOrientation as String] = 1
        properties[kCGImageDestinationLossyCompressionQuality as String] = quality
        if stripLocation {
            // Remove every block that can carry location, not just GPS: IPTC location names and the
            // Apple maker-note (which encodes location-derived data) too.
            properties[kCGImagePropertyGPSDictionary as String] = nil
            properties[kCGImagePropertyIPTCDictionary as String] = nil
            properties[kCGImagePropertyMakerAppleDictionary as String] = nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportError.encodeFailed
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.encodeFailed
        }
        return data as Data
        }
    }
}
