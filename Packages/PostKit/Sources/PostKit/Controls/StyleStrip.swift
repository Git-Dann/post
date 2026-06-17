import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// A horizontal strip of one-tap looks, each rendered as a live thumbnail of the current image.
/// Tapping a style applies its recipe (then it's still tweakable on the dials).
public struct StyleStrip: View {
    private let source: CIImage
    private let styles: [Style]
    /// The user's saved looks (the "Yours" section).
    private let userStyles: [Style]
    /// The currently-applied look, so the strip opens scrolled to (and highlighting) it.
    private let activeStyleID: String?
    /// When set, a leading "Save" card appears in the Yours section (capture the current look).
    private let onSaveCurrent: (() -> Void)?
    /// When set, user looks gain a Delete context-menu action.
    private let onDelete: ((Style) -> Void)?
    private let onPick: (Style) -> Void

    @State private var thumbnails: [String: UIImage] = [:]
    /// Drives the staggered entrance: chips rise + fade in sequentially when the list opens.
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// All chips in display order, so each gets a stagger delay by its position.
    private var orderedStyles: [Style] {
        Style.baselines + houseStyles + collections.flatMap(\.styles) + userStyles
    }

    public init(source: CIImage, styles: [Style], userStyles: [Style] = [],
                activeStyleID: String? = nil,
                onSaveCurrent: (() -> Void)? = nil,
                onDelete: ((Style) -> Void)? = nil,
                onPick: @escaping (Style) -> Void) {
        self.source = source
        self.styles = styles
        self.userStyles = userStyles
        self.activeStyleID = activeStyleID
        self.onSaveCurrent = onSaveCurrent
        self.onDelete = onDelete
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
                    // The "Yours" section: a Save card (+ when there's a look to keep) and saved looks.
                    if onSaveCurrent != nil || !userStyles.isEmpty {
                        divider
                        if let onSaveCurrent { saveCard(onSaveCurrent) }
                        ForEach(userStyles) { chip($0) }
                    }
                }
                .padding(.horizontal, Theme.Space.l)
            }
            .task(id: source.extent.debugDescription) {
                renderThumbnails()
            }
            .onAppear {
                // Quick staggered entrance: the chips rise + fade in sequentially as the list opens.
                revealed = true
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
        // Stagger by position so the chips rise in sequence; capped so a far chip never waits too long.
        let stagger = min(Double(orderedStyles.firstIndex(of: style) ?? 0) * 0.04, 0.4)
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
        // Staggered entrance: each chip rises + fades in, sequentially, when the list opens.
        .offset(y: revealed ? 0 : 18)
        .opacity(revealed ? 1 : 0)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3).delay(stagger), value: revealed)
        .accessibilityLabel("\(style.name) style")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        // Saved looks can be deleted from a long-press menu.
        .contextMenu {
            if let onDelete, style.collection == UserStyleStore.collection {
                Button("Delete Look", systemImage: "trash", role: .destructive) { onDelete(style) }
            }
        }
    }

    /// The leading "Save" card in the Yours section — captures the current look as a new preset.
    private func saveCard(_ action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.impact(.soft)
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .frame(width: 60, height: 76)
                    .overlay(Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.accent))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
                Text("Save")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .offset(y: revealed ? 0 : 18)
        .opacity(revealed ? 1 : 0)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: revealed)
        .accessibilityLabel("Save current look")
    }

    private func renderThumbnails() {
        // Downscale the source once so thumbnails are cheap.
        let extent = source.extent
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty else { return }
        let target: CGFloat = 220
        let scale = min(1, target / max(extent.width, extent.height))
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        var result: [String: UIImage] = [:]
        for style in Style.baselines + styles + userStyles {
            let output = FilterPipeline.makeImage(source: small, state: style.recipe, grainScale: 1)
            if let cg = Self.context.createCGImage(output, from: output.extent) {
                result[style.id] = UIImage(cgImage: cg)
            }
        }
        thumbnails = result
    }
}
