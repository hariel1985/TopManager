import XCTest
@testable import TopManager

final class ProcessDataTests: XCTestCase {

    // MARK: - KERN_PROCARGS2 parsing

    private func buildProcArgsBuffer(argc: Int32, path: String, args: [String], env: [String]) -> [UInt8] {
        var bytes: [UInt8] = [
            UInt8(argc & 0xff),
            UInt8((argc >> 8) & 0xff),
            UInt8((argc >> 16) & 0xff),
            UInt8((argc >> 24) & 0xff)
        ]
        bytes += Array(path.utf8) + [0]
        bytes += [0, 0] // NUL padding before argv[0]
        for a in args { bytes += Array(a.utf8) + [0] }
        for e in env { bytes += Array(e.utf8) + [0] }
        return bytes
    }

    func testProcArgsParseExtractsPathAndArgs() {
        let buffer = buildProcArgsBuffer(argc: 2, path: "/bin/foo",
                                         args: ["/bin/foo", "--flag"],
                                         env: ["PATH=/usr/bin"])
        let parsed = ProcArgs.parse(buffer)
        XCTAssertEqual(parsed?.path, "/bin/foo")
        XCTAssertEqual(parsed?.args, ["/bin/foo", "--flag"])
    }

    func testProcArgsParseStopsAtArgcAndIgnoresEnv() {
        // argc=1 → only the first arg is returned, env is not leaked into args
        let buffer = buildProcArgsBuffer(argc: 1, path: "/usr/bin/x",
                                         args: ["/usr/bin/x"],
                                         env: ["SECRET=shh"])
        let parsed = ProcArgs.parse(buffer)
        XCTAssertEqual(parsed?.args, ["/usr/bin/x"])
        XCTAssertFalse(parsed?.args.contains { $0.contains("SECRET") } ?? true)
    }

    func testProcArgsParseZeroArgc() {
        let buffer = buildProcArgsBuffer(argc: 0, path: "/bin/x", args: [], env: [])
        let parsed = ProcArgs.parse(buffer)
        XCTAssertEqual(parsed?.path, "/bin/x")
        XCTAssertEqual(parsed?.args, [])
    }

    func testProcArgsParseTooShortReturnsNil() {
        XCTAssertNil(ProcArgs.parse([1, 2, 3]))
    }

    // MARK: - Energy model

    func testEnergyImpactMonotonicInCPU() {
        XCTAssertGreaterThan(
            EnergyModel.impact(cpuPercent: 50, idleWakeupsPerSec: 0),
            EnergyModel.impact(cpuPercent: 10, idleWakeupsPerSec: 0)
        )
    }

    func testEnergyImpactMonotonicInWakeups() {
        XCTAssertGreaterThan(
            EnergyModel.impact(cpuPercent: 10, idleWakeupsPerSec: 500),
            EnergyModel.impact(cpuPercent: 10, idleWakeupsPerSec: 0)
        )
    }

    func testEnergyImpactClampsNegativeInputsToZero() {
        XCTAssertEqual(EnergyModel.impact(cpuPercent: -5, idleWakeupsPerSec: -100), 0, accuracy: 0.0001)
    }

    func testEnergyImpactEqualsCPUWhenNoWakeups() {
        XCTAssertEqual(EnergyModel.impact(cpuPercent: 33, idleWakeupsPerSec: 0), 33, accuracy: 0.0001)
    }

    // MARK: - ProcessItem derived + equality

    func testDiskTotalRateSumsReadAndWrite() {
        let p = ProcessItem(pid: 1, name: "a", user: "u", cpuUsage: 0, cpuUsageTotal: 0,
                            memoryUsage: 0, threadCount: 0, state: .running, icon: nil,
                            parentPid: 0, startTime: nil, diskReadRate: 100, diskWriteRate: 50)
        XCTAssertEqual(p.diskTotalRate, 150)
    }

    func testEqualityDetectsEnergyChange() {
        func make(energy: Double) -> ProcessItem {
            ProcessItem(pid: 1, name: "a", user: "u", cpuUsage: 1, cpuUsageTotal: 1,
                        memoryUsage: 1, threadCount: 1, state: .running, icon: nil,
                        parentPid: 0, startTime: nil, energyImpact: energy)
        }
        // Table refresh relies on == seeing energy/disk changes.
        XCTAssertNotEqual(make(energy: 5), make(energy: 9))
        XCTAssertEqual(make(energy: 5), make(energy: 5))
    }

    // MARK: - Live sampling

    /// Fetches 1–3 are full refreshes; 4 and 5 are lightweight ones, which used
    /// to report 0 memory for every idle process (~90% of rows). Only processes
    /// spawned between fetches may legitimately have no reading yet.
    func testLightweightRefreshKeepsLastKnownMemory() {
        let monitor = ProcessMonitor()
        let me = NSUserName()
        for fetch in 1...6 {
            let own = monitor.fetchProcesses().filter { $0.user == me }
            XCTAssertFalse(own.isEmpty)
            let zero = own.filter { $0.memoryUsage == 0 }.count
            XCTAssertLessThan(zero, max(3, own.count / 10),
                              "fetch \(fetch): \(zero) of \(own.count) own processes reported 0 memory")
            let zeroRAM = own.filter { $0.residentMemory == 0 }.count
            XCTAssertLessThan(zeroRAM, max(3, own.count / 10),
                              "fetch \(fetch): \(zeroRAM) of \(own.count) own processes reported 0 RAM")
        }
    }

    func testOwnProcessReportsResidentMemory() {
        let item = ProcessMonitor().fetchProcesses().first { $0.pid == getpid() }
        XCTAssertNotNil(item)
        XCTAssertGreaterThan(item?.residentMemory ?? 0, 0)
        XCTAssertGreaterThan(item?.memoryUsage ?? 0, 0)
    }

    /// A task name port is granted for our own processes only; launchd runs as root.
    func testCompressedMemoryReadableForOwnProcessesOnly() {
        XCTAssertNotNil(fetchCompressedMemory(pid: getpid()))
        XCTAssertNil(fetchCompressedMemory(pid: 1))
    }
}
