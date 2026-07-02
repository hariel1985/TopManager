import XCTest
@testable import TopManager

final class SettingsTests: XCTestCase {

    func testClampIntervalBounds() {
        XCTAssertEqual(AppSettings.clampInterval(0.2), 1)
        XCTAssertEqual(AppSettings.clampInterval(100), 30)
        XCTAssertEqual(AppSettings.clampInterval(5), 5)
        XCTAssertEqual(AppSettings.clampInterval(1), 1)
        XCTAssertEqual(AppSettings.clampInterval(30), 30)
    }

    func testMenuBarMetricRoundTrip() {
        for metric in MenuBarMetric.allCases {
            XCTAssertEqual(MenuBarMetric(rawValue: metric.rawValue), metric)
        }
        XCTAssertNil(MenuBarMetric(rawValue: "nonexistent"))
    }

    func testMenuBarMetricCoversKeyMetrics() {
        XCTAssertTrue(MenuBarMetric.allCases.contains(.cpu))
        XCTAssertTrue(MenuBarMetric.allCases.contains(.memory))
        XCTAssertTrue(MenuBarMetric.allCases.contains(.health))
        XCTAssertTrue(MenuBarMetric.allCases.contains(.download))
    }
}
