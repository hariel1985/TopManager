import Foundation

struct GPUInfo {
    let name: String
    let vramUsed: UInt64
    let vramTotal: UInt64?
    let utilizationPercent: Double?
    let isUnifiedMemory: Bool
    let coreCount: Int?
    let timestamp: Date

    var vramUsagePercentage: Double? {
        guard let total = vramTotal, total > 0 else { return nil }
        return Double(vramUsed) / Double(total) * 100
    }

    var memoryLabel: String {
        isUnifiedMemory ? "GPU Memory" : "VRAM"
    }

    init(
        name: String,
        vramUsed: UInt64,
        vramTotal: UInt64?,
        utilizationPercent: Double?,
        isUnifiedMemory: Bool = false,
        coreCount: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.name = name
        self.vramUsed = vramUsed
        self.vramTotal = vramTotal
        self.utilizationPercent = utilizationPercent
        self.isUnifiedMemory = isUnifiedMemory
        self.coreCount = coreCount
        self.timestamp = timestamp
    }
}

struct GPUHistoryPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let vramUsed: UInt64
    let utilizationPercent: Double?
}
