import XCTest
@testable import TopManager

final class ThermalMathTests: XCTestCase {

    // Names as an M3 reports them (PMU / PMU2 dies, package, calibration, NAND, battery).
    private let m3: [TemperatureReading] = [
        .init(name: "PMU tdie1", celsius: 48.8),
        .init(name: "PMU tdie2", celsius: 46.4),
        .init(name: "PMU2 tdie1", celsius: 43.4),
        .init(name: "PMU tdev2", celsius: 36.2),
        .init(name: "PMU tdev1", celsius: -1.5),
        .init(name: "PMU tcal", celsius: 51.9),
        .init(name: "NAND CH0 temp", celsius: 34.0),
        .init(name: "gas gauge battery", celsius: 31.3),
    ]

    func testOnlyDieSensorsCount() {
        let info = ThermalMath.summarize(m3)
        XCTAssertEqual(info?.cpuSensorCount, 3)
        // tcal (51.9) is hotter than every die but is a calibration value, not the CPU.
        XCTAssertEqual(info?.cpuMax ?? 0, 48.8, accuracy: 0.001)
        XCTAssertEqual(info?.cpuAverage ?? 0, (48.8 + 46.4 + 43.4) / 3, accuracy: 0.001)
    }

    func testM1ClusterSensorsCount() {
        let m1: [TemperatureReading] = [
            .init(name: "pACC MTR Temp Sensor0", celsius: 55),
            .init(name: "eACC MTR Temp Sensor1", celsius: 41),
            .init(name: "GPU MTR Temp Sensor1", celsius: 60),
            .init(name: "SOC MTR Temp Sensor0", celsius: 50),
        ]
        let info = ThermalMath.summarize(m1)
        XCTAssertEqual(info?.cpuSensorCount, 2)
        XCTAssertEqual(info?.cpuMax ?? 0, 55, accuracy: 0.001)
    }

    func testImplausibleDieReadingsAreDropped() {
        let readings: [TemperatureReading] = [
            .init(name: "PMU tdie1", celsius: 0),
            .init(name: "PMU tdie2", celsius: -2),
            .init(name: "PMU tdie3", celsius: 170),
            .init(name: "PMU tdie4", celsius: 44),
        ]
        XCTAssertEqual(ThermalMath.summarize(readings)?.cpuSensorCount, 1)
    }

    func testNoCPUSensorsMeansNil() {
        // An Intel Mac: no IOHID die sensors at all, or only non-CPU ones.
        XCTAssertNil(ThermalMath.summarize([]))
        XCTAssertNil(ThermalMath.summarize([.init(name: "gas gauge battery", celsius: 30)]))
    }

    func testReadsRealSensorsOnAppleSilicon() throws {
        #if !arch(arm64)
        throw XCTSkip("Apple Silicon only: Intel Macs expose these sensors through the SMC")
        #else
        let info = try XCTUnwrap(TemperatureMonitor().fetchThermalInfo())
        XCTAssertGreaterThan(info.cpuSensorCount, 0)
        XCTAssertTrue((15...110).contains(info.cpuMax), "implausible CPU temperature \(info.cpuMax)")
        XCTAssertLessThanOrEqual(info.cpuAverage, info.cpuMax)
        #endif
    }

    func testLevels() {
        XCTAssertEqual(ThermalMath.level(cpuCelsius: 48), .nominal)
        XCTAssertEqual(ThermalMath.level(cpuCelsius: 85), .fair)
        XCTAssertEqual(ThermalMath.level(cpuCelsius: 95), .serious)
        XCTAssertEqual(ThermalMath.level(cpuCelsius: 104), .critical)
    }
}
