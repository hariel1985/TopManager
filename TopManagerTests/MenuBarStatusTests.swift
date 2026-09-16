import XCTest
@testable import TopManager

final class MenuBarStatusTests: XCTestCase {

    private func cpu(_ usage: Double) -> CPUInfo {
        CPUInfo(globalUsage: usage, userUsage: usage, systemUsage: 0, idleUsage: 100 - usage, coreUsages: [])
    }

    @MainActor
    func testFormatsVisibleText() {
        let status = MenuBarStatus()
        status.update(cpu: cpu(41.6), memory: nil, network: nil)
        XCTAssertEqual(status.cpuText, "42%")
        XCTAssertNil(status.memoryText)
        XCTAssertNil(status.downloadText)
    }

    /// Every publish re-measures the status item, so a refresh that renders the
    /// same text must not publish at all.
    @MainActor
    func testRepublishesOnlyWhenVisibleTextChanges() {
        let status = MenuBarStatus()
        var publishes = 0
        let subscription = status.objectWillChange.sink { publishes += 1 }
        defer { subscription.cancel() }

        status.update(cpu: cpu(41.6), memory: nil, network: nil)
        XCTAssertEqual(publishes, 1)
        status.update(cpu: cpu(42.4), memory: nil, network: nil)   // still "42%"
        XCTAssertEqual(publishes, 1)
        status.update(cpu: cpu(57), memory: nil, network: nil)
        XCTAssertEqual(publishes, 2)
    }
}
