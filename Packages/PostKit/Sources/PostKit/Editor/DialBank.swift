import Foundation

/// One page of corner dials — up to four adjustments, one per screen corner, live at the same time
/// in the landscape editor. Swiping the centre-right of the screen moves between banks, so the photo
/// never gives up the middle of the screen to a control strip.
///
/// A category with more than four tools splits into balanced pages (five become 3 + 2, not 4 + 1),
/// which keeps every tool reachable without ever crowding a corner.
public struct DialBank: Identifiable, Equatable, Sendable {
    public let group: EditTool.Group
    public let tools: [EditTool]
    public let page: Int
    public let pageCount: Int

    public var id: String { "\(group.title)#\(page)" }
    public var title: String { group.title }
    /// "2 of 2" for a paged category, nil when the category fits one bank.
    public var pageLabel: String? { pageCount > 1 ? "\(page + 1) of \(pageCount)" : nil }
    /// What the bank pill and VoiceOver announce, e.g. "Light" or "Light · 2 of 2".
    public var displayTitle: String { pageLabel.map { "\(title) · \($0)" } ?? title }

    /// Corners are filled in reading order, so a bank of three leaves the bottom-trailing corner free.
    public static let corners: [DialCorner] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]

    /// Every bank in swipe order: Light → Colour → Effects, each split into pages of four.
    /// (Auto, Crop and Styles aren't dial banks — they stay one-tap controls.)
    public static let all: [DialBank] = EditTool.Group.adjustmentCategories.flatMap { banks(for: $0) }

    public static func banks(for group: EditTool.Group) -> [DialBank] {
        let pages = paginate(group.tools)
        return pages.enumerated().map {
            DialBank(group: group, tools: $0.element, page: $0.offset, pageCount: pages.count)
        }
    }

    /// Split into as few pages as possible, as evenly as possible. `perPage` is the corner count.
    public static func paginate(_ tools: [EditTool], perPage: Int = 4) -> [[EditTool]] {
        guard !tools.isEmpty, perPage > 0 else { return [] }
        let pages = (tools.count + perPage - 1) / perPage
        let base = tools.count / pages
        let extra = tools.count % pages
        var out: [[EditTool]] = []
        var index = 0
        for page in 0..<pages {
            let count = base + (page < extra ? 1 : 0)
            out.append(Array(tools[index..<(index + count)]))
            index += count
        }
        return out
    }

    /// The bank holding `tool`, so rotating into landscape lands on whatever was being edited.
    public static func index(containing tool: EditTool) -> Int? {
        all.firstIndex { $0.tools.contains(tool) }
    }
}
