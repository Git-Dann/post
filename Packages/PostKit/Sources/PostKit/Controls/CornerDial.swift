import SwiftUI

/// Which screen corner an arc dial is seated in.
public nonisolated enum DialCorner: String, CaseIterable, Sendable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var isTrailing: Bool { self == .topTrailing || self == .bottomTrailing }
    var isBottom: Bool { self == .bottomLeading || self == .bottomTrailing }

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
}

/// A unit direction in a dial's own space. Quarter turns are named for how they read on screen
/// (SwiftUI's y grows downward, so "left" is anticlockwise as drawn).
public nonisolated struct DialVector: Sendable, Equatable {
    public var dx: CGFloat
    public var dy: CGFloat

    var turnedLeft: DialVector { DialVector(dx: -dy, dy: dx) }
    var turnedRight: DialVector { DialVector(dx: dy, dy: -dx) }
}

/// The tick contour for one corner: two straight runs, each parallel to the screen edge it follows,
/// joined by a rounded corner — so the ruler traces the outline of the device instead of radiating
/// out of the corner. Ticks stand perpendicular to it, like markings machined into a bezel.
///
/// Everything a ``CornerDial`` draws or touches (ticks, needle, trace, hit band, the readout pocket)
/// comes from ``sample(_:)``, so the shape is described exactly once.
public nonisolated struct DialContour: Sendable {
    public let corner: DialCorner
    /// How far the outer tick tips sit inside the display's edges. The same on all four sides — an even
    /// gap all the way round is what makes the ruler read as engraved into the screen's own outline.
    public var edgeGap: CGFloat
    /// The screen's corner radius. The ruler's corner is concentric with it, so the ticks turn exactly
    /// as the glass does rather than cutting a tighter bend across it.
    public var displayCornerRadius: CGFloat
    /// Straight run along the top/bottom edge — the long one, since width is the plentiful axis.
    public var horizontalRun: CGFloat
    /// Straight run along the leading/trailing edge. Kept short so the two dials sharing a side leave
    /// a gap between them for the action cluster and the category swipe.
    public var verticalRun: CGFloat

    public init(
        corner: DialCorner,
        edgeGap: CGFloat = 12,
        displayCornerRadius: CGFloat = 55,
        horizontalRun: CGFloat = 116,
        verticalRun: CGFloat = 48
    ) {
        self.corner = corner
        self.edgeGap = edgeGap
        self.displayCornerRadius = displayCornerRadius
        self.horizontalRun = horizontalRun
        self.verticalRun = verticalRun
    }

    /// Radius of the tick-tip contour — the display's corner, brought in by the edge gap.
    public var cornerRadius: CGFloat { max(displayCornerRadius - edgeGap, 10) }

    /// Where the touch strip along the ruler starts and ends, as insets in from the tick tips. Bottom
    /// corners begin theirs further in, so a scrub can't be mistaken for the home-indicator swipe.
    public var hitStart: CGFloat { corner.isBottom ? 10 : 0 }
    public var hitEnd: CGFloat { hitStart + 42 }

    /// The box the dial occupies in its corner.
    public var size: CGSize {
        CGSize(width: edgeGap + cornerRadius + horizontalRun,
               height: edgeGap + cornerRadius + verticalRun)
    }

    /// Total finger travel from one end of the ruler to the other.
    public var length: CGFloat { verticalRun + cornerRadius * .pi / 2 + horizontalRun }

    private var apex: CGPoint {
        CGPoint(x: corner.isTrailing ? size.width : 0, y: corner.isBottom ? size.height : 0)
    }
    private var inwardX: CGFloat { corner.isTrailing ? -1 : 1 }
    private var inwardY: CGFloat { corner.isBottom ? -1 : 1 }

    /// The middle of the rounded corner — a pocket the tick tips curve around, where the readout sits.
    public var pocket: CGPoint {
        CGPoint(x: apex.x + inwardX * (edgeGap + cornerRadius),
                y: apex.y + inwardY * (edgeGap + cornerRadius))
    }

    /// Clearance from ``pocket`` to the nearest tick, for sizing what goes in there.
    public func pocketRadius(tickLength: CGFloat) -> CGFloat { cornerRadius - tickLength }

    /// Tick tip and outward normal at value position `t` (0 = range floor, 1 = ceiling).
    ///
    /// The walk runs side-edge → corner → top/bottom edge; the bottom corners read it backwards. Either
    /// way the high end of the range is the end further up the screen, so dragging a finger up the
    /// ruler raises the value in all four corners.
    public func sample(_ t: Double) -> (point: CGPoint, outward: DialVector) {
        var travelled = Double(min(max(t, 0), 1)) * Double(length)
        if corner.isBottom { travelled = Double(length) - travelled }
        let arc = Double(cornerRadius) * .pi / 2

        let u: CGFloat, v: CGFloat, nu: CGFloat, nv: CGFloat
        if travelled <= Double(verticalRun) {
            u = edgeGap
            v = edgeGap + cornerRadius + (verticalRun - CGFloat(travelled))
            nu = -1
            nv = 0
        } else if travelled <= Double(verticalRun) + arc {
            let phi = (travelled - Double(verticalRun)) / Double(cornerRadius)
            u = edgeGap + cornerRadius * (1 - CGFloat(cos(phi)))
            v = edgeGap + cornerRadius * (1 - CGFloat(sin(phi)))
            nu = -CGFloat(cos(phi))
            nv = -CGFloat(sin(phi))
        } else {
            let run = min(CGFloat(travelled - Double(verticalRun) - arc), horizontalRun)
            u = edgeGap + cornerRadius + run
            v = edgeGap
            nu = 0
            nv = -1
        }

        return (
            CGPoint(x: apex.x + inwardX * u, y: apex.y + inwardY * v),
            DialVector(dx: inwardX * nu, dy: inwardY * nv)
        )
    }

    /// A point `inset` points in from the tick tips (0 = the tip itself).
    public func point(_ t: Double, inset: CGFloat) -> CGPoint {
        let s = sample(t)
        return CGPoint(x: s.point.x - s.outward.dx * inset, y: s.point.y - s.outward.dy * inset)
    }

    /// The direction of increasing value at `t` — what a drag gets projected onto while scrubbing.
    public func tangent(_ t: Double) -> DialVector {
        let outward = sample(t).outward
        return corner.isTrailing ? outward.turnedRight : outward.turnedLeft
    }

    /// The position on the ruler nearest `point`. Scrubbing reads the ruler's direction *under the
    /// finger* — not at the current value, which may be round the corner from where you're touching.
    public func nearestPosition(to point: CGPoint) -> Double {
        let steps = 72   // ~3.5pt apart; ample for reading a direction
        var best = 0.0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let candidate = self.point(t, inset: 0)
            let distance = hypot(candidate.x - point.x, candidate.y - point.y)
            if distance < bestDistance {
                bestDistance = distance
                best = t
            }
        }
        return best
    }
}

