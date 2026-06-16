import UIKit
import AudioToolbox
import AVFoundation

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

/// Optional dial tick sound. Uses an ambient, mix-with-others session so it plays alongside any
/// audio and respects the silent switch (we never force sound over the user's mute).
public enum DialSound {
    private static var prepared = false

    public static func prepare() {
        guard !prepared else { return }
        prepared = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    public static func tick() {
        AudioServicesPlaySystemSound(1104)   // soft "tock"
    }
}
