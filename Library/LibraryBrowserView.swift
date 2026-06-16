import SwiftUI
import Photos
import PostKit

/// An in-app grid of the user's photo library for fast, multi-select import. Shown only when the
/// user has granted full (or limited) access; otherwise the gallery uses the system picker.
struct LibraryBrowserView: View {
    /// Called with the chosen assets' full-resolution data when the user taps Import.
    let onImport: ([Data]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var selection: [String] = []      // ordered localIdentifiers
    @State private var isImporting = false

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 3)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    if PhotoLibrary.status == .limited { limitedNotice }
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            let order = selection.firstIndex(of: asset.localIdentifier)
                            AssetThumbnail(asset: asset, selectionOrder: order.map { $0 + 1 })
                                .onTapGesture { toggle(asset) }
                        }
                    }
                    .padding(3)
                }
            }
            .navigationTitle("Your Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selection.isEmpty ? "Import" : "Import \(selection.count)") {
                        importSelected()
                    }
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty || isImporting)
                }
            }
            .task { assets = PhotoLibrary.fetchImageAssets() }
        }
    }

    private var limitedNotice: some View {
        HStack(spacing: Theme.Space.m) {
            Text("You've allowed Post to see selected photos.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Add More") { PhotoLibrary.presentAddMore() }
                .font(.caption.weight(.semibold))
                .tint(Theme.accent)
        }
        .padding(Theme.Space.m)
        .glassEffect(in: .rect(cornerRadius: Theme.Radius.control))
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.s)
    }

    private func toggle(_ asset: PHAsset) {
        if let i = selection.firstIndex(of: asset.localIdentifier) {
            selection.remove(at: i)
        } else {
            selection.append(asset.localIdentifier)
        }
        Haptics.selection()
    }

    private func importSelected() {
        guard !selection.isEmpty else { return }
        isImporting = true
        let byID = Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let chosen = selection.compactMap { byID[$0] }
        Task {
            var datas: [Data] = []
            for asset in chosen {
                if let data = await PhotoLibrary.fullData(for: asset) { datas.append(data) }
            }
            onImport(datas)
            dismiss()
        }
    }
}

/// A single square library thumbnail with a numbered selection badge (like Photos' multi-select).
private struct AssetThumbnail: View {
    let asset: PHAsset
    let selectionOrder: Int?
    @State private var image: UIImage?

    private var isSelected: Bool { selectionOrder != nil }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.canvas.overlay(ProgressView().tint(.white.opacity(0.4)))
                }
            }
            .clipped()
            .overlay { if isSelected { Color.black.opacity(0.3) } }
            .overlay(alignment: .topTrailing) { badge }
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                image = await PhotoLibrary.thumbnail(for: asset, size: CGSize(width: 240, height: 240))
            }
    }

    @ViewBuilder
    private var badge: some View {
        if let selectionOrder {
            Text("\(selectionOrder)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Theme.accent, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .padding(5)
        }
    }
}
