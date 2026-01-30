import Foundation

struct MemoryInfo {
    let totalMemory: UInt64
    let usedMemory: UInt64
    let freeMemory: UInt64
    let activeMemory: UInt64
    let inactiveMemory: UInt64
    let wiredMemory: UInt64
    let compressedMemory: UInt64
    let cachedMemory: UInt64
    let swapUsed: UInt64
    let swapTotal: UInt64
    let memoryPressure: MemoryPressure
    let timestamp: Date

    var usagePercentage: Double {
        guard totalMemory > 0 else { return 0 }
        return Double(usedMemory) / Double(totalMemory) * 100
    }

    var appMemory: UInt64 {
        activeMemory + inactiveMemory
    }

    init(
        totalMemory: UInt64,
        usedMemory: UInt64,
        freeMemory: UInt64,
        activeMemory: UInt64,
        inactiveMemory: UInt64,
        wiredMemory: UInt64,
        compressedMemory: UInt64,
        cachedMemory: UInt64,
        swapUsed: UInt64,
        swapTotal: UInt64,
        memoryPressure: MemoryPressure,
        timestamp: Date = Date()
    ) {
        self.totalMemory = totalMemory
        self.usedMemory = usedMemory
        self.freeMemory = freeMemory
        self.activeMemory = activeMemory
        self.inactiveMemory = inactiveMemory
        self.wiredMemory = wiredMemory
        self.compressedMemory = compressedMemory
        self.cachedMemory = cachedMemory
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.memoryPressure = memoryPressure
        self.timestamp = timestamp
    }
}

enum MemoryPressure: String {
    case nominal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
    case unknown = "Unknown"

    var color: String {
        switch self {
        case .nominal: return "green"
        case .warning: return "yellow"
        case .critical: return "red"
        case .unknown: return "gray"
        }
    }
}

struct MemoryHistoryPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let usedMemory: UInt64
    let totalMemory: UInt64

    var usagePercentage: Double {
        guard totalMemory > 0 else { return 0 }
        return Double(usedMemory) / Double(totalMemory) * 100
    }
}
