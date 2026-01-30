import Foundation

struct NetworkInfo {
    let interfaces: [NetworkInterface]
    let totalDownloadRate: Double
    let totalUploadRate: Double
    let totalDownloadBytes: UInt64
    let totalUploadBytes: UInt64
    let timestamp: Date

    init(
        interfaces: [NetworkInterface],
        totalDownloadRate: Double,
        totalUploadRate: Double,
        totalDownloadBytes: UInt64,
        totalUploadBytes: UInt64,
        timestamp: Date = Date()
    ) {
        self.interfaces = interfaces
        self.totalDownloadRate = totalDownloadRate
        self.totalUploadRate = totalUploadRate
        self.totalDownloadBytes = totalDownloadBytes
        self.totalUploadBytes = totalUploadBytes
        self.timestamp = timestamp
    }
}

struct NetworkInterface: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let downloadBytes: UInt64
    let uploadBytes: UInt64
    let downloadRate: Double
    let uploadRate: Double
    let isActive: Bool

    init(
        name: String,
        displayName: String,
        downloadBytes: UInt64,
        uploadBytes: UInt64,
        downloadRate: Double,
        uploadRate: Double,
        isActive: Bool
    ) {
        self.id = name
        self.name = name
        self.displayName = displayName
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.isActive = isActive
    }
}

struct NetworkHistoryPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let downloadRate: Double
    let uploadRate: Double
}
