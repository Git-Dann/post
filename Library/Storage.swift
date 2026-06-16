import Foundation

/// On-device file storage for originals, written with complete file protection (encrypted at rest).
/// Centralized so Phase 5 can switch the base directory to the shared App Group container in one place.
enum Storage {
    static var baseDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Post", isDirectory: true)
    }

    static var originalsDirectory: URL {
        baseDirectory.appendingPathComponent("Originals", isDirectory: true)
    }

    static func ensureDirectories() {
        try? FileManager.default.createDirectory(
            at: originalsDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
    }

    static func originalURL(for fileName: String) -> URL {
        originalsDirectory.appendingPathComponent(fileName)
    }

    static func writeOriginal(_ data: Data, fileName: String) throws {
        ensureDirectories()
        try data.write(to: originalURL(for: fileName), options: [.atomic, .completeFileProtection])
    }

    static func readOriginal(fileName: String) -> Data? {
        try? Data(contentsOf: originalURL(for: fileName))
    }

    static func deleteOriginal(fileName: String) {
        try? FileManager.default.removeItem(at: originalURL(for: fileName))
    }
}
