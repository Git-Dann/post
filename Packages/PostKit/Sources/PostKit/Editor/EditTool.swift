import SwiftUI

/// One adjustment the editor exposes. Each tool knows how to read and write its slice of the
/// `EditState` recipe, its dial range, and how to present its value — so the editor UI stays
/// generic and the dial is fully reusable.
public enum EditTool: String, CaseIterable, Identifiable, Sendable {
    case crop
    case brightness
    case contrast
    case saturation
    case hue
    case fade
    case grain

    public var id: String { rawValue }

    /// Tools shown on the dial, in display order (crop is a separate geometry mode).
    public static let dialTools: [EditTool] = [.brightness, .contrast, .saturation, .hue, .fade, .grain]

    /// All tools shown in the bottom tool strip, crop first.
    public static let toolbar: [EditTool] = [.crop] + dialTools

    public var isGeometry: Bool { self == .crop }

    public var title: String {
        switch self {
        case .crop: "Crop"
        case .brightness: "Brightness"
        case .contrast: "Contrast"
        case .saturation: "Saturation"
        case .hue: "Hue"
        case .fade: "Fade"
        case .grain: "Grain"
        }
    }

    public var systemImage: String {
        switch self {
        case .crop: "crop.rotate"
        case .brightness: "sun.max"
        case .contrast: "circle.lefthalf.filled"
        case .saturation: "drop"
        case .hue: "paintpalette"
        case .fade: "sun.haze"
        case .grain: "circle.grid.3x3"
        }
    }

    /// Dial range for this tool (bipolar adjustments −1...1, film looks 0...1).
    public var range: ClosedRange<Double> {
        switch self {
        case .brightness, .contrast, .saturation, .hue: -1...1
        case .fade, .grain: 0...1
        case .crop: 0...1
        }
    }

    /// Detent granularity in value units — the spacing between ruler ticks / haptic stops.
    /// 0.01 → steps of 1 on the readout for fine, integer-by-integer control.
    public var detent: Double { 0.01 }

    public var isBipolar: Bool { range.lowerBound < 0 }

    public func value(in state: EditState) -> Double {
        switch self {
        case .brightness: state.brightness
        case .contrast: state.contrast
        case .saturation: state.saturation
        case .hue: state.hue
        case .fade: state.fade
        case .grain: state.grain
        case .crop: 0
        }
    }

    public func set(_ value: Double, in state: inout EditState) {
        let v = min(max(value, range.lowerBound), range.upperBound)
        switch self {
        case .brightness: state.brightness = v
        case .contrast: state.contrast = v
        case .saturation: state.saturation = v
        case .hue: state.hue = v
        case .fade: state.fade = v
        case .grain: state.grain = v
        case .crop: break
        }
    }

    /// Friendly value readout (the "+0.0" pill in the reference).
    public func readout(in state: EditState) -> String {
        let v = value(in: state)
        switch self {
        case .fade, .grain:
            return String(format: "%.0f", v * 100)
        default:
            return String(format: "%+.0f", v * 100)
        }
    }
}
