import Foundation
import AppKit

struct ProcessItem: Identifiable, Hashable {
    let id: pid_t
    let pid: pid_t
    let name: String
    let user: String
    let cpuUsage: Double        // Per-core: 100% = 1 core fully utilized
    let cpuUsageTotal: Double   // Normalized: 100% = all cores fully utilized
    let memoryUsage: Int64
    let threadCount: Int32
    let state: ProcessState
    let icon: NSImage?
    let parentPid: pid_t
    let startTime: Date?

    var iconPlaceholder: String { "" }

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
        startTime: Date?
    ) {
        self.id = pid
        self.pid = pid
        self.name = name
        self.user = user
        self.cpuUsage = cpuUsage
        self.cpuUsageTotal = cpuUsageTotal
        self.memoryUsage = memoryUsage
        self.threadCount = threadCount
        self.state = state
        self.icon = icon
        self.parentPid = parentPid
        self.startTime = startTime
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    static func == (lhs: ProcessItem, rhs: ProcessItem) -> Bool {
        lhs.pid == rhs.pid &&
        lhs.cpuUsage == rhs.cpuUsage &&
        lhs.cpuUsageTotal == rhs.cpuUsageTotal &&
        lhs.memoryUsage == rhs.memoryUsage &&
        lhs.threadCount == rhs.threadCount &&
        lhs.state == rhs.state
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
