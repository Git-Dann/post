import SwiftUI
import PostKit

/// A one-time, first-launch invitation to grant full photo-library access so the user can browse
/// and import their whole library inside Post. Declining is first-class — the system picker works
/// without any permission — and it can be changed later in Settings.
struct PhotoAccessPrimer: View {
    /// Called after the user makes a choice (granted or not); the caller dismisses + records it.
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Spacer(minLength: 0)

            Image(systemName: "photo.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.breathe)

            VStack(spacing: Theme.Space.s) {
                Text("Bring in your photos")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Text("Allow access to browse and import from your whole library inside Post. Your photos are read on your device only — nothing is ever uploaded.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Space.l)

            Spacer(minLength: 0)

            VStack(spacing: Theme.Space.m) {
                Button(action: onAllow) {
                    Text("Allow Photo Access")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)

                Button(action: onSkip) {
                    Text("Maybe later — use the picker")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }
}
