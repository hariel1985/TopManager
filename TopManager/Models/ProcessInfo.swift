import Foundation
import AppKit

struct ProcessItem: Identifiable, Hashable {
    let id: pid_t
    let pid: pid_t
    let name: String
    let user: String
    let cpuUsage: Double        // Per-core: 100% = 1 core fully utilized
    let cpuUsageTotal: Double   // Normalized: 100% = all cores fully utilized
    let memoryUsage: Int64      // physical footprint (Activity Monitor's "Memory")
    let residentMemory: Int64   // pages currently in physical RAM, shared ones included
    let compressedMemory: Int64 // original size of pages in the compressor — in RAM or swapped out
    let threadCount: Int32
    let state: ProcessState
    let icon: NSImage?
    let parentPid: pid_t
    let startTime: Date?
    let diskReadRate: Double    // bytes/sec read from disk
    let diskWriteRate: Double   // bytes/sec written to disk
    let diskReadBytes: UInt64   // cumulative bytes read
    let diskWriteBytes: UInt64  // cumulative bytes written
    let energyImpact: Double    // heuristic energy-impact score (proxy for Activity Monitor's)
    let executablePath: String?

    var iconPlaceholder: String { "" }

    var diskTotalRate: Double { diskReadRate + diskWriteRate }

    init(
        pid: pid_t,
        name: String,
        user: String,
        cpuUsage: Double,
        cpuUsageTotal: Double,
        memoryUsage: Int64,
        threadCount: Int32,
        state: ProcessState,
        icon: NSImage?,
        parentPid: pid_t,
        startTime: Date?,
        diskReadRate: Double = 0,
        diskWriteRate: Double = 0,
        diskReadBytes: UInt64 = 0,
        diskWriteBytes: UInt64 = 0,
        energyImpact: Double = 0,
        executablePath: String? = nil,
        residentMemory: Int64 = 0,
        compressedMemory: Int64 = 0
    ) {
        self.id = pid
        self.pid = pid
        self.name = name
        self.user = user
        self.cpuUsage = cpuUsage
        self.cpuUsageTotal = cpuUsageTotal
        self.memoryUsage = memoryUsage
        self.residentMemory = residentMemory
        self.compressedMemory = compressedMemory
        self.threadCount = threadCount
        self.state = state
        self.icon = icon
        self.parentPid = parentPid
        self.startTime = startTime
        self.diskReadRate = diskReadRate
        self.diskWriteRate = diskWriteRate
        self.diskReadBytes = diskReadBytes
        self.diskWriteBytes = diskWriteBytes
        self.energyImpact = energyImpact
        self.executablePath = executablePath
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    static func == (lhs: ProcessItem, rhs: ProcessItem) -> Bool {
        lhs.pid == rhs.pid &&
        lhs.cpuUsage == rhs.cpuUsage &&
        lhs.cpuUsageTotal == rhs.cpuUsageTotal &&
        lhs.memoryUsage == rhs.memoryUsage &&
        lhs.residentMemory == rhs.residentMemory &&
        lhs.compressedMemory == rhs.compressedMemory &&
        lhs.threadCount == rhs.threadCount &&
        lhs.state == rhs.state &&
        lhs.diskReadRate == rhs.diskReadRate &&
        lhs.diskWriteRate == rhs.diskWriteRate &&
        lhs.energyImpact == rhs.energyImpact
    }
}

/// Heuristic "energy impact" proxy. This is *not* Apple's exact private formula;
/// it approximates it: sustained CPU dominates, with a smaller penalty for idle
/// (timer) wakeups, which correlate with power draw even at low CPU.
enum EnergyModel {
    static func impact(cpuPercent: Double, idleWakeupsPerSec: Double) -> Double {
        max(0, cpuPercent) + max(0, idleWakeupsPerSec) * 0.045
    }
}

enum ProcessState: String {
    case running = "Running"
    case sleeping = "Sleeping"
    case stopped = "Stopped"
    case zombie = "Zombie"
    case unknown = "Unknown"

    var symbol: String {
        switch self {
        case .running: return "play.circle.fill"
        case .sleeping: return "moon.fill"
        case .stopped: return "pause.circle.fill"
        case .zombie: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}
