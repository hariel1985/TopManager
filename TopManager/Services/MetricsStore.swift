import Foundation

/// A single point-in-time snapshot of system-wide metrics, persisted to disk so
/// history survives app restarts (the live in-RAM histories only hold ~60 points).
struct MetricsSample: Codable, Identifiable, Equatable {
    let t: Date          // timestamp
    let cpu: Double      // global CPU usage %
    let memUsed: UInt64
    let memTotal: UInt64
    let netDown: Double  // bytes/sec
    let netUp: Double    // bytes/sec

    var id: Date { t }

    var memPercent: Double {
        memTotal > 0 ? Double(memUsed) / Double(memTotal) * 100 : 0
    }
}

/// Pure, side-effect-free math over samples. Kept separate from `MetricsStore`
/// so it is trivially unit-testable without touching disk or the clock.
enum MetricsMath {
    /// Drop samples older than `maxAge` (relative to `now`) and cap total count,
    /// keeping the most recent `maxCount`.
    static func trim(_ samples: [MetricsSample], now: Date, maxAge: TimeInterval, maxCount: Int) -> [MetricsSample] {
        let cutoff = now.addingTimeInterval(-maxAge)
        var result = samples.filter { $0.t >= cutoff }
        if result.count > maxCount {
            result = Array(result.suffix(maxCount))
        }
        return result
    }

    /// Average samples into fixed-width time buckets so long ranges (e.g. 24h)
    /// plot ~100 points instead of tens of thousands. `bucket <= 0` returns input.
    static func downsample(_ samples: [MetricsSample], bucket: TimeInterval) -> [MetricsSample] {
        guard bucket > 0, samples.count > 1 else { return samples }

        var groups: [Int64: [MetricsSample]] = [:]
        for s in samples {
            let key = Int64((s.t.timeIntervalSince1970 / bucket).rounded(.down))
            groups[key, default: []].append(s)
        }

        return groups.keys.sorted().map { key in
            let group = groups[key]!
            let n = Double(group.count)
            let midpoint = Date(timeIntervalSince1970: (Double(key) + 0.5) * bucket)
            return MetricsSample(
                t: midpoint,
                cpu: group.reduce(0) { $0 + $1.cpu } / n,
                memUsed: UInt64(group.reduce(0.0) { $0 + Double($1.memUsed) } / n),
                memTotal: group.map { $0.memTotal }.max() ?? 0,
                netDown: group.reduce(0) { $0 + $1.netDown } / n,
                netUp: group.reduce(0) { $0 + $1.netUp } / n
            )
        }
    }
}

/// Selectable time window for trend charts.
enum HistoryRange: String, CaseIterable, Identifiable {
    case live = "Live"
    case m5 = "5m"
    case m30 = "30m"
    case h1 = "1h"
    case h24 = "24h"

    var id: String { rawValue }

    /// Window length in seconds; `nil` for the live (in-RAM) view.
    var seconds: TimeInterval? {
        switch self {
        case .live: return nil
        case .m5: return 5 * 60
        case .m30: return 30 * 60
        case .h1: return 60 * 60
        case .h24: return 24 * 60 * 60
        }
    }

    /// Downsample bucket size chosen to keep ~100–150 plotted points.
    var bucket: TimeInterval {
        switch self {
        case .live: return 0
        case .m5: return 0       // ~raw (refresh cadence already ~3s)
        case .m30: return 15
        case .h1: return 30
        case .h24: return 600
        }
    }
}

/// Thread-safe on-disk ring buffer of `MetricsSample`s.
///
/// Access to the backing array is guarded by a lock; file writes happen on a
/// background queue from a snapshot so the recording thread never blocks on I/O.
final class MetricsStore {
    static let shared = MetricsStore()

    private let lock = NSLock()
    private var _samples: [MetricsSample] = []
    private let fileURL: URL
    private let maxAge: TimeInterval
    private let maxCount: Int
    private let saveEvery: Int
    private var unsaved = 0
    private let ioQueue = DispatchQueue(label: "com.topmanager.metricsstore.io", qos: .utility)

    /// - Note: `saveEvery` is deliberately coarse. Every save re-encodes the
    ///   *whole* history (up to `maxCount` samples), which costs a few hundred
    ///   thousand transient allocations; at the old cadence of 10 that ran twice
    ///   a minute and kept the malloc small zone needlessly dirty. 40 samples is
    ///   ~2 minutes at the default 3 s refresh, and `flush()` still runs on quit
    ///   and when the app goes to the background.
    init(fileURL: URL? = nil,
         maxAge: TimeInterval = 24 * 60 * 60,
         maxCount: Int = 20_000,
         saveEvery: Int = 40) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.maxAge = maxAge
        self.maxCount = maxCount
        self.saveEvery = saveEvery
        load()
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("TopManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("metrics-history.json")
    }

    /// Append a sample, trim, and persist on a throttled cadence.
    func record(_ sample: MetricsSample) {
        lock.lock()
        _samples.append(sample)
        _samples = MetricsMath.trim(_samples, now: sample.t, maxAge: maxAge, maxCount: maxCount)
        unsaved += 1
        let snapshot: [MetricsSample]? = unsaved >= saveEvery ? _samples : nil
        if snapshot != nil { unsaved = 0 }
        lock.unlock()

        if let snapshot { persist(snapshot) }
    }

    func samples(since date: Date) -> [MetricsSample] {
        lock.lock(); defer { lock.unlock() }
        return _samples.filter { $0.t >= date }
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _samples.count
    }

    /// Samples for a chart range, downsampled for long windows.
    func downsampled(for range: HistoryRange, now: Date = Date()) -> [MetricsSample] {
        guard let secs = range.seconds else { return [] }
        let windowed = samples(since: now.addingTimeInterval(-secs))
        return MetricsMath.downsample(windowed, bucket: range.bucket)
    }

    /// Force an immediate save (e.g. on stop / quit).
    func flush() {
        lock.lock()
        let snapshot = _samples
        unsaved = 0
        lock.unlock()
        persist(snapshot)
    }

    private func persist(_ snapshot: [MetricsSample]) {
        ioQueue.async { [fileURL] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MetricsSample].self, from: data) else {
            return
        }
        lock.lock()
        _samples = MetricsMath.trim(decoded, now: Date(), maxAge: maxAge, maxCount: maxCount)
        lock.unlock()
    }
}
