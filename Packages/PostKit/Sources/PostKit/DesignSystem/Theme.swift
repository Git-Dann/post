import SwiftUI

/// Central design tokens for Post. Kept tiny and opinionated — the app's identity
/// lives in feel (motion + haptics + glass), not in a sprawling token set.
///
/// `nonisolated` so these immutable constants can be read from any context (including the
/// Sendable label closures of system controls like `PhotosPicker`).
public nonisolated enum Theme {

    // MARK: Brand color

    /// Warm amber accent pulled from the reference shots (the tag chip / highlights).
    public static let accent = Color(red: 0.98, green: 0.74, blue: 0.18)

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
