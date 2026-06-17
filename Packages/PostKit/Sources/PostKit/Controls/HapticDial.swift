import SwiftUI

/// The signature control: a horizontal tick ruler built on a native scroll view, so it inherits the
/// system's smooth momentum, deceleration and rubber-band for free — a slow drag is precise, a flick
/// coasts and settles. Ticks snap to detents under a fixed center indicator, with a per-tick haptic
/// (a fuller "thunk" on the zero/center detent). Reused by the editor adjustments and the crop
/// straighten wheel.
public struct HapticDial: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let detent: Double
    private let label: String
    private let soundEnabled: Bool
    private let onBegin: () -> Void
    private let onCommit: () -> Void

    @State private var centered: Int?
    @State private var indicatorScale: CGFloat = 1
    @State private var isScrolling = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pitch: CGFloat = 12   // points between ticks (a little tighter)

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        detent: Double,
        label: String = "Adjustment",
        soundEnabled: Bool = false,
        onBegin: @escaping () -> Void = {},
        onCommit: @escaping () -> Void = {}
    ) {
        self._value = value
        self.range = range
        self.detent = detent
        self.label = label
        self.soundEnabled = soundEnabled
        self.onBegin = onBegin
        self.onCommit = onCommit
        _centered = State(initialValue: Int((value.wrappedValue / detent).rounded()))
    }

    private var lowIndex: Int { Int((range.lowerBound / detent).rounded()) }
    private var highIndex: Int { Int((range.upperBound / detent).rounded()) }
    private var isBipolar: Bool { range.lowerBound < 0 }

    public var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(lowIndex...highIndex, id: \.self) { i in
                        tick(i, height: h)
                            .frame(width: pitch)
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered, anchor: .center)
            .contentMargins(.horizontal, geo.size.width / 2, for: .scrollContent)
            // Fade the ruler out at the edges (mask, so it goes transparent rather than to a band).
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.14),
                    .init(color: .black, location: 0.86),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            )
            .overlay { centerIndicator(height: h) }
            .onScrollPhaseChange { old, new in
                isScrolling = new != .idle
                if old == .idle && new != .idle { onBegin() }
                if old != .idle && new == .idle { onCommit() }
            }
        }
        .frame(height: 64)
        .onChange(of: centered) { _, new in
            guard let new else { return }
            let v = min(max(Double(new) * detent, range.lowerBound), range.upperBound)
            if abs(v - value) > 1e-9 { value = v }
            if soundEnabled { DialSound.tick() }
            if new == 0 && isBipolar && !reduceMotion {
                indicatorScale = 1.6
                withAnimation(.spring(response: 0.4, dampingFraction: 0.45)) { indicatorScale = 1 }
            }
        }
        .onChange(of: value) { _, v in
            // Ignore writes while the user is mid-scroll — otherwise a live recipe update would
            // yank the ruler out from under their finger and fight the momentum. External changes
            // (reset, undo) only ever arrive when the dial is idle, which is exactly when we honor them.
            guard !isScrolling else { return }
            let idx = Int((v / detent).rounded())
            if idx != centered { centered = idx }
        }
        .sensoryFeedback(trigger: centered) { _, new in
            if new == lowIndex || new == highIndex { return DialFeel.boundHaptic }   // hit the end
            return (new == 0 && isBipolar) ? DialFeel.zeroHaptic : DialFeel.tickHaptic
        }
        .accessibilityElement()
        .accessibilityLabel("\(label) dial")
        .accessibilityValue(Text(String(format: "%.0f", value * 100)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: centered = min((centered ?? 0) + 1, highIndex)
            case .decrement: centered = max((centered ?? 0) - 1, lowIndex)
            default: break
            }
        }
    }

    private func tick(_ i: Int, height: CGFloat) -> some View {
        // Three tiers: 1s short, 5s a medium step, 10s the tall reference lines.
        let isTen = i % 10 == 0
        let isFive = i % 5 == 0
        let isZero = i == 0 && isBipolar
        let lineHeight = height * (isTen ? 0.6 : isFive ? 0.44 : 0.3)
        let lineWidth: CGFloat = isTen ? 2 : isFive ? 1.75 : 1.5
        let opacity = isTen ? 0.55 : isFive ? 0.45 : 0.3
        return Capsule()
            .fill(isZero ? Theme.accent : .white.opacity(opacity))
            .frame(width: lineWidth, height: lineHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // center the line within its pitch
    }

    private func centerIndicator(height: CGFloat) -> some View {
        Capsule()
            .fill(Theme.accent)
            .frame(width: 3, height: height * 0.7)
            .scaleEffect(x: 1, y: indicatorScale, anchor: .center)
            .shadow(color: Theme.accent.opacity(0.6), radius: 6)
            .allowsHitTesting(false)
    }
}
