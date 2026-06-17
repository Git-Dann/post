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

        // 90° turns + flips — no empty space introduced.
        if s.rotationQuarterTurns != 0 || s.flippedHorizontally || s.flippedVertically {
            let c = CGPoint(x: img.extent.midX, y: img.extent.midY)
            let t = CGAffineTransform.identity
                .translatedBy(x: c.x, y: c.y)
                .rotated(by: Double(s.rotationQuarterTurns) * .pi / 2)
                .scaledBy(x: s.flippedHorizontally ? -1 : 1, y: s.flippedVertically ? -1 : 1)
                .translatedBy(x: -c.x, y: -c.y)
            img = img.transformed(by: t)
        }

        // Straighten: rotate AND zoom-to-fill so the frame stays full of image (no empty corners),
        // then crop back to the frame — matches Photos' straighten behaviour.
        if s.straightenAngle != 0 {
            let frame = img.extent
            let c = CGPoint(x: frame.midX, y: frame.midY)
            let a = s.straightenAngle
            // Smallest scale that keeps the rotated frame covering the original frame.
            let zoom = (abs(cos(a)) + abs(sin(a)) * max(frame.width / frame.height, frame.height / frame.width)) * 1.003
            let t = CGAffineTransform.identity
                .translatedBy(x: c.x, y: c.y)
                .rotated(by: -a)
                .scaledBy(x: zoom, y: zoom)
                .translatedBy(x: -c.x, y: -c.y)
            img = img.transformed(by: t).cropped(to: frame)
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

    // MARK: Grain (Core Image Metal kernel — see Shaders/Grain.metal)

    /// Loaded once from the host bundle's metallib.
    private static nonisolated let grainKernel: CIColorKernel? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CIColorKernel(functionName: "postGrain", fromMetalLibraryData: data)
    }()

    static nonisolated func applyGrain(_ base: CIImage, amount: Double, grainScale: CGFloat) -> CIImage {
        guard amount > 0, let kernel = grainKernel else { return base }
        let extent = base.extent
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty else { return base }

        // Grain feel — tune here. `strength` = overall intensity; `size` = noise cell size in px,
        // where SMALLER = finer, less "thick" grain. (Was 0.22 / 1.4 — dialled finer + lighter.)
        let strength = Float(min(max(amount, 0), 1) * 0.14)
        let size = Float(0.8 * grainScale)                    // finer cells; grainScale matches preview↔export
        return kernel.apply(extent: extent, arguments: [base, strength, size]) ?? base
    }
}
