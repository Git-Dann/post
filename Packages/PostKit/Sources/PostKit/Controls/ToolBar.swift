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
    private let onSelect: (EditTool) -> Void

    /// - Parameter selected: the active dial tool, or `nil` when another mode (Styles, Crop) owns the
    ///   editor — in which case no dial chip is highlighted, so only one tool reads as active.
    public init(
        actions: [ToolBarAction] = [],
        selected: EditTool?,
        tools: [EditTool] = EditTool.dialTools,
        editedTools: Set<EditTool> = [],
        onSelect: @escaping (EditTool) -> Void
    ) {
        self.actions = actions
        self.selected = selected
        self.tools = tools
        self.editedTools = editedTools
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
                        .foregroundStyle(action.tinted ? .black : .white)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            action.tinted ? .regular.tint(Theme.accent.opacity(0.78)).interactive() : .regular.interactive(),
            in: .circle
        )
        .overlay(alignment: .topTrailing) { editDot(action.showsDot) }
        .accessibilityLabel(action.title)
    }

    private func chip(_ tool: EditTool) -> some View {
        let isSelected = tool == selected
        return Button {
            onSelect(tool)
        } label: {
            Color.clear
                .frame(width: chipSize, height: chipSize)
                .overlay(
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : .white)
                        .symbolEffect(.bounce, value: isSelected)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(Theme.accent.opacity(0.78)).interactive() : .regular.interactive(),
            in: .circle
        )
        .scaleEffect(isSelected ? 1.12 : 1)
        .animation(Theme.Motion.snappy, value: isSelected)
        .overlay(alignment: .topTrailing) { editDot(editedTools.contains(tool)) }
        .accessibilityLabel(tool.title)
        .accessibilityValue(editedTools.contains(tool) ? "Edited" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func editDot(_ show: Bool) -> some View {
        if show {
            Circle()
                .fill(Theme.accent)
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: 2))
                .offset(x: -3, y: 3)
                .transition(.scale.combined(with: .opacity))
        }
    }
}
