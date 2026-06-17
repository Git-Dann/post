import Foundation

/// Where the tonal/colour adjustments land. The finishing pass (sharpen, vignette, grain) always
/// stays global — only the tonal edit is confined when a region is chosen. One scope per recipe
/// keeps the model simple: the dials are unchanged; the pipeline just composites through a mask.
public nonisolated enum SelectiveScope: String, Codable, Sendable, Equatable, CaseIterable {
    case whole
    case subject
    case background

    public var title: String {
        switch self {
        case .whole: "Whole Photo"
        case .subject: "Subject"
        case .background: "Background"
        }
    }

    /// Short label for the in-canvas chip.
    public var shortTitle: String {
        switch self {
        case .whole: "Whole"
        case .subject: "Subject"
        case .background: "Background"
        }
    }

    public var systemImage: String {
        switch self {
        case .whole: "photo"
        case .subject: "person.and.background.dotted"
        case .background: "mountain.2"
        }
    }

    /// True when the edit should be masked to a region (vs. applied everywhere).
    public var isRegional: Bool { self != .whole }

    /// Spoken to VoiceOver when the scope changes.
    public var announcement: String {
        switch self {
        case .whole: "Adjusting the whole photo"
        case .subject: "Adjusting the subject"
        case .background: "Adjusting the background"
        }
    }
}
