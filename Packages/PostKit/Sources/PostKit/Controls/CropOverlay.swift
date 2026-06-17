import SwiftUI

/// Geometry mode: a draggable crop frame over the (uncropped) image with a dimmed mask and a
/// rule-of-thirds grid, aspect-ratio chips, 90° rotate + flip, and a straighten wheel that reuses
/// `HapticDial`. Crop is edited in normalized UI space and committed to the recipe on Done.
public struct CropOverlay: View {
    private let model: EditorModel

    // Working geometry, seeded from the model and applied on Done.
    @State private var crop: CGRect          // normalized (0...1), top-left origin, in image space
    @State private var straighten: Double
    @State private var quarterTurns: Int
    @State private var flipH: Bool
    @State private var flipV: Bool
    @State private var aspect: AspectOption = .free
    @State private var activeHandle: Handle?

    private let minSize: CGFloat = 0.12

    public init(model: EditorModel) {
        self.model = model
        // Image space uses a bottom-left origin; convert the stored crop to top-left for UI.
        let c = model.state.crop
        _crop = State(initialValue: CGRect(x: c.x, y: 1 - c.y - c.height, width: c.width, height: c.height))
        _straighten = State(initialValue: model.state.straightenAngle)
        _quarterTurns = State(initialValue: model.state.rotationQuarterTurns)
        _flipH = State(initialValue: model.state.flippedHorizontally)
        _flipV = State(initialValue: model.state.flippedVertically)
    }

    private var displayImage: CIImage {
        model.croplessImage(straighten: straighten, quarterTurns: quarterTurns, flipH: flipH, flipV: flipV)
    }

    public var body: some View {
        VStack(spacing: Theme.Space.s) {
            topControls
            GeometryReader { geo in
                let fitted = fittedRect(in: geo.size)
                ZStack {
                    // Contained within this area (no .ignoresSafeArea) so the image doesn't bleed
                    // up behind the top rotate/flip controls.
                    MetalImageView(image: displayImage)
                    dimMask(fitted: fitted)
                    cropFrame(fitted: fitted)
                }
                .contentShape(Rectangle())
            }
            adjustControls
            actionBar
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: Top controls (rotate / flip)

    private var topControls: some View {
        HStack(spacing: Theme.Space.l) {
            GlassIconButton("rotate.left") {
                withAnimation(Theme.Motion.snappy) { quarterTurns = (quarterTurns + 3) % 4 }
                Haptics.impact(.light)
            }
            GlassIconButton("rotate.right") {
                withAnimation(Theme.Motion.snappy) { quarterTurns = (quarterTurns + 1) % 4 }
                Haptics.impact(.light)
            }
            GlassIconButton("arrow.left.and.right.righttriangle.left.righttriangle.right") {
                flipH.toggle(); Haptics.impact(.light)
            }
            GlassIconButton("arrow.up.and.down.righttriangle.up.righttriangle.down") {
                flipV.toggle(); Haptics.impact(.light)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
    }

    // MARK: Straighten wheel + aspect chips

    private var adjustControls: some View {
        VStack(spacing: Theme.Space.m) {
            HapticDial(
                value: $straighten,
                range: -0.4...0.4,
                detent: 0.0175  // ≈ 1° steps
            )
            .padding(.horizontal, Theme.Space.l)

            HStack(spacing: Theme.Space.s) {
                ForEach(AspectOption.allCases) { option in
                    aspectChip(option)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Space.l)
        }
        .padding(.vertical, Theme.Space.m)
    }

    // MARK: Action bar — the same Done + X as the editor (uniformity).

    private var actionBar: some View {
        Button {
            commit()
            model.isCropping = false
        } label: {
            Text("Done")
                .font(.system(.headline, design: .rounded))
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, 14)
        }
        .buttonStyle(.glass)   // same native translucent glass + size as the editor's Done
        .tint(.white)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            GlassIconButton("xmark") { model.isCropping = false }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.bottom, Theme.Space.s)
    }

    private func aspectChip(_ option: AspectOption) -> some View {
        let isSelected = option == aspect
        return Button {
            withAnimation(Theme.Motion.snappy) {
                aspect = option
                applyAspect(option)
            }
        } label: {
            Text(option.label)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(Theme.accent).interactive() : .regular.interactive(),
                     in: .capsule)
    }

    // MARK: Crop frame + mask

    private func dimMask(fitted: CGRect) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .reverseMask {
                Rectangle()
                    .frame(width: crop.width * fitted.width, height: crop.height * fitted.height)
                    .position(
                        x: fitted.minX + (crop.midX) * fitted.width,
                        y: fitted.minY + (crop.midY) * fitted.height
                    )
            }
            .allowsHitTesting(false)
    }

    private func cropFrame(fitted: CGRect) -> some View {
        let rect = CGRect(
            x: fitted.minX + crop.minX * fitted.width,
            y: fitted.minY + crop.minY * fitted.height,
            width: crop.width * fitted.width,
            height: crop.height * fitted.height
        )
        return ZStack {
            // Rule-of-thirds grid + border.
            Path { path in
                path.addRect(rect)
                for i in 1...2 {
                    let x = rect.minX + rect.width * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: rect.minY))
                    path.addLine(to: CGPoint(x: x, y: rect.maxY))
                    let y = rect.minY + rect.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.85), lineWidth: 1)

            ForEach(Handle.corners, id: \.self) { handle in
                cornerHandle(handle, in: rect, fitted: fitted)
            }
        }
        .contentShape(Rectangle())
        .gesture(moveGesture(fitted: fitted))
    }

