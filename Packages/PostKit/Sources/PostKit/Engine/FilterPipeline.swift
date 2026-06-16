import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// The single Core Image chain that turns an `EditState` recipe into a rendered `CIImage`.
///
/// This is `nonisolated` and pure: it's called on the main actor for the live preview and
/// inside the export actor for the full-resolution render — one code path, two inputs, so
/// "what you see is what you get". Fixed order of operations, justified inline.
public enum FilterPipeline {

    /// Build the edited image. `grainScale` enlarges grain cells (>1) so film grain reads at the
    /// same density on a downscaled preview as it will at full export resolution.
    public static nonisolated func makeImage(
        source: CIImage,
        state: EditState,
        grainScale: CGFloat = 1
    ) -> CIImage {
        var img = applyGeometry(source, state)   // geometry first → less work downstream
        img = applyColor(img, state)             // contrast/brightness/saturation in one pass
        img = applyHue(img, state)               // hue rotate
        img = applyFade(img, state)              // lifted blacks AFTER color so the lift survives
        img = applyGrain(img, amount: state.grain, grainScale: grainScale) // grain last: overlay on final frame
        return img
    }

    // MARK: Geometry

    static nonisolated func applyGeometry(_ image: CIImage, _ s: EditState) -> CIImage {
        let e0 = image.extent
        guard !e0.isInfinite, !e0.isNull, !e0.isEmpty else { return image }

        var img = image
        let needsTransform = s.straightenAngle != 0 || s.rotationQuarterTurns != 0
            || s.flippedHorizontally || s.flippedVertically
        if needsTransform {
            let center = CGPoint(x: e0.midX, y: e0.midY)
            let t = CGAffineTransform.identity
                .translatedBy(x: center.x, y: center.y)
                .rotated(by: -s.straightenAngle + Double(s.rotationQuarterTurns) * .pi / 2)
                .scaledBy(x: s.flippedHorizontally ? -1 : 1, y: s.flippedVertically ? -1 : 1)
                .translatedBy(x: -center.x, y: -center.y)
            img = img.transformed(by: t)
        }

        if !s.crop.isFull {
            let e = img.extent
            let rect = CGRect(
                x: e.origin.x + s.crop.x * e.width,
                y: e.origin.y + s.crop.y * e.height,
                width: s.crop.width * e.width,
                height: s.crop.height * e.height
            )
            img = img.cropped(to: rect)
        }

        // Re-origin to (0,0) so downstream sizing/exports are clean.
        let o = img.extent.origin
        if o != .zero {
            img = img.transformed(by: CGAffineTransform(translationX: -o.x, y: -o.y))
        }
        return img
    }

    // MARK: Color controls (contrast → brightness → saturation, one filter)

    static nonisolated func applyColor(_ image: CIImage, _ s: EditState) -> CIImage {
        guard s.brightness != 0 || s.contrast != 0 || s.saturation != 0 else { return image }
        let f = CIFilter.colorControls()
        f.inputImage = image
        f.brightness = Float(s.brightness * 0.4)        // additive, kept subtle
        f.contrast = Float(1 + s.contrast * 0.45)       // multiplicative around 1
        f.saturation = Float(max(0, 1 + s.saturation))  // 0 = grayscale, 2 = punchy
        return f.outputImage ?? image
    }

    // MARK: Hue

    static nonisolated func applyHue(_ image: CIImage, _ s: EditState) -> CIImage {
        guard s.hue != 0 else { return image }
        let f = CIFilter.hueAdjust()
        f.inputImage = image
        f.angle = Float(s.hue * .pi)                    // full wheel at ±1
        return f.outputImage ?? image
    }

    // MARK: Fades (faded-film look via a lifted-black tone curve)

    static nonisolated func applyFade(_ image: CIImage, _ s: EditState) -> CIImage {
        guard s.fade > 0 else { return image }
        let d = s.fade
        let f = CIFilter.toneCurve()
        f.inputImage = image
        f.point0 = CGPoint(x: 0.0, y: 0.05 + 0.18 * d)  // lift the blacks — the fade
        f.point1 = CGPoint(x: 0.25, y: 0.25 + 0.10 * d)
        f.point2 = CGPoint(x: 0.5, y: 0.5)              // anchor midtones
        f.point3 = CGPoint(x: 0.75, y: 0.75 - 0.04 * d)
        f.point4 = CGPoint(x: 1.0, y: 0.95 - 0.05 * d)  // milk the highlights
        return f.outputImage ?? image
    }

    // MARK: Grain (no single CIFilter — a composite: noise → mono → intensity → overlay)

    static nonisolated func applyGrain(_ base: CIImage, amount: Double, grainScale: CGFloat) -> CIImage {
        guard amount > 0 else { return base }
        let extent = base.extent
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty,
              let raw = CIFilter.randomGenerator().outputImage else { return base }

        // Luminance → all RGB channels, opaque. CIRandomGenerator is deterministic (no crawl).
        let mono = CIFilter.colorMatrix()
        mono.inputImage = raw
        let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        mono.rVector = luma
        mono.gVector = luma
        mono.bVector = luma
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mono.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        var noise = mono.outputImage ?? raw

        // Scale noise toward neutral 0.5 by `amount`. Overlay-blending flat 0.5 gray is a no-op,
        // so amount == 0 → no change, amount == 1 → full-strength grain. Clean intensity control.
        let amt = CGFloat(min(max(amount, 0), 1))
        let intensity = CIFilter.colorMatrix()
        intensity.inputImage = noise
        intensity.rVector = CIVector(x: amt, y: 0, z: 0, w: 0)
        intensity.gVector = CIVector(x: 0, y: amt, z: 0, w: 0)
        intensity.bVector = CIVector(x: 0, y: 0, z: amt, w: 0)
        intensity.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        let mid = 0.5 * (1 - amt)
        intensity.biasVector = CIVector(x: mid, y: mid, z: mid, w: 1)
        noise = intensity.outputImage ?? noise

        // Coarsen grain cells to match preview/export density.
        if grainScale != 1 {
            noise = noise.transformed(by: CGAffineTransform(scaleX: grainScale, y: grainScale))
        }
        noise = noise.cropped(to: extent)

        let blend = CIFilter.overlayBlendMode()
        blend.backgroundImage = base
        blend.inputImage = noise
        return (blend.outputImage ?? base).cropped(to: extent)
    }
}
