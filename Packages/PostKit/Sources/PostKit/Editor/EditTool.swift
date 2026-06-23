import SwiftUI

/// One adjustment the editor exposes. Each tool knows how to read and write its slice of the
/// `EditState` recipe, its dial range, and how to present its value — so the editor UI stays
/// generic and the dial is fully reusable.
public enum EditTool: String, CaseIterable, Identifiable, Sendable {
    case crop
    case auto
    case exposure
    case brightness
    case contrast
    case highlights
    case shadows
    case saturation
    case vibrance
    case warmth
    case tint
    case hue
    case sharpness
    case vignette
    case fade
    case grain

    public var id: String { rawValue }

    /// Tools shown on the dial, in display order (crop is a separate geometry mode). Ordered
    /// roughly the way you'd grade a photo: light → tone → colour → finishing.
    public static let dialTools: [EditTool] = [
        .auto, .exposure, .brightness, .contrast, .highlights, .shadows,
        .saturation, .vibrance, .warmth, .tint, .hue,
        .sharpness, .vignette, .fade, .grain
    ]

    /// All tools shown in the bottom tool strip, crop first.
    public static let toolbar: [EditTool] = [.crop] + dialTools

    public var isGeometry: Bool { self == .crop }

    /// Coarse grouping — Auto · Light · Colour · Effects. Drives the category-first tool strip: the
    /// strip shows these categories, and tapping one reveals its tools.
    public enum Group: Sendable, Hashable {
        case geometry, auto, light, colour, finishing

        /// The drillable adjustment categories, in strip order (Auto/Crop/Styles are handled as
        /// direct actions, not drill-in categories).
        public static let adjustmentCategories: [Group] = [.light, .colour, .finishing]

        public var title: String {
            switch self {
            case .geometry: "Crop"
            case .auto: "Auto"
            case .light: "Light"
            case .colour: "Colour"
            case .finishing: "Effects"
            }
        }

        /// Category emblem — chosen to stay distinct from each other at the category level.
        public var systemImage: String {
            switch self {
            case .geometry: "crop.rotate"
            case .auto: "sparkles"
            case .light: "sun.max"
            case .colour: "paintpalette"
            case .finishing: "camera.filters"
            }
        }

        /// The dial tools in this group, in display order.
        public var tools: [EditTool] { EditTool.dialTools.filter { $0.group == self } }
    }

    public var group: Group {
        switch self {
        case .crop: .geometry
        case .auto: .auto
        case .exposure, .brightness, .contrast, .highlights, .shadows: .light
        case .saturation, .vibrance, .warmth, .tint, .hue: .colour
        case .sharpness, .vignette, .fade, .grain: .finishing
        }
    }

    public var title: String {
        switch self {
        case .crop: "Crop"
        case .auto: "Auto"
        case .exposure: "Exposure"
        case .brightness: "Brightness"
        case .contrast: "Contrast"
        case .highlights: "Highlights"
        case .shadows: "Shadows"
        case .saturation: "Saturation"
        case .vibrance: "Vibrance"
        case .warmth: "Warmth"
        case .tint: "Tint"
        case .hue: "Hue"
        case .sharpness: "Sharpness"
        case .vignette: "Vignette"
        case .fade: "Fade"
        case .grain: "Grain"
        }
    }

    public var systemImage: String {
        switch self {
        case .crop: "crop.rotate"
        case .auto: "sparkles"
        case .exposure: "plusminus.circle"
        case .brightness: "sun.max"
        case .contrast: "circle.lefthalf.filled"
        case .highlights: "sun.and.horizon.fill"   // bright tones; visually distinct from brightness's sun.max
        case .shadows: "moon.fill"                 // dark tones (moon)
        case .saturation: "drop"
        case .vibrance: "drop.fill"
        case .warmth: "thermometer.medium"
        case .tint: "camera.filters"
        case .hue: "paintpalette"
        case .sharpness: "wand.and.rays"
        case .vignette: "circle.dotted"
        case .fade: "sun.haze"
        case .grain: "circle.grid.3x3"
        }
    }

    /// Dial range for this tool (bipolar adjustments −1...1, positive-only looks 0...1).
    public var range: ClosedRange<Double> {
        switch self {
        case .exposure, .brightness, .contrast, .highlights, .shadows,
             .saturation, .vibrance, .warmth, .tint, .hue: -1...1
        case .auto, .sharpness, .vignette, .fade, .grain: 0...1
        case .crop: 0...1
        }
    }

    /// Detent granularity in value units — the spacing between ruler ticks / haptic stops.
    /// 0.01 → steps of 1 on the readout for fine, integer-by-integer control.
    public var detent: Double { 0.01 }

    public var isBipolar: Bool { range.lowerBound < 0 }

    /// A subtle colour hint for the dial ruler — only for tools with a real colour axis. The rest
    /// keep their neutral ruler (a colour would be arbitrary and would cheapen the machined look).
    public var dialTint: DialTint? {
        switch self {
        case .warmth: .warmth
        case .tint: .tint
        case .hue: .spectrum
        default: nil
        }
    }

    public func value(in state: EditState) -> Double {
        switch self {
        case .auto: state.autoStrength
        case .exposure: state.exposure
        case .brightness: state.brightness
        case .contrast: state.contrast
        case .highlights: state.highlights
        case .shadows: state.shadows
        case .saturation: state.saturation
        case .vibrance: state.vibrance
        case .warmth: state.warmth
        case .tint: state.tint
        case .hue: state.hue
        case .sharpness: state.sharpness
        case .vignette: state.vignette
        case .fade: state.fade
        case .grain: state.grain
        case .crop: 0
        }
    }

    public func set(_ value: Double, in state: inout EditState) {
        let v = min(max(value, range.lowerBound), range.upperBound)
        switch self {
        case .auto: state.autoStrength = v   // editor re-derives the real fields (see EditorModel)
        case .exposure: state.exposure = v
        case .brightness: state.brightness = v
        case .contrast: state.contrast = v
        case .highlights: state.highlights = v
        case .shadows: state.shadows = v
        case .saturation: state.saturation = v
        case .vibrance: state.vibrance = v
        case .warmth: state.warmth = v
        case .tint: state.tint = v
        case .hue: state.hue = v
        case .sharpness: state.sharpness = v
        case .vignette: state.vignette = v
        case .fade: state.fade = v
        case .grain: state.grain = v
        case .crop: break
        }
    }

    /// Friendly value readout (the "+0.0" pill in the reference). Positive-only looks show an
    /// unsigned 0–100; bipolar adjustments show a signed ±100.
    public func readout(in state: EditState) -> String {
        let v = value(in: state)
        switch self {
        case .auto, .sharpness, .vignette, .fade, .grain:
            return String(format: "%.0f", v * 100)
        default:
            return String(format: "%+.0f", v * 100)
        }
    }
}
