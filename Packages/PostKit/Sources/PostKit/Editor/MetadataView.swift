import SwiftUI

/// A compact info panel showing the image's format and EXIF metadata, presented from the editor's
/// (i) button. Replaces the old static "HEIC" tag with something that actually tells you about the
/// photo.
public struct MetadataView: View {
    let rows: [ImageLoader.MetaRow]
    @Environment(\.dismiss) private var dismiss

    public init(rows: [ImageLoader.MetaRow]) {
        self.rows = rows
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                if rows.isEmpty {
                    ContentUnavailableView("No metadata", systemImage: "info.circle")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                HStack {
                                    Text(row.label)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(row.value)
                                        .fontWeight(.medium)
                                        .multilineTextAlignment(.trailing)
                                }
                                .font(.subheadline)
                                .padding(.vertical, Theme.Space.m)
                                if index < rows.count - 1 {
                                    Divider().overlay(.white.opacity(0.08))
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Space.l)
                        .padding(.vertical, Theme.Space.s)
                        .glassEffect(in: .rect(cornerRadius: Theme.Radius.card))
                        .padding(Theme.Space.l)
                    }
                }
            }
            .navigationTitle("Image Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.clear)
    }
}
