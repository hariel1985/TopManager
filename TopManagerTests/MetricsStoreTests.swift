import XCTest
@testable import TopManager

final class MetricsStoreTests: XCTestCase {

    private func sample(_ secondsAgo: TimeInterval, cpu: Double = 0, memUsed: UInt64 = 0,
                        memTotal: UInt64 = 100, down: Double = 0, up: Double = 0,
                        now: Date) -> MetricsSample {
        MetricsSample(t: now.addingTimeInterval(-secondsAgo), cpu: cpu,
                      memUsed: memUsed, memTotal: memTotal, netDown: down, netUp: up)
    }

    // MARK: - trim

    func testTrimDropsOldSamples() {
        let now = Date()
        let samples = [
            sample(10_000, now: now), // older than 1h
            sample(100, now: now),    // within 1h
            sample(50, now: now)
        ]
        let trimmed = MetricsMath.trim(samples, now: now, maxAge: 3600, maxCount: 100)
        XCTAssertEqual(trimmed.count, 2)
        XCTAssertFalse(trimmed.contains { $0.t < now.addingTimeInterval(-3600) })
    }

    func testTrimCapsCountKeepingNewest() {
        let now = Date()
        // 10 samples, 0..9 seconds ago; keep newest 5
        let samples = (0..<10).map { sample(Double($0), cpu: Double($0), now: now) }
        let trimmed = MetricsMath.trim(samples, now: now, maxAge: 3600, maxCount: 5)
        XCTAssertEqual(trimmed.count, 5)
        // suffix keeps the last 5 of the input order (cpu 5..9)
        XCTAssertEqual(trimmed.map { $0.cpu }, [5, 6, 7, 8, 9])
    }

    // MARK: - downsample

    func testDownsampleZeroBucketIsPassthrough() {
        let now = Date()
        let samples = (0..<5).map { sample(Double($0), cpu: Double($0), now: now) }
        XCTAssertEqual(MetricsMath.downsample(samples, bucket: 0).count, 5)
    }

    func testDownsampleAveragesWithinBucket() {
        // Two samples 0s and 5s into the same 60s bucket → averaged to one point.
        let epoch = Date(timeIntervalSince1970: 1_000_000) // aligned into bucket 16666
        let s1 = MetricsSample(t: epoch, cpu: 20, memUsed: 40, memTotal: 100, netDown: 100, netUp: 10)
        let s2 = MetricsSample(t: epoch.addingTimeInterval(5), cpu: 40, memUsed: 60, memTotal: 100, netDown: 300, netUp: 30)
        let out = MetricsMath.downsample([s1, s2], bucket: 60)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].cpu, 30, accuracy: 0.001)
        XCTAssertEqual(out[0].memUsed, 50)
        XCTAssertEqual(out[0].netDown, 200, accuracy: 0.001)
        XCTAssertEqual(out[0].netUp, 20, accuracy: 0.001)
    }

    func testDownsampleReducesPointCountForLongRange() {
        let base = Date(timeIntervalSince1970: 2_000_000)
        // 600 samples one second apart → into 60s buckets ≈ 10 points
        let samples = (0..<600).map {
            MetricsSample(t: base.addingTimeInterval(Double($0)), cpu: 1, memUsed: 1, memTotal: 100, netDown: 0, netUp: 0)
        }
        let out = MetricsMath.downsample(samples, bucket: 60)
        XCTAssertLessThanOrEqual(out.count, 11)
        XCTAssertGreaterThanOrEqual(out.count, 10)
        // output must be time-sorted
        XCTAssertEqual(out, out.sorted { $0.t < $1.t })
    }

    // MARK: - persistence round-trip

    func testStorePersistsAndReloads() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tm-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = MetricsStore(fileURL: tmp, maxAge: 3600, maxCount: 100, saveEvery: 1)
        let now = Date()
        store.record(MetricsSample(t: now, cpu: 42, memUsed: 5, memTotal: 10, netDown: 1, netUp: 2))

        // saveEvery: 1 persists on the background io queue; wait for the file to appear.
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: tmp.path), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path), "history file was not written")

        let reloaded = MetricsStore(fileURL: tmp, maxAge: 3600, maxCount: 100, saveEvery: 1)
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.samples(since: now.addingTimeInterval(-1)).first?.cpu, 42)
    }

    // MARK: - range config sanity

    func testHistoryRangeLiveHasNoWindow() {
        XCTAssertNil(HistoryRange.live.seconds)
        XCTAssertEqual(HistoryRange.live.bucket, 0)
    }

    func testHistoryRangeWindowsIncrease() {
        let windows = HistoryRange.allCases.compactMap { $0.seconds }
        XCTAssertEqual(windows, windows.sorted())
        XCTAssertEqual(HistoryRange.h24.seconds, 86_400)
    }
}
