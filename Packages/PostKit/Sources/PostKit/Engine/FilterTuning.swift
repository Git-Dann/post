import CoreGraphics

/// One place to tune the *strength* of every adjustment — the colour-science magnitudes that map a
/// dial's −1…1 / 0…1 value onto a Core Image parameter. Edit a number here and rebuild; the live
/// preview and the export both read from `FilterPipeline`, so they stay in lockstep.
///
/// These are deliberately hand-tuned starting points — the kind of thing best nudged by eye on a
/// real photo. (Sibling to `DialFeel`, which tunes how the dial *feels*; this tunes what it *does*.)
public nonisolated enum FilterTuning {

    // MARK: Light & tone
    /// Exposure: stops of light at the dial extremes (±1 → ±this many EV).
    public static let exposureEV: Float = 1.5
    /// Brightness: additive lift at ±1 (kept subtle — Exposure is the heavy hitter).
    public static let brightnessGain: Float = 0.4
    /// Contrast: multiplicative spread around 1.0 at ±1.
    public static let contrastGain: Float = 0.45
    /// Highlights / Shadows: how far the high / low quarter of the tone curve moves at ±1.
    public static let highlightLift: Double = 0.18
    public static let shadowLift: Double = 0.18

    // MARK: White balance
    /// Daylight reference the source white is mapped from.
    public static let whiteBalanceBaseK: Double = 6500
    /// Warmth: Kelvin shift at ±1. Positive warmth → a *lower* target temperature → warmer/amber.
    /// (Increase for a punchier warmth slider; decrease for a gentler one.)
    public static let warmthRangeK: Double = 2500
    /// Tint: green↔magenta shift at ±1. If a real photo shows this inverted, flip the sign in
    /// `FilterPipeline.applyWhiteBalance` (the one-line change) or negate this value.
    public static let tintRange: Double = 50

    // MARK: Colour
    /// Hue: rotation at ±1 (π = a full half-turn; ±1 sweeps the whole wheel).
    public static let hueAngle: Float = .pi
    // Vibrance maps 1:1 onto CIVibrance.amount, so it has no constant here.

    // MARK: Finishing
    /// Sharpness: CISharpenLuminance.sharpness at full strength (1.0).
    public static let sharpenMax: Float = 1.2
    /// Sharpen radius in pixels at full resolution; divided by grainScale so preview ≈ export.
    public static let sharpenRadius: Float = 1.6
    /// Vignette: edge-darkening intensity and how far the falloff pulls inward, at full strength.
    public static let vignetteIntensity: Float = 1.3
    public static let vignetteRadius: Float = 1.0

    // MARK: Film
    /// Fade: how far the blacks lift and the whites milk at full strength (the faded-film look).
    public static let fadeBlackLift: Double = 0.18
    public static let fadeWhiteMilk: Double = 0.05
    /// Grain: overall intensity and noise cell size (smaller = finer). Cell size ×= grainScale so
    /// the preview's grain reads at the same density as the export.
    public static let grainStrength: Float = 0.14
    public static let grainCellSize: Float = 0.8
}
