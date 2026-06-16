import Foundation

/// On-device file storage, shared between the app and extensions via the App Group container
/// (with a safe fallback to Application Support if the group isn't available). Written with file
/// protection so originals are encrypted at rest.
public enum Storage {
    public static let appGroupID = "group.co.gitwork.post"

    /// App Group container if available; otherwise the app's Application Support directory.
    public static var baseDirectory: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group.appendingPathComponent("Post", isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Post", isDirectory: true)
    }

    public static var originalsDirectory: URL {
        baseDirectory.appendingPathComponent("Originals", isDirectory: true)
    }

    public static var storeURL: URL {
        baseDirectory.appendingPathComponent("Post.store")
    }

    public static func ensureDirectories() {
        try? FileManager.default.createDirectory(
            at: originalsDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    public static func originalURL(for fileName: String) -> URL {
        originalsDirectory.appendingPathComponent(fileName)
    }

    public static func writeOriginal(_ data: Data, fileName: String) throws {
        ensureDirectories()
        try data.write(to: originalURL(for: fileName),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public static func readOriginal(fileName: String) -> Data? {
        try? Data(contentsOf: originalURL(for: fileName))
    }

    public static func deleteOriginal(fileName: String) {
        try? FileManager.default.removeItem(at: originalURL(for: fileName))
    }
}
