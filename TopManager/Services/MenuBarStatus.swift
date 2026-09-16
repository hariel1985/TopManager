import Foundation

/// The few always-live strings the menu-bar title shows.
///
/// Kept apart from `SystemMonitor` because the monitor stops publishing while no
/// TopManager window is on screen (see `SystemMonitor.setUIVisible`), and the
/// title must keep ticking regardless. Values are pre-formatted and only
/// re-published when the visible text actually changes: `@Published` fires on
/// every assignment, and each firing re-measures the status item.
@MainActor
final class MenuBarStatus: ObservableObject {
    static let shared = MenuBarStatus()

    @Published private(set) var cpuText: String?
    @Published private(set) var memoryText: String?
    @Published private(set) var downloadText: String?

    init() {}

    func update(cpu: CPUInfo?, memory: MemoryInfo?, network: NetworkInfo?) {
        let cpu = cpu.map { String(format: "%.0f%%", $0.globalUsage) }
        if cpu != cpuText { cpuText = cpu }

        let memory = memory.map { String(format: "%.0f%%", $0.usagePercentage) }
        if memory != memoryText { memoryText = memory }

        let download = network.map { formatBytesPerSecond($0.totalDownloadRate) }
        if download != downloadText { downloadText = download }
    }
}
