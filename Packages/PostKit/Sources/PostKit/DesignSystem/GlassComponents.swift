import SwiftUI

/// A circular, floating Liquid Glass control — the top-bar button vocabulary from the
/// reference editor (menu, bell, share, grid). Interactive glass + a charming press bounce.
public struct GlassIconButton: View {
    private let systemName: String
    private let action: () -> Void
    private let prominent: Bool
    private let size: CGFloat

    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ systemName: String, prominent: Bool = false, size: CGFloat = 48, action: @escaping () -> Void) {
        self.systemName = systemName
        self.prominent = prominent
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // Icon as a centered overlay on a fixed square → always perfectly centered.
            Color.clear
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: systemName)
                        .font(.system(size: size * 0.38, weight: .semibold))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            prominent ? .regular.tint(Theme.accent).interactive() : .regular.interactive(),
            in: .circle
        )
        .scaleEffect(pressed ? 0.9 : 1)
        .animation(Theme.Motion.snappy, value: pressed)
        ._onButtonGesture { pressing in
            pressed = pressing
        } perform: {}
        .accessibilityLabel(Text(systemName.replacingOccurrences(of: ".", with: " ")))
    }
}

/// A capsule label/value pill (the "HEIC" / "+0.0" chips in the reference).
public struct GlassPill: View {
    private let text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .glassEffect(in: .capsule)
    }
}

private extension View {
    /// Lightweight press tracking without a custom ButtonStyle, so callers keep `.plain`.
    func _onButtonGesture(pressing: @escaping (Bool) -> Void, perform: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing(true) }
                .onEnded { _ in pressing(false); perform() }
        )
    }
}
