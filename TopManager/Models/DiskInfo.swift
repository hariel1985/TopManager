import Foundation

struct DiskInfo {
    let volumes: [VolumeInfo]
    let timestamp: Date

    init(volumes: [VolumeInfo], timestamp: Date = Date()) {
        self.volumes = volumes
        self.timestamp = timestamp
    }
}

struct VolumeInfo: Identifiable {
    let id: String
    let name: String
    let mountPoint: String
    let totalSpace: UInt64
    let freeSpace: UInt64
    let usedSpace: UInt64
    let fileSystem: String
    let isRemovable: Bool
    let isInternal: Bool

    var usagePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace) * 100
    }

    init(
        name: String,
        mountPoint: String,
        totalSpace: UInt64,
        freeSpace: UInt64,
        fileSystem: String,
        isRemovable: Bool,
        isInternal: Bool
    ) {
        self.id = mountPoint
        self.name = name
        self.mountPoint = mountPoint
        self.totalSpace = totalSpace
        self.freeSpace = freeSpace
        self.usedSpace = totalSpace > freeSpace ? totalSpace - freeSpace : 0
        self.fileSystem = fileSystem
        self.isRemovable = isRemovable
        self.isInternal = isInternal
    }
}

struct DiskIOStats: Identifiable {
    let id = UUID()
    let timestamp: Date
    let readBytes: UInt64
    let writeBytes: UInt64
    let readRate: Double
    let writeRate: Double
}
