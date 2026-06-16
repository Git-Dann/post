import SwiftUI

/// A subtle one-shot glass light-sweep. Trigger it by changing `token` (e.g. the active style id)
/// and a soft diagonal highlight glides across once — just enough to make applying a look feel
/// physical. Respects Reduce Motion (no sweep), and never intercepts touches.
public struct ShimmerSweep: ViewModifier {
    private let token: AnyHashable?
    @State private var progress: CGFloat = 1   // 0 = entering from the left, 1 = gone past the right
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(token: AnyHashable?) { self.token = token }

    public func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                let w = geo.size.width
                LinearGradient(
                    colors: [.clear, .white.opacity(0.30), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: w * 0.55)
                .offset(x: -w * 0.55 + progress * (w * 1.55))
                .blendMode(.plusLighter)
            }
            .opacity(progress < 1 ? 1 : 0)
            .allowsHitTesting(false)
        }
        .onChange(of: token) { _, _ in
            guard !reduceMotion else { return }
            progress = 0
            withAnimation(.easeOut(duration: 0.7)) { progress = 1 }
        }
    }
}

public extension View {
    /// A subtle glass light-sweep that plays whenever `token` changes.
    func shimmerSweep(token: AnyHashable?) -> some View { modifier(ShimmerSweep(token: token)) }
}
