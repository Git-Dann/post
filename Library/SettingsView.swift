import SwiftUI
import SwiftData
import Photos
import UIKit
import PostKit

/// Settings & about. Doubles as the privacy statement — the app's whole pitch — plus export and
/// photo-access controls.
struct SettingsView: View {
    @AppStorage(ExportPrefs.removeLocationKey, store: .postShared) private var removeLocation = true
    @AppStorage(ExportPrefs.formatKey, store: .postShared) private var exportFormat = "heic"
    @AppStorage(ExportPrefs.qualityKey, store: .postShared) private var exportQuality = 0.92
    @AppStorage(ExportPrefs.maxDimensionKey, store: .postShared) private var exportMaxDimension = 0.0
    @AppStorage("soundEffectsEnabled") private var soundEnabled = false
    @AppStorage(AccentChoice.storageKey) private var accentRaw = AccentChoice.amber.rawValue
    @AppStorage(SyncPrefs.iCloudEnabledKey, store: .postShared) private var iCloudSync = false
    @AppStorage("hasSeenTour") private var hasSeenTour = false
    @State private var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var syncJustChanged = false
    @Environment(\.modelContext) private var modelContext
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
                        preferencesCard
                        exportFormatSection
                        exportOptions
                        aboutSection
                        Text(version)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .padding(.top, Theme.Space.s)
                    }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: 600)            // don't let panels stretch wide in landscape/iPad
                    .frame(maxWidth: .infinity)      // …keep them centred
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite) }
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

    /// Accent · Photo access · iCloud, condensed into one grouped card of compact rows.
    private var preferencesCard: some View {
        VStack(spacing: Theme.Space.m) {
            accentRow
            rowDivider
            photoRow
            rowDivider
            iCloudRow
        }
        .padding(Theme.Space.l)
        .glassEffect(in: .rect(cornerRadius: Theme.Radius.card))
    }

    private var rowDivider: some View { Divider().overlay(.white.opacity(0.1)) }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 26)
    }

    private var accentRow: some View {
        HStack(spacing: Theme.Space.m) {
            rowIcon("paintpalette.fill")
            Text("Accent").font(.subheadline.weight(.medium)).fixedSize()
            Spacer(minLength: Theme.Space.s)
            HStack(spacing: 8) {
                ForEach(AccentChoice.allCases) { choice in
                    Button {
                        accentRaw = choice.rawValue
                        Haptics.selection()
                    } label: {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.white, lineWidth: accentRaw == choice.rawValue ? 2.5 : 0))
                            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.name)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accent colour")
    }

    private var photoRow: some View {
        HStack(spacing: Theme.Space.m) {
            rowIcon("photo.stack")
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo Library").font(.subheadline.weight(.medium))
                Text(photoStatusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Space.s)
            Button(action: handlePhotoAccess) {
                Text(photoStatus == .notDetermined ? "Allow" : "Manage")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .tint(Theme.accent)
        }
    }

    private var iCloudRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $iCloudSync) {
                HStack(spacing: Theme.Space.m) {
                    rowIcon("icloud")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync with iCloud").font(.subheadline.weight(.medium))
                        Text("Your library on all your devices, privately.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(Theme.accent)
            if syncJustChanged {
                Text(iCloudSync ? "Quit and reopen Post to start syncing."
                                : "Quit and reopen Post to stop syncing.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.leading, 26 + Theme.Space.m)
                    .transition(.opacity)
            }
        }
        .onChange(of: iCloudSync) { _, enabled in
            if enabled { ProjectStore.migrateOriginalsIntoStore(in: modelContext) }
            withAnimation(.snappy) { syncJustChanged = true }
        }
    }

    private var photoStatusText: String {
        switch photoStatus {
        case .authorized: "Full access — import anything"
        case .limited: "Limited to selected photos"
        case .denied: "No access — picker only"
        case .restricted: "Restricted by device settings"
        case .notDetermined: "Using the picker (no access needed)"
        @unknown default: "Unknown"
        }
    }

    private func handlePhotoAccess() {
        if photoStatus == .notDetermined {
            Task { photoStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var aboutSection: some View {
        Button {
            hasSeenTour = false   // GalleryView re-presents the welcome when Settings dismisses
            Haptics.selection()
            dismiss()
        } label: {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Welcome Screen")
                        .font(.subheadline.weight(.medium))
                    Text("Replay the intro tour.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity)
            .glassEffect(in: .rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
    }

    private var exportFormatSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Format")
                    .font(.subheadline.weight(.medium))
                Picker("Format", selection: $exportFormat) {
                    Text("HEIC").tag("heic")
                    Text("JPEG").tag("jpeg")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("HEIC is smaller and 10-bit; JPEG is the most compatible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().overlay(.white.opacity(0.1))

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Text("Quality").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int((exportQuality * 100).rounded()))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $exportQuality, in: 0.6...1.0)
                    .tint(Theme.accent)
            }

            Divider().overlay(.white.opacity(0.1))

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Resolution")
                    .font(.subheadline.weight(.medium))
                Picker("Resolution", selection: $exportMaxDimension) {
                    Text("Full").tag(0.0)
                    Text("Large").tag(4096.0)
                    Text("Medium").tag(2048.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Caps the longest edge when you share or export (edits in Photos stay full size).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
