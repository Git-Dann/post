import SwiftUI
import PostKit

/// A light, native first-run welcome — three swipeable cards on the system page style. Shown once
/// (gated by `@AppStorage("hasSeenTour")`), skippable, dismisses into the gallery.
struct WelcomeTour: View {
    let onDone: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Card: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let cards: [Card] = [
        Card(symbol: "dial.medium",
             title: "Edit by feel",
             body: "Spin the dial to fine-tune exposure, colour, grain and more — with a tactile tick for every step."),
        Card(symbol: "wand.and.stars",
             title: "One-tap looks",
             body: "Apply a film-style look, then dial its strength to taste. Save your own favourites, too."),
        Card(symbol: "lock.shield",
             title: "Private by design",
             body: "Everything happens on your device. No tracking, no accounts — nothing ever leaves your phone.")
    ]

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        cardView(card).tag(index)
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(page == cards.count - 1 ? "Get Started" : "Continue") {
                    if page == cards.count - 1 {
                        onDone()
                    } else {
                        withAnimation(reduceMotion ? nil : Theme.Motion.snappy) { page += 1 }
                    }
                    Haptics.impact(.soft)
                }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.l)
            }
            .frame(maxWidth: 600)
        }
        .overlay(alignment: .topTrailing) {
            Button("Skip") { onDone() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(Theme.Space.l)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private func cardView(_ card: Card) -> some View {
        VStack(spacing: Theme.Space.l) {
            Spacer()
            Image(systemName: card.symbol)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.breathe, isActive: !reduceMotion)
            Text(card.title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Text(card.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.xl)
            Spacer()
            Spacer()
        }
        .padding(Theme.Space.l)
    }
}
