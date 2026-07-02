import XCTest
@testable import TopManager

/// Baseline tests proving the test harness works and locking in the existing
/// formatting / model-math behavior so later refactors can't silently break it.
final class FormattingTests: XCTestCase {

    // MARK: - Byte formatting

    func testFormatBytesZero() {
        // ByteCountFormatter renders 0 as "Zero KB"/"Zero bytes" depending on OS/locale.
        let s = formatBytes(UInt64(0)).lowercased()
        XCTAssertTrue(s.contains("zero") || s.contains("0"), "Unexpected zero rendering: \(s)")
    }

    func testFormatBytesGigabyteScale() {
        // 2 GiB in binary style
        let twoGiB = UInt64(2) * 1024 * 1024 * 1024
        let s = formatBytes(twoGiB)
        XCTAssertTrue(s.contains("GB"), "Expected GB unit, got \(s)")
        XCTAssertTrue(s.contains("2"), "Expected value 2, got \(s)")
    }

    func testFormatBytesNegativeDoubleClampsToZero() {
        // Double overload clamps negatives to 0 rather than trapping on UInt64(negative)
        let s = formatBytes(Double(-500)).lowercased()
        XCTAssertTrue(s.contains("zero") || s.contains("0"), "Unexpected clamp rendering: \(s)")
    }

    func testFormatBytesPerSecondBelowOne() {
        XCTAssertEqual(formatBytesPerSecond(0.4), "0 B/s")
    }

    func testFormatBytesPerSecondSuffix() {
        let s = formatBytesPerSecond(5 * 1024 * 1024) // 5 MiB/s
        XCTAssertTrue(s.hasSuffix("/s"), "Expected /s suffix, got \(s)")
        XCTAssertTrue(s.contains("MB"), "Expected MB unit, got \(s)")
    }

    // MARK: - Percentage

    func testFormatPercentageDefaultDecimals() {
        XCTAssertEqual(formatPercentage(12.345), "12.3%")
    }

    func testFormatPercentageCustomDecimals() {
        XCTAssertEqual(formatPercentage(12.345, decimals: 2), "12.35%")
    }

    // MARK: - Uptime

    func testFormatUptimeMinutesOnly() {
        XCTAssertEqual(formatUptime(45 * 60), "45m")
    }

    func testFormatUptimeHoursAndMinutes() {
        XCTAssertEqual(formatUptime(3 * 3600 + 12 * 60), "3h 12m")
    }

    func testFormatUptimeDays() {
        XCTAssertEqual(formatUptime(2 * 86400 + 5 * 3600 + 9 * 60), "2d 5h 9m")
    }

    // MARK: - Model math

    func testMemoryUsagePercentage() {
        let mem = MemoryInfo(
            totalMemory: 16_000_000_000,
            usedMemory: 8_000_000_000,
            freeMemory: 8_000_000_000,
            activeMemory: 4_000_000_000,
            inactiveMemory: 2_000_000_000,
            wiredMemory: 2_000_000_000,
            compressedMemory: 1_000_000_000,
            cachedMemory: 1_000_000_000,
            swapUsed: 0,
            swapTotal: 0,
            memoryPressure: .nominal
        )
        XCTAssertEqual(mem.usagePercentage, 50.0, accuracy: 0.001)
        XCTAssertEqual(mem.appMemory, 6_000_000_000)
    }

    func testMemoryUsagePercentageZeroTotalIsSafe() {
        let mem = MemoryInfo(
            totalMemory: 0, usedMemory: 0, freeMemory: 0, activeMemory: 0,
            inactiveMemory: 0, wiredMemory: 0, compressedMemory: 0, cachedMemory: 0,
            swapUsed: 0, swapTotal: 0, memoryPressure: .unknown
        )
        XCTAssertEqual(mem.usagePercentage, 0)
    }

    func testVolumeUsagePercentageAndUsedSpace() {
        let vol = VolumeInfo(
            name: "Macintosh HD",
            mountPoint: "/",
            totalSpace: 1000,
            freeSpace: 250,
            fileSystem: "APFS",
            isRemovable: false,
            isInternal: true
        )
        XCTAssertEqual(vol.usedSpace, 750)
        XCTAssertEqual(vol.usagePercentage, 75.0, accuracy: 0.001)
    }

    func testVolumeFreeGreaterThanTotalClampsUsedToZero() {
        let vol = VolumeInfo(
            name: "weird", mountPoint: "/x", totalSpace: 100, freeSpace: 200,
            fileSystem: "APFS", isRemovable: false, isInternal: true
        )
        XCTAssertEqual(vol.usedSpace, 0)
    }
}
