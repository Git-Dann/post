import SwiftUI

/// Which screen corner an arc dial is seated in. The apex is the corner itself, and the tick fan
/// sweeps the quarter between the two edges that meet there.
public nonisolated enum DialCorner: String, CaseIterable, Sendable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }

    var unitPoint: UnitPoint {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }

    /// Where the ticks radiate from, in the dial's own coordinate space.
    func apex(in size: CGSize) -> CGPoint {
        switch self {
        case .topLeading: CGPoint(x: 0, y: 0)
        case .topTrailing: CGPoint(x: size.width, y: 0)
        case .bottomLeading: CGPoint(x: 0, y: size.height)
        case .bottomTrailing: CGPoint(x: size.width, y: size.height)
        }
    }

    /// Angles are radians from the +x axis in SwiftUI's y-down space.
    /// The low end of the range always sits at the *lower* end of the arc and the high end at the
    /// *upper* one — so in every corner, dragging your finger up the arc raises the value.
    private var lowAngle: Double {
        switch self {
        case .topLeading, .topTrailing: .pi / 2    // straight down the side edge
        case .bottomLeading: 0                     // along the bottom edge
        case .bottomTrailing: .pi                  // along the bottom edge
        }
    }

    private var highAngle: Double {
        switch self {
        case .topLeading: 0                        // along the top edge
        case .topTrailing: .pi                     // along the top edge
        case .bottomLeading: -.pi / 2              // straight up the side edge
        case .bottomTrailing: 3 * .pi / 2          // straight up the side edge
        }
    }

    /// +1 when the value climbs with increasing angle, −1 when it climbs against it.
    var direction: Double { highAngle > lowAngle ? 1 : -1 }

    /// A few degrees of breathing room so the end ticks don't sit flush against the screen edges.
    private static let endInset: Double = 0.1

    var startAngle: Double { lowAngle + Self.endInset * direction }
    var endAngle: Double { highAngle - Self.endInset * direction }

    /// Angle of the arc at normalized position `t` (0 = range floor, 1 = range ceiling).
    func angle(at t: Double) -> Double {
        startAngle + (endAngle - startAngle) * min(max(t, 0), 1)
    }

    /// A point on the arc at normalized position `t` and the given radius from the apex.
    func point(at t: Double, radius: CGFloat, in size: CGSize) -> CGPoint {
        let a = angle(at: t)
        let o = apex(in: size)
        return CGPoint(x: o.x + cos(a) * radius, y: o.y + sin(a) * radius)
    }
}

