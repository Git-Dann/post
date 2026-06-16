import SwiftUI

/// A non-selectable action chip in the tool strip (Styles, Crop) — distinct from the dial tools.
public struct ToolBarAction: Identifiable {
    public let id: String
    let title: String
    let systemImage: String
    let tinted: Bool
    let handler: () -> Void

    public init(id: String, title: String, systemImage: String, tinted: Bool = false,
                handler: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.tinted = tinted
        self.handler = handler
    }
}

/// The scrollable strip of tools — leading action chips (Styles, Crop) followed by the selectable
/// dial adjustments as circular Liquid Glass chips. The selected tool tints amber and lifts;
/// selection morphs between chips via a shared glass namespace.
public struct ToolBar: View {
    private let actions: [ToolBarAction]
    private let selected: EditTool
    private let tools: [EditTool]
    private let onSelect: (EditTool) -> Void

    public init(
        actions: [ToolBarAction] = [],
        selected: EditTool,
        tools: [EditTool] = EditTool.dialTools,
        onSelect: @escaping (EditTool) -> Void
    ) {
        self.actions = actions
        self.selected = selected
        self.tools = tools
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.m) {
                    ForEach(actions) { action in
                        actionChip(action)
                    }
                    if !actions.isEmpty {
                        Divider()
                            .frame(height: 32)
                            .overlay(.white.opacity(0.15))
                    }
                    ForEach(tools) { tool in
                        chip(tool)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                // Room so the selected chip's 1.12× scale and the glass halo aren't clipped.
                .padding(.vertical, 10)
            }
        }
        // Don't let the scroll view crop the scaled/raised chips top & bottom.
        // (No auto-scroll on selection — the row stays put so chips don't jump.)
        .scrollClipDisabled()
    }

    private func actionChip(_ action: ToolBarAction) -> some View {
        Button(action: action.handler) {
            Image(systemName: action.systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(action.tinted ? .black : .white)
                .frame(width: 54, height: 54)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            action.tinted ? .regular.tint(Theme.accent.opacity(0.78)).interactive() : .regular.interactive(),
            in: .circle
        )
        .accessibilityLabel(action.title)
    }

    private func chip(_ tool: EditTool) -> some View {
        let isSelected = tool == selected
        return Button {
            onSelect(tool)
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isSelected ? .black : .white)
                .symbolEffect(.bounce, value: isSelected)
                .frame(width: 54, height: 54)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(Theme.accent.opacity(0.78)).interactive() : .regular.interactive(),
            in: .circle
        )
        .scaleEffect(isSelected ? 1.12 : 1)
        .animation(Theme.Motion.snappy, value: isSelected)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
