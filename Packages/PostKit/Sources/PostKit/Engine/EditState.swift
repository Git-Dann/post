import Foundation
import CoreGraphics

/// The complete, non-destructive recipe for an edit. This is the single source of truth:
/// the same value drives the live preview and the full-resolution export, and it's all that
/// gets persisted per project. Normalized parameters keep it resolution- and device-independent.
///
/// `Sendable` so it crosses actor boundaries to the export actor; `Codable` for persistence and
/// the bundled style manifest; `Equatable` so undo/redo only snapshots real changes.
///
/// Marked `nonisolated` to opt out of the module's default `MainActor` isolation — it's pure
/// data that the nonisolated pipeline and the export actor both use freely.
public nonisolated struct EditState: Codable, Sendable, Equatable {

    // MARK: Tone & color — normalized −1...1, 0 = neutral.
    public var exposure: Double = 0
    public var brightness: Double = 0
    public var contrast: Double = 0
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var saturation: Double = 0
    public var vibrance: Double = 0
    public var hue: Double = 0

    // MARK: White balance — −1...1, 0 = neutral.
    public var warmth: Double = 0
    public var tint: Double = 0

    /// Auto-enhance strength (0…1). The resolved adjustment values live in the fields above; this
    /// just remembers where the Auto dial sits.
    public var autoStrength: Double = 0

    // MARK: Film looks & finishing — 0...1, 0 = off.
    public var fade: Double = 0
    public var grain: Double = 0
    public var sharpness: Double = 0
    public var vignette: Double = 0

    /// Selective scope: confines the tonal/colour adjustments to a region (finishing stays global).
    public var scope: SelectiveScope = .whole

    // MARK: Geometry.
    public var crop: CropRect = .full
    /// Fine straightening, radians, ±~0.4 (≈ ±23°).
    public var straightenAngle: Double = 0
    /// Discrete 90° taps: 0, 1, 2, 3.
    public var rotationQuarterTurns: Int = 0
    public var flippedHorizontally: Bool = false
    public var flippedVertically: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case exposure, brightness, contrast, highlights, shadows, saturation, vibrance, hue
        case warmth, tint, autoStrength
        case fade, grain, sharpness, vignette
        case scope
        case crop, straightenAngle, rotationQuarterTurns, flippedHorizontally, flippedVertically
    }

    /// Resilient decoding: any absent key falls back to its neutral default. This lets style
    /// manifests (and future remote recipes) specify only the fields they change.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        hue = try c.decodeIfPresent(Double.self, forKey: .hue) ?? 0
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        autoStrength = try c.decodeIfPresent(Double.self, forKey: .autoStrength) ?? 0
        fade = try c.decodeIfPresent(Double.self, forKey: .fade) ?? 0
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        vignette = try c.decodeIfPresent(Double.self, forKey: .vignette) ?? 0
        scope = try c.decodeIfPresent(SelectiveScope.self, forKey: .scope) ?? .whole
        crop = try c.decodeIfPresent(CropRect.self, forKey: .crop) ?? .full
        straightenAngle = try c.decodeIfPresent(Double.self, forKey: .straightenAngle) ?? 0
        rotationQuarterTurns = try c.decodeIfPresent(Int.self, forKey: .rotationQuarterTurns) ?? 0
        flippedHorizontally = try c.decodeIfPresent(Bool.self, forKey: .flippedHorizontally) ?? false
        flippedVertically = try c.decodeIfPresent(Bool.self, forKey: .flippedVertically) ?? false
    }

    /// True when the recipe is a no-op (used to short-circuit rendering and hide "reset").
    public var isIdentity: Bool { self == EditState() }

    /// True if any tone/color/film adjustment is non-neutral (geometry excluded).
    public var hasToneAdjustments: Bool {
        exposure != 0 || brightness != 0 || contrast != 0 || highlights != 0 || shadows != 0
            || saturation != 0 || vibrance != 0 || hue != 0 || warmth != 0 || tint != 0
            || autoStrength != 0 || fade != 0 || grain != 0 || sharpness != 0 || vignette != 0
    }
}

/// A crop rectangle expressed as fractions (0...1) of the source extent, so the same crop
/// applies identically to the downscaled preview and the full-resolution original.
public nonisolated struct CropRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey { case x, y, width, height }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 1
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 1
    }

    public static let full = CropRect()

    public var isFull: Bool { self == .full }
}
