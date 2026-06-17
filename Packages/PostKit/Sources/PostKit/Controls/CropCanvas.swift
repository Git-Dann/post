import SwiftUI

/// The in-place crop interaction drawn over the editor's framed image: a draggable crop frame with
/// corner handles, a rule-of-thirds grid, and a dimmed surround. The editor sizes the card to the
/// crop preview's aspect, so this view's bounds == the image rect and the crop is simply normalized
/// to it (no letterbox maths). Working state lives on the model; Done commits it.
struct CropCanvas: View {
    let model: EditorModel
    private let minSize: CGFloat = 0.12

    @State private var activeHandle: Handle?
    @State private var dragStartOrigin: CGPoint?

    private var crop: CGRect { model.cropWorkingRect }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                MetalImageView(image: model.cropDisplayImage)
                dimMask(size)
                cropFrame(size)
            }
            .contentShape(Rectangle())
        }
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

    private func cropFrame(_ size: CGSize) -> some View {
        let rect = CGRect(x: crop.minX * size.width, y: crop.minY * size.height,
                          width: crop.width * size.width, height: crop.height * size.height)
        return ZStack {
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

            ForEach(Handle.corners, id: \.self) { handle in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.accent)
                    .frame(width: 22, height: 22)
                    .position(handle.point(in: rect))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in activeHandle = handle; resize(handle, to: v.location, size: size) }
                            .onEnded { _ in activeHandle = nil; Haptics.selection() }
                    )
            }
        }
        .contentShape(Rectangle())
        .gesture(moveGesture(size))
    }

    private func moveGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                guard activeHandle == nil else { return }
                if dragStartOrigin == nil { dragStartOrigin = crop.origin }
                let start = dragStartOrigin ?? crop.origin
                var o = CGPoint(x: start.x + v.translation.width / size.width,
                                y: start.y + v.translation.height / size.height)
                o.x = min(max(0, o.x), 1 - crop.width)
                o.y = min(max(0, o.y), 1 - crop.height)
                model.cropWorkingRect.origin = o
            }
            .onEnded { _ in dragStartOrigin = nil }
    }

    private func resize(_ handle: Handle, to location: CGPoint, size: CGSize) {
        let nx = min(max(0, location.x / size.width), 1)
        let ny = min(max(0, location.y / size.height), 1)
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

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
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
