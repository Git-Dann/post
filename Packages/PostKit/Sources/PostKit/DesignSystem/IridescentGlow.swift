import SwiftUI

/// An iridescent shimmer — a slowly-rotating angular sweep of cool→warm hues, softly blurred into a
/// glow. Pure SwiftUI (no Metal, no private API). Used as a brief, delightful "on-device subject
/// detection" cue: masked to the selected region, or to a capsule stroke on the scope chip while
/// segmenting. Holds still under Reduce Motion.
struct IridescentGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    private let colors: [Color] = [
        Color(red: 0.30, green: 0.60, blue: 1.00),   // blue
        Color(red: 0.60, green: 0.40, blue: 0.95),   // violet
        Color(red: 0.96, green: 0.36, blue: 0.62),   // pink
        Color(red: 0.98, green: 0.70, blue: 0.30),   // amber
        Color(red: 0.30, green: 0.60, blue: 1.00)    // back to blue → seamless loop
    ]

    var body: some View {
        AngularGradient(colors: colors, center: .center, angle: .degrees(angle))
            .blur(radius: 14)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
