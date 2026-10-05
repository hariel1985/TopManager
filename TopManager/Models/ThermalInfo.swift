import Foundation

/// One temperature sensor as reported by the system (name as the hardware names it).
struct TemperatureReading: Equatable {
    let name: String
    let celsius: Double
}

/// CPU temperature summarised from the die sensors.
struct ThermalInfo: Equatable {
    let cpuMax: Double          // °C, hottest CPU die sensor
    let cpuAverage: Double      // °C, mean of the CPU die sensors
    let cpuSensorCount: Int
}

/// Pure, testable selection of CPU sensors (no IOKit).
enum ThermalMath {
    /// CPU die sensors on Apple Silicon: "PMU tdie*" / "PMU2 tdie*" (M2 and later)
    /// and "pACC/eACC MTR Temp Sensor*" (M1). The "tdev" ones sit elsewhere on the
    /// package, "tcal" is a calibration value, "gas gauge battery" is the battery.
    static func isCPUDie(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("tdie") || n.contains("acc mtr temp")
    }

    /// Readings no real sensor produces (unconnected ones report ≤ 0).
    static func isPlausible(_ celsius: Double) -> Bool {
        celsius > 0 && celsius < 150
    }

    /// How hot the CPU die is. Apple Silicon runs into the 90s under sustained load
    /// and only throttles near 105 °C, so the bands sit high on purpose.
    static func level(cpuCelsius t: Double) -> ThermalLevel {
        switch t {
        case 100...: return .critical
        case 90..<100: return .serious
        case 80..<90: return .fair
        default: return .nominal
        }
    }

    static func summarize(_ readings: [TemperatureReading]) -> ThermalInfo? {
        let cpu = readings
            .filter { isCPUDie($0.name) && isPlausible($0.celsius) }
            .map(\.celsius)
        guard let hottest = cpu.max() else { return nil }
        return ThermalInfo(
            cpuMax: hottest,
            cpuAverage: cpu.reduce(0, +) / Double(cpu.count),
            cpuSensorCount: cpu.count
        )
    }
}
