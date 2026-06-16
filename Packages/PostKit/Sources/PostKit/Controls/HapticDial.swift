import SwiftUI

/// The signature control: a horizontal, machined-wheel tick ruler. Drag scrolls the ticks under
/// a fixed center indicator; the value snaps to detents with a per-tick selection haptic, a heavier
/// "thunk" at the zero/center detent, and a rigid tap + rubber-band spring bounce at the bounds.
///
/// Reusable: the editor adjustments and the crop straighten wheel both use it.
public struct HapticDial: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let detent: Double
    private let onBegin: () -> Void
    private let onCommit: () -> Void

    private let tickSpacing: CGFloat = 10
    private var pointsPerUnit: CGFloat { tickSpacing / detent }
    private var isBipolar: Bool { range.lowerBound < 0 }

    @State private var dragStart: Double?
    @State private var overscroll: CGFloat = 0
    @State private var boundHits: Int = 0
    @State private var wasAtBound = false
    @State private var indicatorScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        detent: Double,
        onBegin: @escaping () -> Void = {},
        onCommit: @escaping () -> Void = {}
    ) {
        self._value = value
        self.range = range
        self.detent = detent
        self.onBegin = onBegin
        self.onCommit = onCommit
    }

    private var detentIndex: Int { Int((value / detent).rounded()) }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                ruler(width: geo.size.width, height: geo.size.height)
                    .offset(x: overscroll)
                centerIndicator(height: geo.size.height)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .frame(height: 64)
        .sensoryFeedback(trigger: detentIndex) { _, newValue in
            newValue == 0 && isBipolar ? .impact(weight: .heavy, intensity: 0.85) : .selection
        }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.7), trigger: boundHits)
        .onChange(of: detentIndex) { _, newValue in
            guard newValue == 0, isBipolar, !reduceMotion else { return }
            indicatorScale = 1.6   // popped, then springs back to 1
            withAnimation(.spring(response: 0.4, dampingFraction: 0.45)) { indicatorScale = 1 }
        }
        .accessibilityElement()
        .accessibilityLabel("Adjustment dial")
        .accessibilityValue(Text(String(format: "%.0f", value * 100)))
        .accessibilityAdjustableAction { direction in
            let step = detent * 2
            switch direction {
            case .increment: setValue(value + step)
            case .decrement: setValue(value - step)
            default: break
            }
        }
    }

    // MARK: Ruler

    private func ruler(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            let mid = size.width / 2
            let halfSpan = mid / pointsPerUnit
            var i = Int(((value - halfSpan) / detent).rounded(.down)) - 1
            let iMax = Int(((value + halfSpan) / detent).rounded(.up)) + 1

            while i <= iMax {
                let tickValue = Double(i) * detent
                defer { i += 1 }
                guard tickValue >= range.lowerBound - 1e-9,
                      tickValue <= range.upperBound + 1e-9 else { continue }

                let x = mid + CGFloat(tickValue - value) * pointsPerUnit
                guard x >= -2, x <= size.width + 2 else { continue }

                let isMajor = i % 5 == 0
                let isZero = i == 0
                let h = isMajor ? size.height * 0.62 : size.height * 0.30
                var path = Path()
                path.move(to: CGPoint(x: x, y: (size.height - h) / 2))
                path.addLine(to: CGPoint(x: x, y: (size.height + h) / 2))

                // Fade ticks toward the edges for a soft, focused ruler.
                let edge = min(x, size.width - x)
                let edgeAlpha = max(0, min(1, edge / 44))
                if isZero && isBipolar {
                    context.stroke(path, with: .color(Theme.accent.opacity(Double(edgeAlpha))), lineWidth: 2.5)
                } else {
                    let base = isMajor ? 0.55 : 0.32
                    context.stroke(path, with: .color(.white.opacity(base * Double(edgeAlpha))),
                                   lineWidth: isMajor ? 2 : 1)
                }
            }
        }
    }

    private func centerIndicator(height: CGFloat) -> some View {
        Capsule()
            .fill(Theme.accent)
            .frame(width: 3, height: height * 0.7)
            .scaleEffect(x: 1, y: indicatorScale, anchor: .center)
            .shadow(color: Theme.accent.opacity(0.6), radius: 6)
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragStart == nil {
                    dragStart = value
                    onBegin()
                }
                let start = dragStart ?? value
                let raw = start - Double(gesture.translation.width / pointsPerUnit)

                let beyond = raw < range.lowerBound || raw > range.upperBound
                if beyond {
                    let bound = raw < range.lowerBound ? range.lowerBound : range.upperBound
                    overscroll = rubberBand(CGFloat(raw - bound) * pointsPerUnit)
                    setValue(bound)
                    if !wasAtBound { boundHits += 1 }   // rigid tap once per contact
                    wasAtBound = true
                } else {
                    overscroll = 0
                    wasAtBound = false
                    setValue((raw / detent).rounded() * detent)
                }
            }
            .onEnded { _ in
                dragStart = nil
                wasAtBound = false
                withAnimation(Theme.Motion.bounce(reduceMotion: reduceMotion)) {
                    overscroll = 0
                }
                onCommit()
            }
    }

    private func setValue(_ newValue: Double) {
        let clamped = min(max(newValue, range.lowerBound), range.upperBound)
        if clamped != value { value = clamped }
    }

    private func rubberBand(_ offset: CGFloat) -> CGFloat {
        let limit: CGFloat = 80
        let coefficient: CGFloat = 0.55
        let sign: CGFloat = offset < 0 ? -1 : 1
        let magnitude = abs(offset)
        return sign * (1 - 1 / (magnitude * coefficient / limit + 1)) * limit
    }
}
