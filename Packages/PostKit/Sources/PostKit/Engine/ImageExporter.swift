import CoreImage
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

        var utType: UTType { self == .heic ? .heic : .jpeg }
        var ciFormat: CIFormat { self == .heic ? .RGBA16 : .RGBA8 }
    }

    public enum ExportError: Error { case decodeFailed, renderFailed, encodeFailed }

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

    /// Render `imageData` through `state` at full resolution and encode to `format`.
    public func export(
        imageData: Data,
        state: EditState,
        format: Format = .heic,
        quality: Double = 0.92,
        stripLocation: Bool = false
    ) throws -> Data {
        guard let source = ImageLoader.fullImage(from: imageData) else {
            throw ExportError.decodeFailed
        }

        // Full resolution → native grain (grainScale 1).
        let output = FilterPipeline.makeImage(source: source, state: state, grainScale: 1)
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
