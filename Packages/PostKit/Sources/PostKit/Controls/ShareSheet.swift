import SwiftUI
import UIKit

/// An item to share — a file URL of an exported image.
public struct ShareItem: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
    public init(url: URL) { self.url = url }
}

/// Bridges `UIActivityViewController` (the system share sheet) into SwiftUI. The share sheet's
/// "Save Image" path is how edits reach the photo library — add-only, no full library access.
public struct ActivityView: UIViewControllerRepresentable {
    private let items: [Any]
    public init(items: [Any]) { self.items = items }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
