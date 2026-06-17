import CoreImage
import Vision

/// On-device foreground/subject segmentation for selective edits. Wraps Vision's
/// `VNGenerateForegroundInstanceMaskRequest` (iOS 17+) and returns a grayscale `CIImage` mask —
/// white where the subject(s) are, black elsewhere — scaled to the source's pixel extent so it
/// aligns 1:1 with the geometry the pipeline applies. Nothing leaves the device.
public enum SubjectMask {

    /// Generate a combined mask for every detected foreground subject. Returns `nil` when Vision
    /// finds no subject (e.g. a flat landscape) — callers then fall back to a whole-photo edit.
    ///
    /// Marked `nonisolated` and synchronous: it does real work, so call it off the main actor
    /// (inside a `Task.detached` or the export actor), never on a scroll.
    public nonisolated static func foregroundMask(for source: CIImage) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: source, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
        do {
            let buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances,
                                                               from: handler)
            let mask = CIImage(cvPixelBuffer: buffer)
            // Vision scales the mask to the source pixels; re-fit defensively so a rounding
            // difference can't misalign the composite.
            guard source.extent.width > 0, source.extent.height > 0,
                  mask.extent.width > 0, mask.extent.height > 0 else { return mask }
            let sx = source.extent.width / mask.extent.width
            let sy = source.extent.height / mask.extent.height
            if abs(sx - 1) < 0.001 && abs(sy - 1) < 0.001 { return mask }
            return mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        } catch {
            return nil
        }
    }
}
