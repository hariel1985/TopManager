import Foundation

/// Architecture-neutral thermal level so the pure health model doesn't depend on
/// Foundation's `ProcessInfo.ThermalState` (keeps it trivially unit-testable).
enum ThermalLevel {
    case nominal, fair, serious, critical
}

/// Everything the health score needs, as plain values.
struct HealthInput {
    let cpuUsage: Double            // global CPU %
    let memoryPressure: MemoryPressure
    let swapUsedBytes: UInt64
    let thermal: ThermalLevel
    let diskUsedFraction: Double    // 0…1 for the fullest volume
}

/// Computes a 0–100 "system health" score and a plain-language diagnosis.
/// This is what turns raw numbers into "is my Mac OK, and if not, why?".
enum HealthModel {
    static func score(_ input: HealthInput) -> Int {
        var score = 100.0

        // Sustained high CPU: lose up to ~20 points as usage climbs 60→100%.
        if input.cpuUsage > 60 {
            score -= min(20, (input.cpuUsage - 60) * 0.5)
        }

        switch input.memoryPressure {
        case .warning: score -= 15
        case .critical: score -= 30
        default: break
        }

        if input.swapUsedBytes > 2_000_000_000 { score -= 10 }
        else if input.swapUsedBytes > 500_000_000 { score -= 5 }

        switch input.thermal {
        case .fair: score -= 5
        case .serious: score -= 20
        case .critical: score -= 35
        case .nominal: break
        }

        if input.diskUsedFraction > 0.95 { score -= 15 }
        else if input.diskUsedFraction > 0.90 { score -= 8 }

        return max(0, min(100, Int(score.rounded())))
    }

    static func diagnosis(_ input: HealthInput) -> [String] {
        var issues: [String] = []
        if input.cpuUsage > 85 {
            issues.append("CPU is heavily loaded (\(Int(input.cpuUsage))%)")
        }
        switch input.memoryPressure {
        case .critical: issues.append("Memory pressure is critical — the system is low on RAM")
        case .warning: issues.append("Memory pressure is elevated")
        default: break
        }
        if input.swapUsedBytes > 2_000_000_000 {
            issues.append("High swap usage — closing apps may help")
        }
        switch input.thermal {
        case .serious, .critical: issues.append("System is running hot and may be throttling")
        default: break
        }
        if input.diskUsedFraction > 0.90 {
            issues.append("Startup disk is nearly full (\(Int(input.diskUsedFraction * 100))%)")
        }
        return issues
    }

    static func rating(_ score: Int) -> String {
        switch score {
        case 85...: return "Excellent"
        case 70..<85: return "Good"
        case 50..<70: return "Fair"
        default: return "Poor"
        }
    }
}