    private func cornerHandle(_ handle: Handle, in rect: CGRect, fitted: CGRect) -> some View {
        let point = handle.point(in: rect)
        return RoundedRectangle(cornerRadius: 3)
            .fill(Theme.accent)
            .frame(width: 22, height: 22)
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        activeHandle = handle
                        resize(handle: handle, to: value.location, fitted: fitted)
                    }
                    .onEnded { _ in activeHandle = nil; Haptics.selection() }
            )
    }

    // MARK: Gestures

    private func moveGesture(fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard activeHandle == nil else { return }
                let dx = value.translation.width / fitted.width
                let dy = value.translation.height / fitted.height
                var origin = lastCropOrigin ?? crop.origin
                if lastCropOrigin == nil { lastCropOrigin = crop.origin }
                origin.x = min(max(0, origin.x + dx), 1 - crop.width)
                origin.y = min(max(0, origin.y + dy), 1 - crop.height)
                crop.origin = origin
            }
            .onEnded { _ in lastCropOrigin = nil }
    }

    @State private var lastCropOrigin: CGPoint?

    private func resize(handle: Handle, to location: CGPoint, fitted: CGRect) {
        // A manual handle drag is a free-form crop — drop any locked aspect ratio.
        if aspect != .free { aspect = .free }

        var nx = (location.x - fitted.minX) / fitted.width
        var ny = (location.y - fitted.minY) / fitted.height
        nx = min(max(0, nx), 1)
        ny = min(max(0, ny), 1)

        var newRect = crop
        if handle.isLeft { newRect.size.width = max(minSize, crop.maxX - nx); newRect.origin.x = min(nx, crop.maxX - minSize) }
        if handle.isRight { newRect.size.width = max(minSize, nx - crop.minX) }
        if handle.isTop { newRect.size.height = max(minSize, crop.maxY - ny); newRect.origin.y = min(ny, crop.maxY - minSize) }
        if handle.isBottom { newRect.size.height = max(minSize, ny - crop.minY) }
        crop = newRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: Aspect

    private func applyAspect(_ option: AspectOption) {
        guard let ratio = option.ratio else { return }   // .free / .original handled elsewhere
        let imageExtent = displayImage.extent
        let imageAspect = imageExtent.height > 0 ? imageExtent.width / imageExtent.height : 1
        // Convert desired ratio (w:h) in image pixels into normalized crop dimensions.
        let targetWOverH = ratio
        var w = 1.0
        var h = 1.0
        if targetWOverH > imageAspect {
            w = 1.0
            h = imageAspect / targetWOverH
        } else {
            h = 1.0
            w = targetWOverH / imageAspect
        }
        crop = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    // MARK: Layout helpers

    private func fittedRect(in size: CGSize) -> CGRect {
        let extent = displayImage.extent
        guard extent.width > 0, extent.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let inset: CGFloat = Theme.Space.l
        let avail = CGSize(width: size.width - inset * 2, height: size.height - inset * 2)
        let scale = min(avail.width / extent.width, avail.height / extent.height)
        let w = extent.width * scale
        let h = extent.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func commit() {
        // Convert UI (top-left) crop back to image space (bottom-left origin).
        let imageCrop = CropRect(
            x: crop.minX,
            y: 1 - crop.minY - crop.height,
            width: crop.width,
            height: crop.height
        )
        model.apply(
            crop: imageCrop,
            straighten: straighten,
            quarterTurns: quarterTurns,
            flipH: flipH,
            flipV: flipV
        )
    }
}

// MARK: - Supporting types

private enum Handle: Hashable {
    case topLeft, topRight, bottomLeft, bottomRight

    static let corners: [Handle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isRight: Bool { self == .topRight || self == .bottomRight }
    var isTop: Bool { self == .topLeft || self == .topRight }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

private enum AspectOption: String, CaseIterable, Identifiable {
    case free, square, fourThree, threeTwo, sixteenNine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: "Free"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenNine: "16:9"
        }
    }

    /// Width-over-height ratio, or nil for Free.
    var ratio: Double? {
        switch self {
        case .free: nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .threeTwo: 3.0 / 2.0
        case .sixteenNine: 16.0 / 9.0
        }
    }
}

private extension View {
    /// Masks `self` so that the supplied shape is *removed* (punches a hole).
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
