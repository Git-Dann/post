import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// A horizontal strip of one-tap looks, each rendered as a live thumbnail of the current image.
/// Tapping a style applies its recipe (then it's still tweakable on the dials).
public struct StyleStrip: View {
    private let source: CIImage
    private let styles: [Style]
    private let onPick: (Style) -> Void

    @State private var thumbnails: [String: UIImage] = [:]

    private static let context = CIContext(options: [.cacheIntermediates: false])

    public init(source: CIImage, styles: [Style], onPick: @escaping (Style) -> Void) {
        self.source = source
        self.styles = styles
        self.onPick = onPick
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
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
        Button {
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
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
                Text(style.name)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.name) style")
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
