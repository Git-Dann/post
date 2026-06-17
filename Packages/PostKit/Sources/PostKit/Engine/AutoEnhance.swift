import CoreImage
import CoreImage.CIFilterBuiltins

/// Computes a one-tap "Auto" target from on-device image analysis — no ML, no network. Returns an
/// `EditState` with the adjustments Auto controls (exposure, white balance, plus a gentle pop); the
/// editor blends 0→this with the Auto dial, and the resulting values are real fields the other dials
/// can then refine.
public enum AutoEnhance {

    /// The fields Auto drives, so the editor knows which to scale by the dial's strength.
    public static func apply(_ target: EditState, strength: Double, to state: inout EditState) {
        let s = min(max(strength, 0), 1)
        state.exposure = s * target.exposure
        state.contrast = s * target.contrast
        state.warmth = s * target.warmth
        state.vibrance = s * target.vibrance
    }

    /// Analyse the image's average tone & colour and derive a flattering target.
    public static func target(for image: CIImage, context: CIContext) -> EditState {
        var t = EditState()
        let extent = image.extent
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty else { return t }

        let avg = CIFilter.areaAverage()
        avg.inputImage = image
        avg.extent = extent
        guard let out = avg.outputImage else { return t }

        var px = [UInt8](repeating: 0, count: 4)
        context.render(out, toBitmap: &px, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let r = Double(px[0]) / 255, g = Double(px[1]) / 255, b = Double(px[2]) / 255
        let luma = 0.299 * r + 0.587 * g + 0.114 * b

        // Exposure: lift (or pull) the average toward a pleasant mid-tone, clamped to stay natural.
        t.exposure = min(max((0.46 - luma) * 1.4, -0.5), 0.5)
        // Gray-world white balance: nudge a colour cast back toward neutral. A warm image (r > b)
        // gets cooled and vice-versa. (Sign matches FilterPipeline.applyWhiteBalance.)
        t.warmth = min(max((b - r) * 1.1, -0.35), 0.35)
        // A gentle, broadly-flattering pop.
        t.contrast = 0.12
        t.vibrance = 0.15
        return t
    }
}
