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
        var img = applyGeometry(source, state)        // geometry first → less work downstream
        img = applyExposure(img, state)               // overall light, like a stop adjustment
        img = applyWhiteBalance(img, state)           // warmth + tint (temperature)
        img = applyHighlightShadow(img, state)        // recover/lift tonal extremes
        img = applyColor(img, state)                  // contrast/brightness/saturation in one pass
        img = applyVibrance(img, state)               // smart saturation after the flat saturation
        img = applyHue(img, state)                    // hue rotate
        img = applyFade(img, state)                   // lifted blacks AFTER color so the lift survives
        img = applySharpen(img, state, grainScale: grainScale)  // crispness on near-final tones
        img = applyVignette(img, state)               // darken the edges of the finished frame
        img = applyGrain(img, amount: state.grain, grainScale: grainScale) // grain last: overlay on final
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

    // MARK: Exposure (photographic stops, distinct from additive brightness)

    static nonisolated func applyExposure(_ image: CIImage, _ s: EditState) -> CIImage {
        guard s.exposure != 0 else { return image }
        let f = CIFilter.exposureAdjust()
        f.inputImage = image
        f.ev = Float(s.exposure * 1.5)                  // ±1.5 stops at the extremes
        return f.outputImage ?? image
    }

    // MARK: White balance (warmth + tint)

    static nonisolated func applyWhiteBalance(_ image: CIImage, _ s: EditState) -> CIImage {
        guard s.warmth != 0 || s.tint != 0 else { return image }
        let f = CIFilter.temperatureAndTint()
        f.inputImage = image
        // Treat the source white as daylight (6500K) and remap it: a LOWER target temperature warms
        // the image toward amber, higher cools it toward blue; the tint axis runs green↔magenta.
        // (Hand-tuned magnitudes; flip a sign if a direction reads inverted on a real photo.)
        f.neutral = CIVector(x: 6500, y: 0)
        f.targetNeutral = CIVector(x: 6500 - s.warmth * 2500, y: -s.tint * 50)
        return f.outputImage ?? image
    }

    // MARK: Highlights & shadows (bipolar tonal recovery via a tone curve)

    static nonisolated func applyHighlightShadow(_ image: CIImage, _ s: EditState) -> CIImage {
        guard s.highlights != 0 || s.shadows != 0 else { return image }
        // A pivoted tone curve: lift/deepen the low quarter (shadows) and the high quarter
        // (highlights) while pinning the black/white points (0,0)/(1,1) and the midtone anchor — so
        // it's fully bipolar and doesn't clip, unlike highlightShadowAdjust's one-sided highlight.
        let sh = s.shadows * 0.18
        let hi = s.highlights * 0.18
        let f = CIFilter.toneCurve()
        f.inputImage = image
        f.point0 = CGPoint(x: 0.0, y: 0.0)
        f.point1 = CGPoint(x: 0.25, y: 0.25 + sh)
        f.point2 = CGPoint(x: 0.5, y: 0.5)
        f.point3 = CGPoint(x: 0.75, y: 0.75 + hi)
        f.point4 = CGPoint(x: 1.0, y: 1.0)
        return f.outputImage ?? image
    }

    // MARK: Vibrance (smart saturation that protects already-saturated tones)

    static nonisolated func applyVibrance(_ image: CIImage, _ s: EditState) -> CIImage {
        guard s.vibrance != 0 else { return image }
        let f = CIFilter.vibrance()
        f.inputImage = image
        f.amount = Float(s.vibrance)                    // −1...1 maps directly
        return f.outputImage ?? image
    }

    // MARK: Sharpen (luminance only, so colour noise isn't amplified)

    static nonisolated func applySharpen(_ image: CIImage, _ s: EditState, grainScale: CGFloat) -> CIImage {
        guard s.sharpness > 0 else { return image }
        let f = CIFilter.sharpenLuminance()
        f.inputImage = image
        f.sharpness = Float(min(max(s.sharpness, 0), 1) * 1.2)
        // Radius is in pixels, so it must scale with resolution to match preview↔export — same
        // grainScale trick as grain (divide here, since a smaller preview needs a smaller radius
        // for the same *relative* halo).
        f.radius = Float(1.6 / max(grainScale, 0.001))
        return f.outputImage ?? image
    }

    // MARK: Vignette (darkened edges — resolution-independent)

    static nonisolated func applyVignette(_ image: CIImage, _ s: EditState) -> CIImage {
        guard s.vignette > 0 else { return image }
        let f = CIFilter.vignette()
        f.inputImage = image
        f.intensity = Float(s.vignette * 1.3)           // subtle → strong
        f.radius = Float(1.0 + s.vignette)              // pull the falloff inward as it deepens
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
