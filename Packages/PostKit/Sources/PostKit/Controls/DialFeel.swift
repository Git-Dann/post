import SwiftUI

/// One place to tune how the dials feel. Edit these numbers and rebuild — every adjustment dial
/// and the crop straighten wheel read from here, so the whole app stays consistent.
///
/// Quick guide:
/// • Grippier / finer control → raise ``pointsPerDetent`` (more finger travel per click).
/// • Stronger clicks          → raise the `intensity:` on the haptics below (max 1.0), or bump the
///                              `weight:` (`.light` → `.medium` → `.heavy`) / use `.rigid` flexibility.
/// • Longer/shorter coast      → ``coastFriction`` toward 1.0 glides longer; lower stops sooner.
///
/// (The *value* step per click — how much e.g. Brightness moves per detent — lives in
/// `EditTool.detent`; lower it there for even finer numeric steps.)
public nonisolated enum DialFeel {

    // MARK: Grip & precision

    /// Finger travel, in points, needed to advance one detent. Higher = a grippier wheel that takes
    /// more deliberate movement, giving finer control. (Was 17; 24 is noticeably grippier.)
    public static let pointsPerDetent: CGFloat = 24

    // MARK: Momentum (flick to coast)

    /// Per-frame velocity decay while coasting after a flick. Closer to 1.0 = longer glide.
    public static let coastFriction: Double = 0.95
    /// Speed (value units/sec) below which a coast settles onto the nearest detent.
    public static let coastStopThreshold: Double = 0.15

    // MARK: Haptics — strength of each "click"

    /// Felt every time the wheel crosses a detent.
    public static let tickHaptic: SensoryFeedback = .impact(weight: .heavy, intensity: 0.85)
    /// A fuller "thunk" when landing on the zero/center detent of a bipolar dial.
    public static let zeroHaptic: SensoryFeedback = .impact(weight: .heavy, intensity: 1.0)
    /// A rigid tap when the wheel hits the end of its range.
    public static let boundHaptic: SensoryFeedback = .impact(flexibility: .rigid, intensity: 1.0)
}
