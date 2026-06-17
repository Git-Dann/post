import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// A horizontal strip of one-tap looks, each rendered as a live thumbnail of the current image.
/// Tapping a style applies its recipe (then it's still tweakable on the dials).
public struct StyleStrip: View {
    private let source: CIImage
    private let styles: [Style]
    /// The currently-applied look, so the strip opens scrolled to (and highlighting) it.
    private let activeStyleID: String?
    private let onPick: (Style) -> Void

    @State private var thumbnails: [String: UIImage] = [:]

    private static let context = CIContext(options: [.cacheIntermediates: false])

    public init(source: CIImage, styles: [Style], activeStyleID: String? = nil,
                onPick: @escaping (Style) -> Void) {
        self.source = source
        self.styles = styles
        self.activeStyleID = activeStyleID
        self.onPick = onPick
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    // Baselines first: OG (the original) and ZERO (a flat "Process Zero" base).
                    ForEach(Style.baselines) { chip($0) }
                    // Divider, then the house looks.
                    divider
                    ForEach(houseStyles) { chip($0) }
                    // A divider before each collaborator collection (e.g. "Chunk").
                    ForEach(collections, id: \.name) { group in
                        divider
                        ForEach(group.styles) { chip($0) }
                    }
                }
                .padding(.horizontal, Theme.Space.l)
            }
            .task(id: source.extent.debugDescription) {
                renderThumbnails()
            }
            .onAppear {
                // Remember where you were: open the list at the active look rather than the front.
                guard let activeStyleID else { return }
                DispatchQueue.main.async { proxy.scrollTo(activeStyleID, anchor: .center) }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(width: 1, height: 76)
    }

    /// House looks have no collection; collaborator looks are grouped by their collection.
    private var houseStyles: [Style] { styles.filter { $0.collection == nil } }

    /// Collaborator collections in first-seen order, each with its styles.
    private var collections: [(name: String, styles: [Style])] {
        var order: [String] = []
        var byName: [String: [Style]] = [:]
        for style in styles {
            guard let c = style.collection else { continue }
            if byName[c] == nil { order.append(c) }
            byName[c, default: []].append(style)
        }
        return order.map { (name: $0, styles: byName[$0] ?? []) }
    }

    private func chip(_ style: Style) -> some View {
        let isActive = style.id == activeStyleID
        return Button {
            onPick(style)
            Haptics.impact(.soft)
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let image = thumbnails[style.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Theme.canvas
                    }
                }
                .frame(width: 60, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isActive ? Theme.accent : .white.opacity(0.15),
                                      lineWidth: isActive ? 2.5 : 1)
                )
                Text(style.name)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(isActive ? Theme.accent : .white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .id(style.id)
        // Dock-style magnifier: chips sit at full size in the body of the strip and taper — shrink
        // and dim — as they scroll toward either edge. Native `scrollTransition` (phase.value is 0
        // at rest, ±1 at the edges) interpolates it smoothly while you scroll.
        .scrollTransition { content, phase in
            let v = min(max(phase.value, -1), 1)
            return content
                .scaleEffect(1 - abs(v) * 0.22)   // full size at rest, ~0.78 at the edges
                .opacity(1 - abs(v) * 0.45)
        }
        .accessibilityLabel("\(style.name) style")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func renderThumbnails() {
        // Downscale the source once so thumbnails are cheap.
        let extent = source.extent
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty else { return }
        let target: CGFloat = 220
        let scale = min(1, target / max(extent.width, extent.height))
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        var result: [String: UIImage] = [:]
        for style in Style.baselines + styles {
            let output = FilterPipeline.makeImage(source: small, state: style.recipe, grainScale: 1)
            if let cg = Self.context.createCGImage(output, from: output.extent) {
                result[style.id] = UIImage(cgImage: cg)
            }
        }
        thumbnails = result
    }
}