/// The landscape counterpart to ``HapticDial``: a quarter-circle tick fan wrapped into a screen
/// corner, so four adjustments can sit around the photo at once while the image keeps the middle of
/// the screen to itself.
///
/// Feel matches the ruler dial — relative scrubbing (nothing jumps when you touch down), one haptic
/// click per detent, a fuller thunk on a bipolar zero, a rigid tap at the ends, and pointer-style
/// acceleration so a slow drag is precise and a quick sweep travels. Gearing lives in ``DialFeel``.
public struct CornerDial: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let detent: Double
    private let corner: DialCorner
    private let systemImage: String
    private let label: String
    private let readout: String
    private let radius: CGFloat
    private let tint: DialTint?
    private let soundEnabled: Bool
    private let onBegin: () -> Void
    private let onCommit: () -> Void

    /// Unsnapped position, so sub-detent movement accumulates instead of being rounded away.
    @State private var rawValue: Double = 0
    @State private var lastAngle: Double?
    @State private var scrubbing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ticks in the fan. Coarser than the detents (a 200-step range would be a solid smear) — the fan
    /// reads as a gauge of the range, and the accent needle marks the live value between ticks.
    private static let tickCount = 20
    /// Padding beyond the arc so the needle, its glow and the icon aren't clipped.
    private static let margin: CGFloat = 46

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        detent: Double,
        corner: DialCorner,
        systemImage: String,
        label: String,
        readout: String,
        radius: CGFloat = 118,
        tint: DialTint? = nil,
        soundEnabled: Bool = false,
        onBegin: @escaping () -> Void = {},
        onCommit: @escaping () -> Void = {}
    ) {
        self._value = value
        self.range = range
        self.detent = detent
        self.corner = corner
        self.systemImage = systemImage
        self.label = label
        self.readout = readout
        self.radius = radius
        self.tint = tint
        self.soundEnabled = soundEnabled
        self.onBegin = onBegin
        self.onCommit = onCommit
        _rawValue = State(initialValue: value.wrappedValue)
    }

    private var side: CGFloat { radius + Self.margin }
    private var boxSize: CGSize { CGSize(width: side, height: side) }
    private var isBipolar: Bool { range.lowerBound < 0 }
    private var span: Double { range.upperBound - range.lowerBound }
    private var t: Double { span > 0 ? (value - range.lowerBound) / span : 0 }
    /// Where the accent fill starts: the centre for a bipolar tool, the floor for a positive-only one.
    private var fillOrigin: Double { isBipolar ? 0.5 : 0 }
    private var detentIndex: Int { Int((value / detent).rounded()) }
    private var lowIndex: Int { Int((range.lowerBound / detent).rounded()) }
    private var highIndex: Int { Int((range.upperBound / detent).rounded()) }
    private var isActive: Bool { scrubbing || abs(value) > 1e-9 }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            cornerScrim
            ticks
            fill
            needle
            badge
            // The scrub band sits on top but only claims the annulus around the arc, so it never
            // steals a tap meant for the badge (double-tap to zero) or for the photo.
            Color.clear
                .contentShape(ArcBand(corner: corner,
                                      inner: radius - 34,
                                      outer: radius + 22))
                .gesture(scrub)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) dial")
        .accessibilityValue(readout)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(by: detent)
            case .decrement: nudge(by: -detent)
            default: break
            }
        }
        .sensoryFeedback(trigger: detentIndex) { _, new in
            if new == lowIndex || new == highIndex { return DialFeel.boundHaptic }
            return (new == 0 && isBipolar) ? DialFeel.zeroHaptic : DialFeel.tickHaptic
        }
    }

    // MARK: Layers

    /// Keeps ticks and glyphs legible over a bright photo without a hard-edged plate.
    private var cornerScrim: some View {
        RadialGradient(
            colors: [.black.opacity(0.5), .black.opacity(0.18), .clear],
            center: corner.unitPoint,
            startRadius: 0,
            endRadius: side
        )
        .allowsHitTesting(false)
    }

    private var ticks: some View {
        // Resolved up front (colours included) so the renderer only walks plain values — nothing it
        // touches depends on the view or on actor-isolated state.
        let specs = tickSpecs
        let radius = self.radius
        let corner = self.corner
        return Canvas { ctx, size in
            for spec in specs {
                var path = Path()
                path.move(to: corner.point(at: spec.t, radius: radius - spec.length, in: size))
                path.addLine(to: corner.point(at: spec.t, radius: radius, in: size))
                ctx.stroke(path,
                           with: .color(spec.color),
                           style: StrokeStyle(lineWidth: spec.width, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    /// One entry per tick: three tiers of length like the ruler's ticks, a whisper of the tool's colour
    /// axis where it has one, and the accent on a bipolar dial's centre.
    private var tickSpecs: [TickSpec] {
        let accent = Theme.accent
        return (0...Self.tickCount).map { i in
            let t = Double(i) / Double(Self.tickCount)
            let isMajor = i % 5 == 0
            let isZero = isBipolar && i == Self.tickCount / 2
            let base = isZero ? accent : (tint?.color(at: t) ?? .white)
            return TickSpec(
                t: t,
                length: isMajor ? 13 : 8,
                width: isMajor ? 2 : 1.5,
                color: base.opacity(isZero ? 0.9 : (isMajor ? 0.55 : 0.3))
            )
        }
    }

    /// The accent trace from the fill origin out to the current value — "how far off neutral am I".
    private var fill: some View {
        ArcFill(t: t, origin: fillOrigin, corner: corner, radius: radius - 5)
            .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .animation(scrubbing || reduceMotion ? nil : Theme.Motion.snappy, value: t)
            .allowsHitTesting(false)
    }

    private var needle: some View {
        Capsule()
            .fill(Theme.accent)
            .frame(width: 3.5, height: 26)
            .shadow(color: Theme.accent.opacity(0.55), radius: 5)
            .rotationEffect(.radians(corner.angle(at: t) - .pi / 2))
            .position(corner.point(at: t, radius: radius - 5, in: boxSize))
            .animation(scrubbing || reduceMotion ? nil : Theme.Motion.snappy, value: t)
            .allowsHitTesting(false)
    }

    /// Tool glyph + live value, seated on the diagonal inside the fan. Double-tap to zero the tool,
    /// the same shortcut the ruler dial gives on its centre mark.
    private var badge: some View {
        VStack(spacing: 1) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
            if isActive {
                Text(readout)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            if scrubbing {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(isActive ? Theme.accent : .white)
        .shadow(color: .black.opacity(0.7), radius: 4)
        .animation(reduceMotion ? nil : Theme.Motion.snappy, value: isActive)
        .frame(width: 76, height: 60)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { zeroOut() }
        .position(corner.point(at: 0.5, radius: radius * 0.44, in: boxSize))
    }

    // MARK: Scrubbing

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { v in
                let apex = corner.apex(in: boxSize)
                let dx = v.location.x - apex.x, dy = v.location.y - apex.y
                let angle = atan2(dy, dx)
                guard let previous = lastAngle else {
                    // First movement only seats the gesture — touching down never nudges the value.
                    lastAngle = angle
                    rawValue = value
                    scrubbing = true
                    onBegin()
                    return
                }
                lastAngle = angle
                // Shortest way round, so crossing ±π can't fling the value.
                var delta = angle - previous
                while delta > .pi { delta -= 2 * .pi }
                while delta < -.pi { delta += 2 * .pi }
                // Arc length actually travelled, at the radius the finger is on (clamped so a touch
                // drifting toward the apex doesn't turn into a huge angular swing).
                let touchRadius = min(max(hypot(dx, dy), radius * 0.55), radius * 1.5)
                let travel = delta * corner.direction * Double(touchRadius)
                let speed = Double(hypot(v.velocity.width, v.velocity.height))
                let step = travel / Double(DialFeel.arcPointsPerDetent) * detent * DialFeel.gain(forSpeed: speed)
                rawValue = clamp(rawValue + step)
                let snapped = clamp((rawValue / detent).rounded() * detent)
                if abs(snapped - value) > 1e-9 {
                    value = snapped
                    if soundEnabled { DialSound.tick() }
                }
            }
            .onEnded { _ in
                lastAngle = nil
                scrubbing = false
                onCommit()
            }
    }

    private func clamp(_ v: Double) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }

    private func nudge(by delta: Double) {
        let next = clamp(value + delta)
        guard abs(next - value) > 1e-9 else { return }
        onBegin()
        value = next
        rawValue = next
        onCommit()
    }

    private func zeroOut() {
        guard abs(value) > 1e-9 else { return }
        onBegin()
        value = 0
        rawValue = 0
        onCommit()
        Haptics.impact(.rigid)
    }
}

// MARK: Drawing

/// A single tick, fully resolved — the renderer needs no context beyond these numbers.
private nonisolated struct TickSpec: Sendable {
    let t: Double
    let length: CGFloat
    let width: CGFloat
    let color: Color
}

// MARK: Shapes

/// The accent trace along the arc, from `origin` to `t`. Animatable so the trace grows and shrinks
/// with the value instead of snapping.
private nonisolated struct ArcFill: Shape {
    var t: Double
    let origin: Double
    let corner: DialCorner
    let radius: CGFloat

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Walked as a polyline rather than `addArc`, whose clockwise flag is ambiguous in SwiftUI's
        // flipped space — this can only ever draw the short way round.
        let low = min(origin, t), high = max(origin, t)
        var path = Path()
        guard high - low > 0.001 else { return path }
        let steps = 24
        for i in 0...steps {
            let p = corner.point(at: low + (high - low) * Double(i) / Double(steps),
                                 radius: radius, in: rect.size)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

/// The annulus around the tick fan — used as the dial's hit area so the rest of the corner (and the
/// photo behind it) stays touchable.
private nonisolated struct ArcBand: Shape {
    let corner: DialCorner
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 32
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let p = corner.point(at: t, radius: outer, in: rect.size)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let t = Double(i) / Double(steps)
            path.addLine(to: corner.point(at: t, radius: inner, in: rect.size))
        }
        path.closeSubpath()
        return path
    }
}
