import Foundation
import MetricKit

/// Receives MetricKit's daily performance metrics and crash/hang diagnostics and stores them
/// **on device only** — nothing is ever uploaded, so the "zero data collection" promise holds. The
/// payloads sit in Application Support (capped to the most recent few) for local inspection/QA.
///
/// `nonisolated`: MetricKit delivers payloads on a background queue, so the subscriber stays off the
/// main actor (the module otherwise defaults to MainActor).
final class MetricsMonitor: NSObject, MXMetricManagerSubscriber {
    private nonisolated static let keep = 12   // most-recent payloads retained on disk

    override init() {
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit { MXMetricManager.shared.remove(self) }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        store(payloads.map { $0.jsonRepresentation() }, prefix: "metric")
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        store(payloads.map { $0.jsonRepresentation() }, prefix: "diagnostic")
    }

    /// Write each payload's JSON to the local metrics folder, then prune to the newest `keep`.
    private nonisolated func store(_ payloads: [Data], prefix: String) {
        guard !payloads.isEmpty,
              let dir = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
              ).appendingPathComponent("Metrics", isDirectory: true)
        else { return }

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for data in payloads {
            let url = dir.appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
            try? data.write(to: url, options: .atomic)
        }
        prune(in: dir)
    }

    private nonisolated func prune(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        ), files.count > Self.keep else { return }

        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a > b   // newest first
        }
        for old in sorted.dropFirst(Self.keep) { try? fm.removeItem(at: old) }
    }
}
