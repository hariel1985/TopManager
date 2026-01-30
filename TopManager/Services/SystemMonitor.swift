import Foundation
import Combine

@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    // Published properties
    @Published var cpuInfo: CPUInfo?
    @Published var memoryInfo: MemoryInfo?
    @Published var processes: [ProcessItem] = []
    @Published var diskInfo: DiskInfo?
    @Published var networkInfo: NetworkInfo?
    @Published var gpuInfo: GPUInfo?
    @Published var lastError: String?

    // History for charts
    @Published var cpuHistory: [CPUHistoryPoint] = []
    @Published var coreHistories: [Int: [CoreHistoryPoint]] = [:]
    @Published var memoryHistory: [MemoryHistoryPoint] = []
    @Published var networkHistory: [NetworkHistoryPoint] = []

    // Sub-monitors
    private let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let processMonitor = ProcessMonitor()
    private let diskMonitor = DiskMonitor()
    private let networkMonitor = NetworkMonitor()
    private let gpuMonitor = GPUMonitor()

    // Timer
    private var timer: Timer?
    private let historyLimit = 60
    private var refreshCount = 0

    var isAppleSilicon: Bool {
        cpuMonitor.isAppleSilicon
    }

    var thermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }

    private init() {}

    func startMonitoring() {
        // Initial fetch
        Task {
            await refreshAll()
        }

        // Start periodic refresh (2 second interval to reduce CPU usage)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshAll() async {
        refreshCount += 1

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshCPU() }
            group.addTask { await self.refreshMemory() }
            group.addTask { await self.refreshNetwork() }

            // Refresh processes every other cycle = 4 seconds (expensive operation)
            if self.refreshCount % 2 == 0 {
                group.addTask { await self.refreshProcesses() }
            }

            // Refresh disk and GPU every 3 cycles = 6 seconds (less volatile)
            if self.refreshCount % 3 == 0 {
                group.addTask { await self.refreshDisk() }
                group.addTask { await self.refreshGPU() }
            }
        }
    }

    private func refreshCPU() async {
        if let info = cpuMonitor.fetchCPUInfo() {
            cpuInfo = info

            // Global CPU history
            let historyPoint = CPUHistoryPoint(
                timestamp: info.timestamp,
                usage: info.globalUsage,
                userUsage: info.userUsage,
                systemUsage: info.systemUsage
            )
            cpuHistory.append(historyPoint)
            if cpuHistory.count > historyLimit {
                cpuHistory.removeFirst()
            }

            // Per-core history
            for core in info.coreUsages {
                let corePoint = CoreHistoryPoint(
                    timestamp: info.timestamp,
                    usage: core.usage
                )
                if coreHistories[core.id] == nil {
                    coreHistories[core.id] = []
                }
                coreHistories[core.id]?.append(corePoint)
                if coreHistories[core.id]?.count ?? 0 > historyLimit {
                    coreHistories[core.id]?.removeFirst()
                }
            }
        }
    }

    private func refreshMemory() async {
        if let info = memoryMonitor.fetchMemoryInfo() {
            memoryInfo = info

            let historyPoint = MemoryHistoryPoint(
                timestamp: info.timestamp,
                usedMemory: info.usedMemory,
                totalMemory: info.totalMemory
            )
            memoryHistory.append(historyPoint)
            if memoryHistory.count > historyLimit {
                memoryHistory.removeFirst()
            }
        }
    }

    private func refreshProcesses() async {
        processes = processMonitor.fetchProcesses()
    }

    private func refreshDisk() async {
        diskInfo = diskMonitor.fetchDiskInfo()
    }

    private func refreshNetwork() async {
        if let info = networkMonitor.fetchNetworkInfo() as NetworkInfo? {
            networkInfo = info

            let historyPoint = NetworkHistoryPoint(
                timestamp: info.timestamp,
                downloadRate: info.totalDownloadRate,
                uploadRate: info.totalUploadRate
            )
            networkHistory.append(historyPoint)
            if networkHistory.count > historyLimit {
                networkHistory.removeFirst()
            }
        }
    }

    private func refreshGPU() async {
        gpuInfo = gpuMonitor.fetchGPUInfo()
    }

    // Process control methods
    @discardableResult
    func terminateProcess(_ pid: pid_t) -> Bool {
        kill(pid, SIGTERM) == 0
    }

    @discardableResult
    func forceKillProcess(_ pid: pid_t) -> Bool {
        kill(pid, SIGKILL) == 0
    }

    @discardableResult
    func suspendProcess(_ pid: pid_t) -> Bool {
        kill(pid, SIGSTOP) == 0
    }

    @discardableResult
    func resumeProcess(_ pid: pid_t) -> Bool {
        kill(pid, SIGCONT) == 0
    }
}
