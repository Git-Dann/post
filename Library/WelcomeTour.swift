import SwiftUI
import PostKit

/// A first-run welcome in the style of Apple's "What's New" sheets: a bold title, a column of
/// icon-led feature rows that stagger in, and one prominent call-to-action. Shown once (gated by
/// `@AppStorage("hasSeenTour")`), dismisses into the gallery.
struct WelcomeTour: View {
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private struct Feature: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let features: [Feature] = [
        Feature(symbol: "dial.medium",
                title: "Edit by feel",
                body: "Spin a tactile dial to grade exposure, colour, grain and more — a click for every step."),
        Feature(symbol: "wand.and.stars",
                title: "One-tap looks",
                body: "Drop on a film-style look, then dial it to taste. Save your own favourites, too."),
        Feature(symbol: "person.and.background.dotted",
                title: "Subject or background",
                body: "Confine any adjustment to just the subject — or everything but. All on device."),
        Feature(symbol: "lock.shield",
                title: "Private by design",
                body: "No tracking, no accounts. Nothing ever leaves your phone.")
    ]

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 34) {
                        header
                        VStack(alignment: .leading, spacing: 26) {
                            ForEach(Array(features.enumerated()), id: \.element.id) { index, f in
                                featureRow(f, index: index)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.top, 60)
                    .padding(.bottom, Theme.Space.xl)
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity)
                }
                footer
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task {
            // Let the sheet settle, then stagger the content in.
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) { appeared = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text("Post")
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: appeared)
    }

    @ViewBuilder
    private func featureRow(_ f: Feature, index: Int) -> some View {
        let delay = reduceMotion ? 0 : 0.12 + Double(index) * 0.09
        HStack(alignment: .top, spacing: Theme.Space.l) {
            Image(systemName: f.symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .symbolEffect(.bounce, options: .nonRepeating, value: appeared)
            VStack(alignment: .leading, spacing: 3) {
                Text(f.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                Text(f.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(reduceMotion ? nil : .smooth(duration: 0.5).delay(delay), value: appeared)
    }

    private var footer: some View {
        Button {
            Haptics.impact(.soft)
            onDone()
        } label: {
            Text("Get Started")
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .foregroundStyle(.black)
        .frame(maxWidth: 540)
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.l)
        .background(
            // A soft scrim so scrolling rows fade under the pinned button rather than hard-clip.
            LinearGradient(colors: [Theme.canvas.opacity(0), Theme.canvas],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .frame(maxWidth: .infinity, alignment: .bottom)
                .allowsHitTesting(false),
            alignment: .bottom
        )
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .smooth(duration: 0.5).delay(0.45), value: appeared)
    }
}
