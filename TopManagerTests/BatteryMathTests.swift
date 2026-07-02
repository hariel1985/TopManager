import XCTest
@testable import TopManager

final class BatteryMathTests: XCTestCase {

    func testHealthPercent() {
        // 4000 mAh current full-charge vs 5000 mAh design = 80%
        XCTAssertEqual(BatteryMath.healthPercent(maxCapacity: 4000, designCapacity: 5000), 80, accuracy: 0.001)
    }

    func testHealthPercentZeroDesignIsSafe() {
        XCTAssertEqual(BatteryMath.healthPercent(maxCapacity: 100, designCapacity: 0), 0)
    }

    func testConditionNormalWhenHealthy() {
        XCTAssertEqual(BatteryMath.condition(healthPercent: 92, cycleCount: 120), .normal)
    }

    func testConditionServiceWhenHealthLow() {
        XCTAssertEqual(BatteryMath.condition(healthPercent: 74, cycleCount: 120), .serviceRecommended)
    }

    func testConditionServiceWhenCyclesHigh() {
        XCTAssertEqual(BatteryMath.condition(healthPercent: 95, cycleCount: 1200), .serviceRecommended)
    }

    func testConditionUnknownWhenNoHealth() {
        XCTAssertEqual(BatteryMath.condition(healthPercent: nil, cycleCount: 100), .unknown)
    }

    func testWattsPositiveWhenCharging() {
        // 12 V * 2000 mA = 24 W
        XCTAssertEqual(BatteryMath.watts(volts: 12, milliAmps: 2000), 24, accuracy: 0.001)
    }

    func testWattsNegativeWhenDischarging() {
        XCTAssertEqual(BatteryMath.watts(volts: 12, milliAmps: -1500), -18, accuracy: 0.001)
    }

    func testFormatMinutes() {
        XCTAssertEqual(BatteryMath.formatMinutes(135), "2h 15m")
        XCTAssertEqual(BatteryMath.formatMinutes(45), "45m")
        XCTAssertEqual(BatteryMath.formatMinutes(0), "—")
    }

    func testPowerInfoDerivedValues() {
        let p = PowerInfo(
            hasBattery: true, currentCharge: 66, isCharging: false, isPluggedIn: false,
            fullyCharged: false, cycleCount: 150, designCapacity: 5000, maxCapacity: 4600,
            temperature: 30.5, voltage: 12.0, amperage: -1500, timeToEmpty: 200,
            timeToFull: nil, adapterWatts: nil
        )
        XCTAssertEqual(p.healthPercent ?? 0, 92, accuracy: 0.001)
        XCTAssertEqual(p.condition, .normal)
        XCTAssertEqual(p.powerWatts ?? 0, -18, accuracy: 0.001)
        XCTAssertEqual(p.powerSourceLabel, "Battery Power")
    }
}
