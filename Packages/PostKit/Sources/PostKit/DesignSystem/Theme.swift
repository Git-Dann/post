import SwiftUI

/// Central design tokens for Post. Kept tiny and opinionated — the app's identity
/// lives in feel (motion + haptics + glass), not in a sprawling token set.
///
/// `nonisolated` so these immutable constants can be read from any context (including the
/// Sendable label closures of system controls like `PhotosPicker`).
public nonisolated enum Theme {

    // MARK: Brand color

    /// The user-selected accent (defaults to warm amber). Computed so a change in Settings
    /// propagates everywhere once the view tree re-renders.
    public static var accent: Color { AccentChoice.current.color }

    /// The editor canvas is always near-black so the image is the hero.
    public static let canvas = Color(red: 0.05, green: 0.05, blue: 0.06)

    // MARK: Spacing

    public nonisolated enum Space {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 32
    }

    // MARK: Motion — one vocabulary, reused everywhere.

    public nonisolated enum Motion {
        /// Snappy, lightly playful response for taps and tool changes.
        public static let snappy = Animation.spring(response: 0.34, dampingFraction: 0.78)
        /// Softer settle for larger surfaces.
        public static let settle = Animation.spring(response: 0.5, dampingFraction: 0.85)
        /// The bounce used when a control rubber-bands back from a bound.
        public static let bounce = Animation.interpolatingSpring(stiffness: 260, damping: 17)

        /// Reduce-Motion-aware variant of ``bounce``.
        public static func bounce(reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.15) : bounce
        }
    }

    // MARK: Shape

    public nonisolated enum Radius {
        public static let control: CGFloat = 22
        public static let card: CGFloat = 28
        public static let image: CGFloat = 32
    }
}

/// The selectable accent colorways. Stored as a raw string in UserDefaults under "accentChoice".
public nonisolated enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case amber, coral, pink, violet, blue, teal, green

    public static let storageKey = "accentChoice"

    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }

    public var color: Color {
        switch self {
        case .amber:  Color(red: 0.98, green: 0.74, blue: 0.18)
        case .coral:  Color(red: 1.00, green: 0.45, blue: 0.35)
        case .pink:   Color(red: 0.96, green: 0.36, blue: 0.62)
        case .violet: Color(red: 0.60, green: 0.40, blue: 0.95)
        case .blue:   Color(red: 0.25, green: 0.55, blue: 1.00)
        case .teal:   Color(red: 0.16, green: 0.78, blue: 0.74)
        case .green:  Color(red: 0.40, green: 0.82, blue: 0.45)
        }
    }

    /// The current choice from UserDefaults (defaults to amber).
    public static var current: AccentChoice {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let choice = AccentChoice(rawValue: raw) else { return .amber }
        return choice
    }
}
