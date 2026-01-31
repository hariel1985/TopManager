import Foundation
import Combine

final class SystemMonitor: ObservableObject {
    @MainActor static let shared = SystemMonitor()

    private let backgroundQueue = DispatchQueue(label: "com.topmanager.monitor", qos: .userInitiated)

    // Published properties (must be updated on main thread)
    @MainActor @Published var cpuInfo: CPUInfo?
    @MainActor @Published var memoryInfo: MemoryInfo?
    @MainActor @Published var processes: [ProcessItem] = []
    @MainActor @Published var diskInfo: DiskInfo?
    @MainActor @Published var networkInfo: NetworkInfo?
    @MainActor @Published var gpuInfo: GPUInfo?
    @MainActor @Published var lastError: String?

    // History for charts
    @MainActor @Published var cpuHistory: [CPUHistoryPoint] = []
    @MainActor @Published var coreHistories: [Int: [CoreHistoryPoint]] = [:]
    @MainActor @Published var memoryHistory: [MemoryHistoryPoint] = []
    @MainActor @Published var networkHistory: [NetworkHistoryPoint] = []

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

    @MainActor var thermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }

    private init() {}

    @MainActor func startMonitoring() {
        // Immediate initial fetch
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }

            // Prime both CPU and process monitors (first call sets baseline for delta calculation)
            _ = self.cpuMonitor.fetchCPUInfo()
            _ = self.processMonitor.fetchProcesses()

            // Delay for meaningful delta calculation (1 second minimum for accurate CPU %)
            Thread.sleep(forTimeInterval: 1.0)

            // Now fetch with valid deltas
            let cpuData = self.cpuMonitor.fetchCPUInfo()
            let memData = self.memoryMonitor.fetchMemoryInfo()
            let netData = self.networkMonitor.fetchNetworkInfo()
            let processData = self.processMonitor.fetchProcesses()
            let diskData = self.diskMonitor.fetchDiskInfo()
            let gpuData = self.gpuMonitor.fetchGPUInfo()

            DispatchQueue.main.async {
                self.updateUI(cpu: cpuData, memory: memData, network: netData,
                             processes: processData, disk: diskData, gpu: gpuData)
            }
        }

        // Start periodic refresh (3 second interval)
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.backgroundQueue.async {
                self?.refreshAllBackground()
            }
        }
    }

    @MainActor func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshAllBackground() {
        refreshCount += 1
        let currentCount = refreshCount

        // Fetch data on background thread
        let cpuData = cpuMonitor.fetchCPUInfo()
        let memData = memoryMonitor.fetchMemoryInfo()
        let netData = networkMonitor.fetchNetworkInfo()

        // Fetch processes: first 3 cycles always, then every other cycle
        var processData: [ProcessItem]? = nil
        if currentCount <= 3 || currentCount % 2 == 0 {
            processData = processMonitor.fetchProcesses()
        }

        // Fetch disk and GPU every 3 cycles
        var diskData: DiskInfo? = nil
        var gpuData: GPUInfo? = nil
        if currentCount % 3 == 0 {
            diskData = diskMonitor.fetchDiskInfo()
            gpuData = gpuMonitor.fetchGPUInfo()
        }

        // Update UI on main thread
        DispatchQueue.main.async { [weak self] in
            self?.updateUI(cpu: cpuData, memory: memData, network: netData,
                          processes: processData, disk: diskData, gpu: gpuData)
        }
    }

    @MainActor private func updateUI(cpu: CPUInfo?, memory: MemoryInfo?, network: NetworkInfo?,
                                      processes: [ProcessItem]?, disk: DiskInfo?, gpu: GPUInfo?) {
        if let info = cpu {
            cpuInfo = info
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

            for core in info.coreUsages {
                let corePoint = CoreHistoryPoint(timestamp: info.timestamp, usage: core.usage)
                if coreHistories[core.id] == nil {
                    coreHistories[core.id] = []
                }
                coreHistories[core.id]?.append(corePoint)
                if coreHistories[core.id]?.count ?? 0 > historyLimit {
                    coreHistories[core.id]?.removeFirst()
                }
            }
        }

        if let info = memory {
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

        if let info = network {
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

        if let procs = processes {
            self.processes = procs
        }

        if let info = disk {
            diskInfo = info
        }

        if let info = gpu {
            gpuInfo = info
        }
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
