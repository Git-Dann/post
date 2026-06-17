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
                        // Uppercase secondary labels in a left column, values aligned beside them —
                        // the system camera/settings-panel layout.
                        Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: Theme.Space.m) {
                            ForEach(rows) { row in
                                GridRow {
                                    Text(row.label.uppercased())
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(row.value)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .gridColumnAlignment(.leading)
                                }
                            }
                        }
                        .padding(Theme.Space.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
