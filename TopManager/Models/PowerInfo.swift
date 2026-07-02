import Foundation

/// Battery / power state. Mirrors what Activity Monitor's Energy tab and the
/// macOS battery menu surface, which TopManager currently lacks entirely.
struct PowerInfo {
    let hasBattery: Bool
    let currentCharge: Int          // 0–100 %
    let isCharging: Bool
    let isPluggedIn: Bool           // external power connected
    let fullyCharged: Bool
    let cycleCount: Int?
    let designCapacity: Int?        // mAh
    let maxCapacity: Int?           // mAh (current full-charge capacity)
    let temperature: Double?        // °C
    let voltage: Double?            // volts
    let amperage: Int?              // mA (negative while discharging)
    let timeToEmpty: Int?           // minutes (nil if unknown/charging)
    let timeToFull: Int?            // minutes (nil if unknown/discharging)
    let adapterWatts: Int?          // power adapter rating

    /// Battery health as current-full-charge ÷ design capacity.
    var healthPercent: Double? {
        guard let maxCapacity, let designCapacity, designCapacity > 0 else { return nil }
        return BatteryMath.healthPercent(maxCapacity: maxCapacity, designCapacity: designCapacity)
    }

    var condition: BatteryCondition {
        BatteryMath.condition(healthPercent: healthPercent, cycleCount: cycleCount)
    }

    /// Instantaneous power flow in watts (positive = charging, negative = draining).
    var powerWatts: Double? {
        guard let voltage, let amperage else { return nil }
        return BatteryMath.watts(volts: voltage, milliAmps: amperage)
    }

    var powerSourceLabel: String {
        isPluggedIn ? "AC Power" : "Battery Power"
    }
}

enum BatteryCondition: String {
    case normal = "Normal"
    case serviceRecommended = "Service Recommended"
    case unknown = "Unknown"

    var color: String {
        switch self {
        case .normal: return "green"
        case .serviceRecommended: return "orange"
        case .unknown: return "gray"
        }
    }
}

/// Pure, testable battery math (no IOKit, no clock).
enum BatteryMath {
    static func healthPercent(maxCapacity: Int, designCapacity: Int) -> Double {
        guard designCapacity > 0 else { return 0 }
        return Double(maxCapacity) / Double(designCapacity) * 100
    }

    /// Apple flags "Service Recommended" as health degrades or cycles climb.
    /// This approximates that classification from the raw numbers.
    static func condition(healthPercent: Double?, cycleCount: Int?) -> BatteryCondition {
        guard let healthPercent else { return .unknown }
        if healthPercent < 80 { return .serviceRecommended }
        if let cycleCount, cycleCount > 1000 { return .serviceRecommended }
        return .normal
    }

    static func watts(volts: Double, milliAmps: Int) -> Double {
        volts * Double(milliAmps) / 1000.0
    }

    /// Format a minutes duration as "2h 15m" / "45m"; nil-safe caller.
    static func formatMinutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
