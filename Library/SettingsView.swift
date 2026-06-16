import SwiftUI
import PostKit

/// Settings & about. Doubles as the privacy statement — the app's whole pitch — plus the one
/// export option that touches privacy: stripping location from shared images.
struct SettingsView: View {
    @AppStorage("removeLocationOnExport") private var removeLocation = false
    @AppStorage("soundEffectsEnabled") private var soundEnabled = false
    @AppStorage(AccentChoice.storageKey) private var accentRaw = AccentChoice.amber.rawValue
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(v)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Theme.Space.l) {
                        promise
                        appearance
                        exportOptions
                        Text(version)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .padding(.top, Theme.Space.s)
                    }
                    .padding(Theme.Space.l)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var promise: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.breathe)
            Text("Yours, and only yours")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            VStack(spacing: Theme.Space.s) {
                promiseRow("photo.on.rectangle", "Everything happens on your device")
                promiseRow("eye.slash", "No tracking, no analytics, no accounts")
                promiseRow("wifi.slash", "No network — your photos never leave")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.l)
        .glassEffect(in: .rect(cornerRadius: Theme.Radius.card))
    }

    private func promiseRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Accent color")
                .font(.subheadline.weight(.medium))
            HStack {
                ForEach(AccentChoice.allCases) { choice in
                    Button {
                        accentRaw = choice.rawValue
                        Haptics.selection()
                    } label: {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().strokeBorder(.white, lineWidth: accentRaw == choice.rawValue ? 3 : 0)
                            )
                            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.name)
                    if choice != AccentChoice.allCases.last { Spacer() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
        .glassEffect(in: .rect(cornerRadius: Theme.Radius.card))
    }

    private var exportOptions: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Toggle(isOn: $removeLocation) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove location from exports")
                        .font(.subheadline.weight(.medium))
                    Text("Strip GPS data when sharing or saving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Theme.accent)

            Divider().overlay(.white.opacity(0.1))

            Toggle(isOn: $soundEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dial sound effects")
                        .font(.subheadline.weight(.medium))
                    Text("A soft tick as the dial passes each mark.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Theme.accent)
        }
        .padding(Theme.Space.l)
        .glassEffect(in: .rect(cornerRadius: Theme.Radius.card))
    }
}

#Preview {
    SettingsView().preferredColorScheme(.dark)
}
