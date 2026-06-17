import SwiftUI

/// A non-selectable action chip in the tool strip (Styles, Crop) — distinct from the dial tools.
public struct ToolBarAction: Identifiable {
    public let id: String
    let title: String
    let systemImage: String
    let tinted: Bool
    let showsDot: Bool
    let handler: () -> Void

    public init(id: String, title: String, systemImage: String, tinted: Bool = false,
                showsDot: Bool = false, handler: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.tinted = tinted
        self.showsDot = showsDot
        self.handler = handler
    }
}

/// The scrollable strip of tools — leading action chips (Styles, Crop) followed by the selectable
/// dial adjustments as circular Liquid Glass chips. The selected tool tints; tools with an active
/// edit show a small accent dot.
public struct ToolBar: View {
    private let actions: [ToolBarAction]
    private let selected: EditTool?
    private let tools: [EditTool]
    private let editedTools: Set<EditTool>
    /// When false (e.g. while a mode like Styles is active), no dial tool shows the selected
    /// highlight — so the active *mode* chip reads as the current selection instead.
    private let highlightSelection: Bool
    /// Horizontal strip (portrait) or vertical rail (landscape). Only the container/divider/edge-fade
    /// orientation changes — every chip is shared.
    private let axis: Axis
    private let onSelect: (EditTool) -> Void

    public init(
        actions: [ToolBarAction] = [],
        selected: EditTool?,
        tools: [EditTool] = EditTool.dialTools,
        editedTools: Set<EditTool> = [],
        highlightSelection: Bool = true,
        axis: Axis = .horizontal,
        onSelect: @escaping (EditTool) -> Void
    ) {
        self.actions = actions
        self.selected = selected
        self.tools = tools
        self.editedTools = editedTools
        self.highlightSelection = highlightSelection
        self.axis = axis
        self.onSelect = onSelect
    }

    private var isVertical: Bool { axis == .vertical }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(isVertical ? .vertical : .horizontal, showsIndicators: false) {
                // Same chips; AnyLayout swaps the stack axis so there's a single view tree.
                let layout = isVertical
                    ? AnyLayout(VStackLayout(spacing: Theme.Space.m))
                    : AnyLayout(HStackLayout(spacing: Theme.Space.m))
                layout {
                    // Styles & Crop lead the strip; the dial tools own the visible run.
                    ForEach(actions) { action in
                        actionChip(action)
                    }
                    if !actions.isEmpty { divider }
                    ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                        // Subtle group spacing: a short, faint tick whenever the group changes
                        // (Auto · Light · Colour · Finishing), so the strip reads in sections.
                        if index > 0, tools[index - 1].group != tool.group {
                            groupSeparator
                        }
                        chip(tool).id(tool)
                    }
                }
                .padding(isVertical ? .vertical : .horizontal, Theme.Space.l)
                // Room so the selected chip's 1.12× scale and the glass halo aren't clipped.
                .padding(isVertical ? .horizontal : .vertical, 10)
            }
            .scrollClipDisabled()
            // Soft fade at each end — a mask (like the dial) so chips fade to transparent at the
            // edges regardless of scroll overflow. (A black overlay missed chips that overran the
            // bounds via scrollClipDisabled, leaving a hard cut in the landscape rail.)
            .mask(edgeFadeMask)
            .onAppear {
                // Horizontal: start scrolled past Styles/Crop to the first dial tool. Vertical:
                // leave Styles/Crop visible at the top (they're primary in the rail).
                if !isVertical, !actions.isEmpty, let first = tools.first {
                    proxy.scrollTo(first, anchor: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var divider: some View {
        if isVertical {
            Divider().frame(width: 32).overlay(.white.opacity(0.15))
        } else {
            Divider().frame(height: 32).overlay(.white.opacity(0.15))
        }
    }

    /// A shorter, fainter tick than `divider` — separates adjustment groups within the dial tools
    /// (vs. the main divider that splits the action chips from the tools).
    @ViewBuilder
    private var groupSeparator: some View {
        if isVertical {
            Divider().frame(width: 16).overlay(.white.opacity(0.08))
        } else {
            Divider().frame(height: 16).overlay(.white.opacity(0.08))
        }
    }

    /// Gradient mask that fades the strip/rail to transparent at both ends along the scroll axis.
    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.94),
                .init(color: .clear, location: 1)
            ],
            startPoint: isVertical ? .top : .leading,
            endPoint: isVertical ? .bottom : .trailing
        )
    }

    private let chipSize: CGFloat = 54

    private func actionChip(_ action: ToolBarAction) -> some View {
        Button(action: action.handler) {
            Color.clear
                .frame(width: chipSize, height: chipSize)
                .overlay(
                    Image(systemName: action.systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(iconColor(active: action.tinted, edited: action.showsDot))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(chipGlass(active: action.tinted, edited: action.showsDot), in: .circle)
        .animation(Theme.Motion.snappy, value: action.showsDot)
        .accessibilityLabel(action.title)
        .accessibilityValue(action.showsDot ? "Edited" : "")
    }

    private func chip(_ tool: EditTool) -> some View {
        let isSelected = highlightSelection && tool == selected
        let isEdited = editedTools.contains(tool)
        return Button {
            onSelect(tool)
        } label: {
            Color.clear
                .frame(width: chipSize, height: chipSize)
                .overlay(
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(iconColor(active: isSelected, edited: isEdited))
                        .symbolEffect(.bounce, value: isSelected)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(chipGlass(active: isSelected, edited: isEdited), in: .circle)
        .scaleEffect(isSelected ? 1.12 : 1)
        .animation(Theme.Motion.snappy, value: isSelected)
        .animation(Theme.Motion.snappy, value: isEdited)
        .accessibilityLabel(tool.title)
        .accessibilityValue(isEdited ? "Edited" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Three chip states, expressed purely through the native glass — no overlaid dot:
    /// • active (selected tool / open mode) → a strong accent tint, the chip reads as "on";
    /// • edited (has a non-zero adjustment) → a soft accent tint, so it glows quietly;
    /// • idle → clear glass.
    private func chipGlass(active: Bool, edited: Bool) -> Glass {
        if active { return .regular.tint(Theme.accent.opacity(0.78)).interactive() }
        if edited { return .regular.tint(Theme.accent.opacity(0.30)).interactive() }
        return .regular.interactive()
    }

    private func iconColor(active: Bool, edited: Bool) -> Color {
        if active { return .black }       // legible on the strong tint
        if edited { return Theme.accent } // matches the soft tint
        return .white
    }
}
