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
    private let onSelect: (EditTool) -> Void

    public init(
        actions: [ToolBarAction] = [],
        selected: EditTool?,
        tools: [EditTool] = EditTool.dialTools,
        editedTools: Set<EditTool> = [],
        highlightSelection: Bool = true,
        onSelect: @escaping (EditTool) -> Void
    ) {
        self.actions = actions
        self.selected = selected
        self.tools = tools
        self.editedTools = editedTools
        self.highlightSelection = highlightSelection
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.m) {
                    // Styles & Crop live to the left, off-screen by default — scroll left to reach
                    // them, so the dial tools own the visible strip.
                    ForEach(actions) { action in
                        actionChip(action)
                    }
                    if !actions.isEmpty {
                        Divider()
                            .frame(height: 32)
                            .overlay(.white.opacity(0.15))
                    }
                    ForEach(tools) { tool in
                        chip(tool).id(tool)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                // Room so the selected chip's 1.12× scale, the dot, and the glass halo aren't clipped.
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
            // Soft fade at each end hints there's more beyond (Crop/Styles left, more tools right).
            .overlay(alignment: .leading) { edgeFade(.leading) }
            .overlay(alignment: .trailing) { edgeFade(.trailing) }
            .onAppear {
                // Start scrolled so the first dial tool is at the leading edge (actions hidden left).
                if !actions.isEmpty, let first = tools.first {
                    proxy.scrollTo(first, anchor: .leading)
                }
            }
        }
    }

    private func edgeFade(_ edge: HorizontalEdge) -> some View {
        LinearGradient(
            colors: edge == .leading ? [.black, .clear] : [.clear, .black],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 28)
        .allowsHitTesting(false)
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
