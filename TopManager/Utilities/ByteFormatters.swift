import Foundation

func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
    return formatter.string(fromByteCount: Int64(bytes))
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
    return formatter.string(fromByteCount: bytes)
}

func formatBytes(_ bytes: Double) -> String {
    formatBytes(UInt64(max(0, bytes)))
}

func formatBytesPerSecond(_ bytesPerSecond: Double) -> String {
    let absValue = abs(bytesPerSecond)

    if absValue < 1 {
        return "0 B/s"
    }

    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
    return formatter.string(fromByteCount: Int64(absValue)) + "/s"
}

func formatBytesCompact(_ bytes: Double) -> String {
    let absValue = abs(bytes)

    if absValue < 1 {
        return "0"
    } else if absValue < 1024 {
        return String(format: "%.0f B", absValue)
    } else if absValue < 1024 * 1024 {
        return String(format: "%.1f KB", absValue / 1024)
    } else if absValue < 1024 * 1024 * 1024 {
        return String(format: "%.1f MB", absValue / (1024 * 1024))
    } else {
        return String(format: "%.2f GB", absValue / (1024 * 1024 * 1024))
    }
}

func formatPercentage(_ value: Double, decimals: Int = 1) -> String {
    String(format: "%.\(decimals)f%%", value)
}

func formatUptime(_ interval: TimeInterval) -> String {
    let days = Int(interval) / 86400
    let hours = (Int(interval) % 86400) / 3600
    let minutes = (Int(interval) % 3600) / 60

    if days > 0 {
        return "\(days)d \(hours)h \(minutes)m"
    } else if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else {
        return "\(minutes)m"
    }
}
