import Foundation

/// On-device file storage, shared between the app and extensions via the App Group container
/// (with a safe fallback to Application Support if the group isn't available). Written with file
/// protection so originals are encrypted at rest.
public enum Storage {
    public nonisolated static let appGroupID = "group.co.gitwork.post"

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

    private static let protection: [FileAttributeKey: Any] =
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]

    public static func ensureDirectories() {
        // Protect the base directory too — the SwiftData store (thumbnails + recipes) lives here.
        try? FileManager.default.createDirectory(
            at: baseDirectory, withIntermediateDirectories: true, attributes: protection)
        try? FileManager.default.createDirectory(
            at: originalsDirectory, withIntermediateDirectories: true, attributes: protection)
    }

    /// File-protect the SwiftData store and its WAL/SHM sidecars (SwiftData doesn't set this itself).
    public static func protectStoreFiles() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.setAttributes(protection, ofItemAtPath: storeURL.path + suffix)
        }
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

public extension UserDefaults {
    /// Settings shared between the app and its extensions via the App Group (falls back to standard).
    /// `nonisolated(unsafe)`: UserDefaults is documented thread-safe, so concurrent reads are fine.
    nonisolated(unsafe) static let postShared = UserDefaults(suiteName: Storage.appGroupID) ?? .standard
}

/// iCloud sync preference, read at container-open time. Shared via the App Group so the app and the
/// extensions agree on whether to open the CloudKit-backed store. Defaults OFF (privacy-first opt-in).
public nonisolated enum SyncPrefs {
    public static let iCloudEnabledKey = "iCloudSyncEnabled"

    /// The CloudKit container backing the private database. Only used when sync is enabled AND the
    /// matching entitlement is provisioned (see project.yml); otherwise the store stays local.
    public static let cloudContainerID = "iCloud.co.gitwork.post"

    public static var iCloudEnabled: Bool { UserDefaults.postShared.bool(forKey: iCloudEnabledKey) }
}

/// Export preferences shared across the app, extensions and the Shortcuts intent. `nonisolated`
/// (pure UserDefaults reads) so the App Intent and extensions can read them off the main actor.
public nonisolated enum ExportPrefs {
    public static let removeLocationKey = "removeLocationOnExport"
    public static let formatKey = "exportFormat"          // "heic" | "jpeg"
    public static let qualityKey = "exportQuality"        // 0…1
    public static let maxDimensionKey = "exportMaxDimension"  // longest edge in px; 0 = full

    /// Strip location metadata on export. Defaults to ON (privacy-first) when unset.
    public static var removeLocation: Bool {
        UserDefaults.postShared.object(forKey: removeLocationKey) as? Bool ?? true
    }

    /// Output container. Defaults to HEIC (smaller, 10-bit).
    public static var format: ImageExporter.Format {
        UserDefaults.postShared.string(forKey: formatKey) == "jpeg" ? .jpeg : .heic
    }

    /// Lossy compression quality. Defaults to 0.92.
    public static var quality: Double {
        let q = UserDefaults.postShared.object(forKey: qualityKey) as? Double ?? 0.92
        return min(max(q, 0.4), 1.0)
    }

    /// Longest-edge cap for share/export (nil = full resolution). Not applied to edit-in-place
    /// (the Photos extension) so library photos keep their native size.
    public static var maxDimension: CGFloat? {
        let d = UserDefaults.postShared.object(forKey: maxDimensionKey) as? Double ?? 0
        return d > 0 ? CGFloat(d) : nil
    }
}
