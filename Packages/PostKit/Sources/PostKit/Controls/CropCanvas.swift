import SwiftUI

/// The crop image, dimmed surround, and rule-of-thirds frame — drawn inside the editor's rounded
/// card. The corner grips live in `CropHandles`, drawn UNCLIPPED on top so they're never cut off by
/// the card's rounded corners. The card is sized to the image's aspect, so this view's bounds ==
/// the image rect and the crop is simply normalized to it.
struct CropCanvas: View {
    let model: EditorModel
    @State private var dragStartOrigin: CGPoint?

    private var crop: CGRect { model.cropWorkingRect }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                MetalImageView(image: model.cropDisplayImage)
                dimMask(size)
                grid(rectIn(size))
                // Drag inside the crop to reposition it. Sits below the dial overlay, so the dial
                // still receives touches; outside the crop (dim area) doesn't move anything.
                Rectangle().fill(.clear)
                    .frame(width: crop.width * size.width, height: crop.height * size.height)
                    .position(x: crop.midX * size.width, y: crop.midY * size.height)
                    .contentShape(Rectangle())
                    .gesture(moveGesture(size))
            }
        }
    }

    private func rectIn(_ size: CGSize) -> CGRect {
        CGRect(x: crop.minX * size.width, y: crop.minY * size.height,
               width: crop.width * size.width, height: crop.height * size.height)
    }

    private func dimMask(_ size: CGSize) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .reverseMask {
                Rectangle()
                    .frame(width: crop.width * size.width, height: crop.height * size.height)
                    .position(x: crop.midX * size.width, y: crop.midY * size.height)
            }
            .allowsHitTesting(false)
    }

    private func grid(_ rect: CGRect) -> some View {
        Path { p in
            p.addRect(rect)
            for i in 1...2 {
                let x = rect.minX + rect.width * CGFloat(i) / 3
                p.move(to: CGPoint(x: x, y: rect.minY)); p.addLine(to: CGPoint(x: x, y: rect.maxY))
                let y = rect.minY + rect.height * CGFloat(i) / 3
                p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(.white.opacity(0.85), lineWidth: 1)
        .allowsHitTesting(false)
    }

    private func moveGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                if dragStartOrigin == nil { dragStartOrigin = crop.origin; Haptics.selection() }
                let start = dragStartOrigin ?? crop.origin
                var o = CGPoint(x: start.x + v.translation.width / size.width,
                                y: start.y + v.translation.height / size.height)
                o.x = min(max(0, o.x), 1 - crop.width)
                o.y = min(max(0, o.y), 1 - crop.height)
                model.cropWorkingRect.origin = o
            }
            .onEnded { _ in dragStartOrigin = nil }
    }
}

/// The four corner resize grips — Photos-style L-shaped brackets, drawn unclipped over the card so
/// they stay fully visible even when the crop fills the frame.
struct CropHandles: View {
    let model: EditorModel
    @State private var active: Handle?
    private let minSize: CGFloat = 0.12

    private var crop: CGRect { model.cropWorkingRect }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let rect = CGRect(x: crop.minX * size.width, y: crop.minY * size.height,
                              width: crop.width * size.width, height: crop.height * size.height)
            ForEach(Handle.corners, id: \.self) { handle in
                Color.clear
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .overlay(CornerBracket(handle: handle, active: active == handle))
                    .position(handle.point(in: rect))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                if active == nil { Haptics.selection() }   // first touch on a grip
                                active = handle
                                resize(handle, to: v.location, size: size)
                            }
                            .onEnded { _ in active = nil; Haptics.selection() }
                    )
                    .accessibilityLabel("\(handle.name) crop handle")
                    .accessibilityHint("Drag to resize the crop")
            }
        }
    }

    private func resize(_ handle: Handle, to location: CGPoint, size: CGSize) {
        let nx = min(max(0, location.x / size.width), 1)
        let ny = min(max(0, location.y / size.height), 1)

        if let ratio = model.cropAspectRatio {
            // Locked: anchor the opposite corner, keep displayed aspect == ratio.
            let k = model.cropPreviewAspect / ratio   // h_n = w_n * k
            let ax = handle.isLeft ? crop.maxX : crop.minX
            let ay = handle.isTop ? crop.maxY : crop.minY
            var w = max(abs(nx - ax), abs(ny - ay) / k)
            var h = w * k
            let maxW = handle.isLeft ? ax : 1 - ax
            let maxH = handle.isTop ? ay : 1 - ay
            if w > maxW { w = maxW; h = w * k }
            if h > maxH { h = maxH; w = h / k }
            w = max(w, minSize); h = max(h, minSize)
            let cx = handle.isLeft ? ax - w : ax + w
            let cy = handle.isTop ? ay - h : ay + h
            model.cropWorkingRect = CGRect(x: min(ax, cx), y: min(ay, cy), width: w, height: h)
            return
        }

        var r = crop
        if handle.isLeft { r.size.width = max(minSize, crop.maxX - nx); r.origin.x = min(nx, crop.maxX - minSize) }
        if handle.isRight { r.size.width = max(minSize, nx - crop.minX) }
        if handle.isTop { r.size.height = max(minSize, crop.maxY - ny); r.origin.y = min(ny, crop.maxY - minSize) }
        if handle.isBottom { r.size.height = max(minSize, ny - crop.minY) }
        model.cropWorkingRect = r.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

private enum Handle: Hashable {
    case topLeft, topRight, bottomLeft, bottomRight
    static let corners: [Handle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isRight: Bool { self == .topRight || self == .bottomRight }
    var isTop: Bool { self == .topLeft || self == .topRight }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }

    var name: String {
        switch self {
        case .topLeft: "Top-left"
        case .topRight: "Top-right"
        case .bottomLeft: "Bottom-left"
        case .bottomRight: "Bottom-right"
        }
    }

    /// The frame corner the bracket's elbow hugs — its arms then run inward along the two edges.
    var bracketAlignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

/// A single L-shaped corner grip, like the brackets in Apple's Photos crop. Two rounded arms meet at
/// an elbow that hugs the crop corner; the arms run inward along the two edges. Nudges larger while
/// being dragged for a little tactile feedback.
private struct CornerBracket: View {
    let handle: Handle
    let active: Bool

    private let arm: CGFloat = 20
    private let thickness: CGFloat = 3.5

    var body: some View {
        let align = handle.bracketAlignment
        ZStack(alignment: align) {
            RoundedRectangle(cornerRadius: thickness / 2).frame(width: arm, height: thickness)
            RoundedRectangle(cornerRadius: thickness / 2).frame(width: thickness, height: arm)
        }
        .frame(width: arm, height: arm, alignment: align)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        // Shift the elbow from the bracket's centre onto the crop corner (centre of the 44pt frame).
        .offset(x: handle.isLeft ? arm / 2 : -arm / 2,
                y: handle.isTop ? arm / 2 : -arm / 2)
        .scaleEffect(active ? 1.18 : 1, anchor: .center)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: active)
    }
}

private extension View {
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
