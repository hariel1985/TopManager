import Foundation
import IOKit

/// Reads battery / power state from the AppleSmartBattery IORegistry entry.
/// No entitlements or root required. On a desktop Mac (no battery) it reports
/// `hasBattery == false` and AC power.
final class PowerMonitor {

    func fetchPowerInfo() -> PowerInfo {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            // No battery (e.g. Mac mini / Studio / Pro): assume AC power.
            return PowerInfo(
                hasBattery: false, currentCharge: 100, isCharging: false, isPluggedIn: true,
                fullyCharged: true, cycleCount: nil, designCapacity: nil, maxCapacity: nil,
                temperature: nil, voltage: nil, amperage: nil, timeToEmpty: nil,
                timeToFull: nil, adapterWatts: nil
            )
        }
        defer { IOObjectRelease(service) }

        var unmanagedProps: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanagedProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanagedProps?.takeRetainedValue() as? [String: Any] else {
            return PowerInfo(
                hasBattery: false, currentCharge: 100, isCharging: false, isPluggedIn: true,
                fullyCharged: true, cycleCount: nil, designCapacity: nil, maxCapacity: nil,
                temperature: nil, voltage: nil, amperage: nil, timeToEmpty: nil,
                timeToFull: nil, adapterWatts: nil
            )
        }

        let int = { (key: String) -> Int? in props[key] as? Int }
        let bool = { (key: String) -> Bool? in props[key] as? Bool }

        // Percent charge: CurrentCapacity is 0–100 on Apple Silicon.
        let currentCharge = int("CurrentCapacity") ?? 0
        let isCharging = bool("IsCharging") ?? false
        let isPluggedIn = bool("ExternalConnected") ?? false
        let fullyCharged = bool("FullyCharged") ?? false
        let cycleCount = int("CycleCount")
        let designCapacity = int("DesignCapacity")
        // Raw (mAh) capacity is the meaningful "full charge capacity" on AS.
        let maxCapacity = int("AppleRawMaxCapacity") ?? int("MaxCapacity")
        let temperature = int("Temperature").map { Double($0) / 100.0 }   // centi-°C
        let voltage = int("Voltage").map { Double($0) / 1000.0 }          // mV → V
        let amperage = int("Amperage")

        let timeToEmpty = normalizedMinutes(int("AvgTimeToEmpty"), valid: !isPluggedIn)
        let timeToFull = normalizedMinutes(int("AvgTimeToFull"), valid: isCharging)

        let adapterWatts = (props["AdapterDetails"] as? [String: Any])?["Watts"] as? Int

        return PowerInfo(
            hasBattery: true,
            currentCharge: currentCharge,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            fullyCharged: fullyCharged,
            cycleCount: cycleCount,
            designCapacity: designCapacity,
            maxCapacity: maxCapacity,
            temperature: temperature,
            voltage: voltage,
            amperage: amperage,
            timeToEmpty: timeToEmpty,
            timeToFull: timeToFull,
            adapterWatts: adapterWatts
        )
    }

    /// AppleSmartBattery reports 65535 (or 0) for "still calculating"; treat as unknown.
    private func normalizedMinutes(_ value: Int?, valid: Bool) -> Int? {
        guard valid, let value, value > 0, value != 65535 else { return nil }
        return value
    }
}