/// The landscape counterpart to ``HapticDial``: a ruler bent around a screen corner, following the
/// contour of the device, so four adjustments can sit around the photo at once while the image keeps
/// the middle of the screen to itself.
///
/// Feel matches the ruler dial — relative scrubbing (nothing jumps when you touch down), a drag
/// projected onto the ruler so it tracks your finger one-to-one, a haptic click per detent, a fuller
/// thunk on a bipolar zero, a rigid tap at the ends, and pointer-style acceleration so a slow drag is
/// precise and a quick sweep travels. Gearing lives in ``DialFeel``.
public struct CornerDial: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let detent: Double
    private let contour: DialContour
    private let systemImage: String
    private let label: String
    private let readout: String
    private let tint: DialTint?
    private let soundEnabled: Bool
    private let onBegin: () -> Void
    private let onCommit: () -> Void

    /// Unsnapped position, so sub-detent movement accumulates instead of being rounded away.
    @State private var rawValue: Double = 0
    @State private var lastLocation: CGPoint?
    @State private var scrubbing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ticks on the ruler. Coarser than the detents (a 200-step range would be a solid smear) — the
    /// ruler reads as a gauge of the range, and the accent needle marks the live value between ticks.
    /// 30 intervals puts them ~8pt apart, the same density as the ruler dial's pitch.
    private static let tickCount = 30
    private static let majorTick: CGFloat = 14
    private static let mediumTick: CGFloat = 11
    private static let minorTick: CGFloat = 8

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        detent: Double,
        corner: DialCorner,
        systemImage: String,
        label: String,
        readout: String,
        contour: DialContour? = nil,
        tint: DialTint? = nil,
        soundEnabled: Bool = false,
        onBegin: @escaping () -> Void = {},
        onCommit: @escaping () -> Void = {}
    ) {
        self._value = value
        self.range = range
        self.detent = detent
        self.contour = contour ?? DialContour(corner: corner)
        self.systemImage = systemImage
        self.label = label
        self.readout = readout
        self.tint = tint
        self.soundEnabled = soundEnabled
        self.onBegin = onBegin
        self.onCommit = onCommit
        _rawValue = State(initialValue: value.wrappedValue)
    }

    private var corner: DialCorner { contour.corner }
    private var isBipolar: Bool { range.lowerBound < 0 }
    private var span: Double { range.upperBound - range.lowerBound }
    private var t: Double { span > 0 ? (value - range.lowerBound) / span : 0 }
    /// Where the accent trace starts: the centre for a bipolar tool, the floor for a positive-only one.
    private var traceOrigin: Double { isBipolar ? 0.5 : 0 }
    private var detentIndex: Int { Int((value / detent).rounded()) }
    private var lowIndex: Int { Int((range.lowerBound / detent).rounded()) }
    private var highIndex: Int { Int((range.upperBound / detent).rounded()) }
    private var isActive: Bool { scrubbing || abs(value) > 1e-9 }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            cornerScrim
            ticks
            trace
            needle
            badge
            // The scrub band sits on top but only claims the strip along the ruler, so it never steals
            // a tap meant for the readout (double-tap to zero) or for the photo.
            Color.clear
                .contentShape(ContourBand(contour: contour, from: contour.hitStart, to: contour.hitEnd))
                .gesture(scrub)
        }
        .frame(width: contour.size.width, height: contour.size.height)
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
            endRadius: max(contour.size.width, contour.size.height)
        )
        .allowsHitTesting(false)
    }

    private var ticks: some View {
        // Resolved up front (colours included) so the renderer only walks plain values — nothing it
        // touches depends on the view or on actor-isolated state.
        let specs = tickSpecs
        let contour = self.contour
        return Canvas { ctx, _ in
            for spec in specs {
                var path = Path()
                path.move(to: contour.point(spec.t, inset: 0))
                path.addLine(to: contour.point(spec.t, inset: spec.length))
                ctx.stroke(path,
                           with: .color(spec.color),
                           style: StrokeStyle(lineWidth: spec.width, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    /// One entry per tick. Same three tiers as the ruler dial — 10s tall, 5s a medium step, the rest
    /// short — plus a whisper of the tool's colour axis where it has one, and the accent on a bipolar
    /// dial's centre (which lands right on the corner, so neutral reads as the corner itself).
    private var tickSpecs: [TickSpec] {
        let accent = Theme.accent
        return (0...Self.tickCount).map { i in
            let isTen = i % 10 == 0
            let isFive = i % 5 == 0
            let isZero = isBipolar && i == Self.tickCount / 2
            let t = Double(i) / Double(Self.tickCount)
            let base = isZero ? accent : (tint?.color(at: t) ?? .white)
            return TickSpec(
                t: t,
                length: isZero || isTen ? Self.majorTick : (isFive ? Self.mediumTick : Self.minorTick),
                width: isTen ? 2 : (isFive ? 1.75 : 1.5),
                color: base.opacity(isZero ? 0.9 : (isTen ? 0.55 : (isFive ? 0.45 : 0.3)))
            )
        }
    }

    /// The accent trace from neutral out to the current value — "how far off neutral am I".
    private var trace: some View {
        ContourTrace(t: t, origin: traceOrigin, contour: contour, inset: 3)
            .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .animation(scrubbing || reduceMotion ? nil : Theme.Motion.snappy, value: t)
            .allowsHitTesting(false)
    }

    private var needle: some View {
        let sample = contour.sample(t)
        // Stands perpendicular to the ruler, like the ticks, and overhangs them at both ends.
        let angle = atan2(sample.outward.dy, sample.outward.dx) - .pi / 2
        return Capsule()
            .fill(Theme.accent)
            .frame(width: 3.5, height: 26)
            .shadow(color: Theme.accent.opacity(0.55), radius: 5)
            .rotationEffect(.radians(Double(angle)))
            .position(contour.point(t, inset: 9))
            .animation(scrubbing || reduceMotion ? nil : Theme.Motion.snappy, value: t)
            .allowsHitTesting(false)
    }

    /// Tool glyph + live value, sitting in the pocket the corner curves around. Double-tap to zero the
    /// tool, the same shortcut the ruler dial gives on its centre mark.
    private var badge: some View {
        let clearance = contour.pocketRadius(tickLength: Self.majorTick)
        return VStack(spacing: 1) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
            if isActive {
                Text(readout)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .fixedSize()
            }
            if scrubbing {
                // Overhangs the pocket rather than wrapping inside it — it's only up while your finger
                // is down, and the ticks it reaches over are 14pt of hairline.
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize()
            }
        }
        .foregroundStyle(isActive ? Theme.accent : .white)
        .shadow(color: .black.opacity(0.7), radius: 4)
        .animation(reduceMotion ? nil : Theme.Motion.snappy, value: isActive)
        // Sized to the pocket, so the readout can never crowd the ticks curving around it.
        .frame(width: clearance * 1.5, height: clearance * 1.05)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { zeroOut() }
        .position(contour.pocket)
    }

    // MARK: Scrubbing

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { v in
                guard let previous = lastLocation else {
                    // First movement only seats the gesture — touching down never nudges the value.
                    lastLocation = v.location
                    rawValue = value
                    scrubbing = true
                    onBegin()
                    return
                }
                lastLocation = v.location
                // How far the finger moved *along* the ruler: its travel projected onto the ruler's
                // direction where the finger is. Straight runs and the corner curve behave identically,
                // and the dial tracks the finger rather than the angle it happens to subtend.
                let tangent = contour.tangent(contour.nearestPosition(to: previous))
                let travel = (v.location.x - previous.x) * tangent.dx + (v.location.y - previous.y) * tangent.dy
                let speed = Double(hypot(v.velocity.width, v.velocity.height))
                let step = Double(travel) / Double(DialFeel.arcPointsPerDetent) * detent * DialFeel.gain(forSpeed: speed)
                rawValue = clamp(rawValue + step)
                let snapped = clamp((rawValue / detent).rounded() * detent)
                if abs(snapped - value) > 1e-9 {
                    value = snapped
                    if soundEnabled { DialSound.tick() }
                }
            }
            .onEnded { _ in
                lastLocation = nil
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

/// Walks the contour as a polyline. Sampling (rather than piecing arcs and lines together) keeps the
/// drawn shapes in lockstep with `DialContour.sample`, which is also what the gesture reads.
private nonisolated func contourPath(
    _ contour: DialContour, from low: Double, to high: Double, inset: CGFloat, steps: Int
) -> Path {
    var path = Path()
    guard high > low, steps > 0 else { return path }
    for i in 0...steps {
        let p = contour.point(low + (high - low) * Double(i) / Double(steps), inset: inset)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    return path
}

/// The accent trace along the ruler, from `origin` to `t`. Animatable so it grows and shrinks with the
/// value instead of snapping.
private nonisolated struct ContourTrace: Shape {
    var t: Double
    let origin: Double
    let contour: DialContour
    let inset: CGFloat

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let low = min(origin, t), high = max(origin, t)
        guard high - low > 0.001 else { return Path() }
        return contourPath(contour, from: low, to: high, inset: inset, steps: 28)
    }
}

/// The strip along the ruler — the dial's hit area, so the rest of the corner (and the photo behind
/// it) stays touchable. `from` and `to` are insets in from the tick tips.
private nonisolated struct ContourBand: Shape {
    let contour: DialContour
    let from: CGFloat
    let to: CGFloat

    func path(in rect: CGRect) -> Path {
        let steps = 36
        var path = contourPath(contour, from: 0, to: 1, inset: from, steps: steps)
        for i in stride(from: steps, through: 0, by: -1) {
            path.addLine(to: contour.point(Double(i) / Double(steps), inset: to))
        }
        path.closeSubpath()
        return path
    }
}
