import UIKit

/// Centralized haptic vocabulary so feel is intentional and consistent — not sprinkled ad hoc.
/// Views prefer SwiftUI's declarative `.sensoryFeedback`; this is for imperative spots inside
/// gesture handlers (e.g. crop handle snaps) where a direct tap reads better.
public enum Haptics {

    public static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred(intensity: intensity)
    }

    public static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}
