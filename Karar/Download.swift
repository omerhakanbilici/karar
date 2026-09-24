import Foundation

/// The progress of one `/api/pull`, folded into one bar per model it downloads (a router has no
/// weights; its targets each get a bar). Lines carry only blob digests, so models are told apart
/// by their `pulling manifest` lines (docs/api.md §7.6: a router's own manifest first, then each
/// target in route order).
struct Download: Equatable {
    struct Part: Equatable, Identifiable {
        let name: String
        let estimate: Int64                        // catalog size, until the real sizes are known
        fileprivate(set) var isDone = false
        fileprivate var sizes: [String: Int64] = [:]      // digest → blob size
        fileprivate var present: [String: Int64] = [:]    // digest → bytes on disk

        var id: String { name }
        var completed: Int64 { present.values.reduce(0, +) }
        var total: Int64 {
            let known = sizes.values.reduce(0, +)
            return isDone ? known : max(known, estimate)   // blobs are announced one by one
        }
        var fraction: Double { total > 0 ? min(Double(completed) / Double(total), 1) : 0 }
    }

    private(set) var parts: [Part]
    private(set) var isFinished = false
    private(set) var bytesPerSecond: Double?
    var error: String?

    private let skipsFirstManifest: Bool           // a router's own manifest has no bar
    private var manifests = 0
    private var baselines: [String: Int64] = [:]   // digest → first non-zero `completed` (resumed bytes)
    private var firstByteAt: Date?

    init(for entry: CatalogEntry) {
        if entry.includes.isEmpty {
            parts = [Part(name: entry.name, estimate: entry.size)]
            skipsFirstManifest = false
        } else {
            parts = entry.includes.map { Part(name: $0, estimate: CatalogEntry.named($0)?.size ?? 0) }
            skipsFirstManifest = true
        }
    }

    var fraction: Double {
        let total = parts.map(\.total).reduce(0, +)
        return total > 0 ? min(Double(parts.map(\.completed).reduce(0, +)) / Double(total), 1) : 0
    }

    func secondsLeft(_ part: Part) -> Double? {
        guard let speed = bytesPerSecond, speed > 0, !part.isDone else { return nil }
        return Double(max(part.total - part.completed, 0)) / speed
    }

    private var current: Int? {
        let index = manifests - 1 - (skipsFirstManifest ? 1 : 0)
        return parts.indices.contains(index) ? index : nil
    }

    mutating func apply(_ progress: PullProgress, at now: Date) {
        switch progress.status {
        case "pulling manifest":
            if let current { parts[current].isDone = true }
            manifests += 1
        case "success":
            for index in parts.indices { parts[index].isDone = true }
            isFinished = true
        default:
            guard let digest = progress.digest, let size = progress.total, let bytes = progress.completed,
                  let current else { return }
            parts[current].sizes[digest] = size
            parts[current].present[digest] = bytes
            if bytes > 0, baselines[digest] == nil {
                baselines[digest] = bytes
                if firstByteAt == nil { firstByteAt = now }
            }
            updateSpeed(at: now)
        }
    }

    // ponytail: average since the first byte, not a moving window; fine for a steady connection.
    private mutating func updateSpeed(at now: Date) {
        guard let start = firstByteAt, now.timeIntervalSince(start) >= 1 else { return }
        var fresh: Int64 = 0
        for part in parts {
            for (digest, bytes) in part.present { fresh += bytes - (baselines[digest] ?? bytes) }
        }
        bytesPerSecond = Double(fresh) / now.timeIntervalSince(start)
    }
}
