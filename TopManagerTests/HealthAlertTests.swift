import XCTest
@testable import TopManager

final class HealthAlertTests: XCTestCase {

    private func healthy() -> HealthInput {
        HealthInput(cpuUsage: 10, memoryPressure: .nominal, swapUsedBytes: 0,
                    thermal: .nominal, diskUsedFraction: 0.4)
    }

    // MARK: - Health score

    func testHealthyScoreIsExcellent() {
        let s = HealthModel.score(healthy())
        XCTAssertEqual(s, 100)
        XCTAssertEqual(HealthModel.rating(s), "Excellent")
    }

    func testHighCPULowersScore() {
        var input = healthy()
        input = HealthInput(cpuUsage: 100, memoryPressure: .nominal, swapUsedBytes: 0,
                            thermal: .nominal, diskUsedFraction: 0.4)
        XCTAssertLessThan(HealthModel.score(input), HealthModel.score(healthy()))
    }

    func testCriticalMemoryAndThermalCompound() {
        let input = HealthInput(cpuUsage: 95, memoryPressure: .critical, swapUsedBytes: 3_000_000_000,
                                thermal: .critical, diskUsedFraction: 0.97)
        let s = HealthModel.score(input)
        XCTAssertLessThan(s, 50)
        XCTAssertEqual(HealthModel.rating(s), "Poor")
        XCTAssertGreaterThanOrEqual(s, 0)
    }

    func testScoreClampedToRange() {
        // Absolute worst case must not underflow below 0.
        let worst = HealthInput(cpuUsage: 100, memoryPressure: .critical, swapUsedBytes: .max,
                                thermal: .critical, diskUsedFraction: 1.0)
        let s = HealthModel.score(worst)
        XCTAssertTrue((0...100).contains(s))
    }

    func testDiagnosisEmptyWhenHealthy() {
        XCTAssertTrue(HealthModel.diagnosis(healthy()).isEmpty)
    }

    func testDiagnosisReportsProblems() {
        let input = HealthInput(cpuUsage: 95, memoryPressure: .critical, swapUsedBytes: 3_000_000_000,
                                thermal: .serious, diskUsedFraction: 0.93)
        let d = HealthModel.diagnosis(input)
        XCTAssertFalse(d.isEmpty)
        XCTAssertTrue(d.contains { $0.localizedCaseInsensitiveContains("CPU") })
        XCTAssertTrue(d.contains { $0.localizedCaseInsensitiveContains("memory") })
        XCTAssertTrue(d.contains { $0.localizedCaseInsensitiveContains("disk") })
    }

    // MARK: - Alert sustained evaluator

    func testSustainedFiresOnlyAfterRequiredCycles() {
        var count = 0
        var result = AlertEvaluator.sustained(breached: true, previousCount: count, requiredCycles: 3)
        count = result.count
        XCTAssertFalse(result.firing)   // 1
        result = AlertEvaluator.sustained(breached: true, previousCount: count, requiredCycles: 3)
        count = result.count
        XCTAssertFalse(result.firing)   // 2
        result = AlertEvaluator.sustained(breached: true, previousCount: count, requiredCycles: 3)
        count = result.count
        XCTAssertTrue(result.firing)    // 3 → fires
    }

    func testSustainedResetsWhenConditionClears() {
        var count = 5
        let result = AlertEvaluator.sustained(breached: false, previousCount: count, requiredCycles: 3)
        count = result.count
        XCTAssertFalse(result.firing)
        XCTAssertEqual(count, 0)
    }

    func testSeverityOrdering() {
        XCTAssertTrue(AlertSeverity.info < AlertSeverity.warning)
        XCTAssertTrue(AlertSeverity.warning < AlertSeverity.critical)
    }

    // MARK: - AlertCenter integration (de-dup + inbox)

    @MainActor
    func testAlertCenterDedupesAndClearsActiveKinds() {
        let center = AlertCenter.shared
        center.clearInbox()

        let mem = MemoryInfo(totalMemory: 16, usedMemory: 15, freeMemory: 1, activeMemory: 8,
                             inactiveMemory: 2, wiredMemory: 3, compressedMemory: 2, cachedMemory: 0,
                             swapUsed: 0, swapTotal: 0, memoryPressure: .critical)

        let before = center.alerts.count
        // Two consecutive critical-pressure evaluations → only ONE alert (de-dup).
        center.evaluate(cpuUsage: 5, memory: mem, disk: nil, thermal: .nominal, topProcess: nil, power: nil)
        center.evaluate(cpuUsage: 5, memory: mem, disk: nil, thermal: .nominal, topProcess: nil, power: nil)
        XCTAssertEqual(center.alerts.count, before + 1, "critical memory pressure should fire exactly once")
        XCTAssertTrue(center.activeKinds.contains(.memoryPressure))

        // Pressure recovers → active kind clears, no new alert added.
        let ok = MemoryInfo(totalMemory: 16, usedMemory: 4, freeMemory: 12, activeMemory: 2,
                            inactiveMemory: 1, wiredMemory: 1, compressedMemory: 0, cachedMemory: 0,
                            swapUsed: 0, swapTotal: 0, memoryPressure: .nominal)
        center.evaluate(cpuUsage: 5, memory: ok, disk: nil, thermal: .nominal, topProcess: nil, power: nil)
        XCTAssertFalse(center.activeKinds.contains(.memoryPressure))
    }
}
