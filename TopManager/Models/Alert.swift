import Foundation

enum AlertSeverity: Int, Comparable {
    case info = 0, warning, critical
    static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
    var symbol: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
    var colorName: String {
        switch self {
        case .info: return "blue"
        case .warning: return "orange"
        case .critical: return "red"
        }
    }
}

/// Distinct alert categories. The kind is the de-dup key: at most one active
/// alert per kind at a time, so we never storm the user with duplicates.
enum AlertKind: String {
    case cpuHigh, memoryPressure, diskFull, thermal, runawayProcess, lowBattery
}

/// Named `SystemAlert` (not `Alert`) to avoid shadowing SwiftUI's `Alert` type
/// inside view files.
struct SystemAlert: Identifiable {
    let id = UUID()
    let kind: AlertKind
    let title: String
    let message: String
    let severity: AlertSeverity
    let timestamp: Date
}

/// User-tunable thresholds (wired to Settings in a later increment; sensible
/// defaults here).
struct AlertThresholds: Equatable {
    var cpuPercent: Double = 90
    var cpuSustainedCycles: Int = 3
    var memoryPressureCritical = true
    var diskUsedFraction: Double = 0.95
    var thermalSerious = true
    var processCpuPercent: Double = 190   // per-core (~1.9 cores) sustained
    var processSustainedCycles: Int = 3
    var lowBatteryPercent = 15
}

/// Pure helper for "sustained" conditions: a breach must persist for N
/// consecutive samples before it fires, and it clears as soon as it recovers.
/// Returned `count` is fed back in on the next call.
enum AlertEvaluator {
    static func sustained(breached: Bool, previousCount: Int, requiredCycles: Int) -> (firing: Bool, count: Int) {
        let count = breached ? previousCount + 1 : 0
        return (count >= requiredCycles, count)
    }
}
