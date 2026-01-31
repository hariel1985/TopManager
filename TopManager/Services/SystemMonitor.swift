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

    // Process control methods with PID validation

    /// Validates that a PID still refers to the same process before sending a signal
    private func validateProcess(pid: pid_t, expectedStartTime: Date?) -> ProcessControlError? {
        var bsdInfo = proc_bsdinfo()
        let bsdInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdInfoSize)

        // Check if process still exists
        guard result == bsdInfoSize else {
            return .processNotFound
        }

        // Validate start time matches (detects PID reuse)
        if let expected = expectedStartTime {
            let currentStartTime = Date(timeIntervalSince1970: TimeInterval(bsdInfo.pbi_start_tvsec))
            // Allow 1 second tolerance for timing differences
            if abs(currentStartTime.timeIntervalSince(expected)) > 1.0 {
                return .processChanged
            }
        }

        return nil // Validation passed
    }

    func terminateProcess(_ pid: pid_t, expectedStartTime: Date? = nil) -> Result<Void, ProcessControlError> {
        // Validate PID still refers to same process
        if let error = validateProcess(pid: pid, expectedStartTime: expectedStartTime) {
            return .failure(error)
        }

        let result = kill(pid, SIGTERM)
        if result == 0 {
            return .success(())
        } else {
            return .failure(ProcessControlError.fromErrno(errno))
        }
    }

    func forceKillProcess(_ pid: pid_t, expectedStartTime: Date? = nil) -> Result<Void, ProcessControlError> {
        // Validate PID still refers to same process
        if let error = validateProcess(pid: pid, expectedStartTime: expectedStartTime) {
            return .failure(error)
        }

        let result = kill(pid, SIGKILL)
        if result == 0 {
            return .success(())
        } else {
            return .failure(ProcessControlError.fromErrno(errno))
        }
    }

    func suspendProcess(_ pid: pid_t, expectedStartTime: Date? = nil) -> Result<Void, ProcessControlError> {
        if let error = validateProcess(pid: pid, expectedStartTime: expectedStartTime) {
            return .failure(error)
        }

        let result = kill(pid, SIGSTOP)
        if result == 0 {
            return .success(())
        } else {
            return .failure(ProcessControlError.fromErrno(errno))
        }
    }

    func resumeProcess(_ pid: pid_t, expectedStartTime: Date? = nil) -> Result<Void, ProcessControlError> {
        if let error = validateProcess(pid: pid, expectedStartTime: expectedStartTime) {
            return .failure(error)
        }

        let result = kill(pid, SIGCONT)
        if result == 0 {
            return .success(())
        } else {
            return .failure(ProcessControlError.fromErrno(errno))
        }
    }
}

// MARK: - Process Control Errors

enum ProcessControlError: Error, LocalizedError {
    case processNotFound
    case processChanged
    case permissionDenied
    case unknownError(Int32)

    var errorDescription: String? {
        switch self {
        case .processNotFound:
            return "Process no longer exists"
        case .processChanged:
            return "Process has changed (PID was reused by another process)"
        case .permissionDenied:
            return "Permission denied"
        case .unknownError(let code):
            return "Operation failed (error code: \(code))"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .processNotFound:
            return "The process may have exited on its own."
        case .processChanged:
            return "Please refresh the process list and try again."
        case .permissionDenied:
            return "You don't have permission to control this process. It may be owned by another user or the system."
        case .unknownError:
            return "Please try again or check system logs."
        }
    }

    static func fromErrno(_ errno: Int32) -> ProcessControlError {
        switch errno {
        case ESRCH:
            return .processNotFound
        case EPERM:
            return .permissionDenied
        default:
            return .unknownError(errno)
        }
    }
}
