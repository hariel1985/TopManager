import Foundation
import Darwin
import AppKit

final class ProcessMonitor {
    private var previousCPUTimes: [pid_t: (user: UInt64, system: UInt64, timestamp: Date)] = [:]
    private var lastKnownCPU: [pid_t: Double] = [:]  // Cache last known CPU usage
    private let iconCache = NSCache<NSNumber, NSImage>()
    private var noIconPids: Set<pid_t> = []  // Cache for PIDs with no icon
    private var nameCache: [pid_t: String] = [:]
    private var userCache: [uid_t: String] = [:]
    private let timebaseInfo: mach_timebase_info_data_t
    private var refreshCounter = 0
    private let processorCount = Double(ProcessInfo.processInfo.processorCount)

    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        self.timebaseInfo = info
    }

    func fetchProcesses() -> [ProcessItem] {
        refreshCounter += 1
        // Full refresh on first 3 calls (to establish baselines) and then every 3rd call
        let isFullRefresh = refreshCounter <= 3 || refreshCounter % 3 == 0

        var pids = [pid_t](repeating: 0, count: 2048)
        let bytesUsed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))

        guard bytesUsed > 0 else { return [] }

        let pidCount = Int(bytesUsed) / MemoryLayout<pid_t>.size
        var processes: [ProcessItem] = []
        var currentPids = Set<pid_t>()

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }
            currentPids.insert(pid)

            if let process = fetchProcessInfo(pid: pid, fullRefresh: isFullRefresh) {
                processes.append(process)
                lastKnownCPU[pid] = process.cpuUsage
            }
        }

        // Clean up caches for terminated processes
        let stalePids = Set(nameCache.keys).subtracting(currentPids)
        for pid in stalePids {
            nameCache.removeValue(forKey: pid)
            iconCache.removeObject(forKey: NSNumber(value: pid))
            previousCPUTimes.removeValue(forKey: pid)
            noIconPids.remove(pid)
            lastKnownCPU.removeValue(forKey: pid)
        }

        return processes
    }

    private func fetchProcessInfo(pid: pid_t, fullRefresh: Bool = true) -> ProcessItem? {
        var bsdInfo = proc_bsdinfo()
        let bsdInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let bsdResult = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdInfoSize)

        // If proc_pidinfo fails, use sysctl to get basic info (works for processes we don't own)
        if bsdResult != bsdInfoSize {
            return fetchBasicProcessInfo(pid: pid)
        }

        let name = fetchProcessName(pid: pid, bsdInfo: bsdInfo)
        let user = fetchUsername(uid: bsdInfo.pbi_uid)
        let parentPid = pid_t(bsdInfo.pbi_ppid)
        let startTime = Date(timeIntervalSince1970: TimeInterval(bsdInfo.pbi_start_tvsec))

        // Check if we should do a lightweight refresh
        // Skip expensive calls for processes with 0 CPU last time (unless full refresh)
        let lastCPU = lastKnownCPU[pid] ?? 0
        let needsDetailedInfo = fullRefresh || lastCPU > 0.1

        let memoryUsage: Int64
        let threadCount: Int32
        let cpuUsage: Double

        if needsDetailedInfo {
            var taskInfo = proc_taskinfo()
            let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let taskResult = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
            let hasTaskInfo = taskResult == taskInfoSize

            if hasTaskInfo {
                let rusageData = fetchRusageData(pid: pid)
                memoryUsage = rusageData.memory
                threadCount = taskInfo.pti_threadnum
                cpuUsage = calculateCPUUsage(
                    pid: pid,
                    userTime: rusageData.userTime,
                    systemTime: rusageData.systemTime
                )
            } else {
                memoryUsage = 0
                threadCount = 0
                cpuUsage = 0
            }
        } else {
            // Lightweight refresh - reuse last known values
            memoryUsage = 0
            threadCount = 0
            cpuUsage = 0
        }

        let state = determineProcessState(status: bsdInfo.pbi_status, cpuUsage: cpuUsage)

        let icon = fetchIcon(pid: pid)

        // Calculate normalized CPU (100% = all cores)
        let cpuUsageTotal = cpuUsage / processorCount

        return ProcessItem(
            pid: pid,
            name: name,
            user: user,
            cpuUsage: cpuUsage,
            cpuUsageTotal: cpuUsageTotal,
            memoryUsage: memoryUsage,
            threadCount: threadCount,
            state: state,
            icon: icon,
            parentPid: parentPid,
            startTime: startTime
        )
    }

    private func fetchProcessName(pid: pid_t, bsdInfo: proc_bsdinfo) -> String {
        // Check cache first
        if let cached = nameCache[pid] {
            return cached
        }

        // DEFENSIVE: Use explicit constant instead of magic number
        // PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN = 4 * 1024 = 4096
        let maxPathSize = 4096
        var pathBuffer = [CChar](repeating: 0, count: maxPathSize)

        // proc_pidpath returns length WITHOUT null terminator, or 0 on error
        let pathLength = Int(proc_pidpath(pid, &pathBuffer, UInt32(maxPathSize)))

        let name: String
        if pathLength > 0 && pathLength < maxPathSize {
            // DEFENSIVE: Create string from explicit length, don't rely on null terminator
            // This protects against edge cases where buffer might not be null-terminated
            let pathData = Data(bytes: pathBuffer, count: pathLength)
            if let path = String(data: pathData, encoding: .utf8) {
                name = (path as NSString).lastPathComponent
            } else {
                name = "Process \(pid)"
            }
        } else {
            // DEFENSIVE: Safe BSD name extraction with guaranteed null termination
            // Don't trust that pbi_name is null-terminated within MAXCOMLEN bounds
            var bsdNameBytes = bsdInfo.pbi_name

            let bsdName = withUnsafeBytes(of: &bsdNameBytes) { rawPtr -> String in
                let maxLen = Int(MAXCOMLEN)
                // Create a safe buffer with guaranteed null terminator at end
                var safeBuffer = [UInt8](repeating: 0, count: maxLen + 1)

                // Copy only up to maxLen bytes, leaving the last byte as null
                let bytesToCopy = min(rawPtr.count, maxLen)
                for i in 0..<bytesToCopy {
                    safeBuffer[i] = rawPtr[i]
                }

                // Now safe to use String(cString:) - buffer is guaranteed null-terminated
                return safeBuffer.withUnsafeBufferPointer { bufPtr in
                    bufPtr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: safeBuffer.count) {
                        String(cString: $0)
                    }
                }
            }

            // DEFENSIVE: Clean control characters and whitespace that could be injected
            let cleanedName = bsdName.trimmingCharacters(in: .controlCharacters.union(.whitespaces))
            name = cleanedName.isEmpty ? "Process \(pid)" : cleanedName
        }

        nameCache[pid] = name
        return name
    }

    private func fetchUsername(uid: uid_t) -> String {
        if let cached = userCache[uid] {
            return cached
        }

        let name: String
        if let pw = getpwuid(uid) {
            name = String(cString: pw.pointee.pw_name)
        } else {
            name = String(uid)
        }

        userCache[uid] = name
        return name
    }

    private func fetchRusageData(pid: pid_t) -> (memory: Int64, userTime: UInt64, systemTime: UInt64) {
        var rusage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
            }
        }

        if result == 0 {
            return (
                memory: Int64(rusage.ri_phys_footprint),
                userTime: rusage.ri_user_time,
                systemTime: rusage.ri_system_time
            )
        }

        // Fallback to proc_taskinfo if rusage fails
        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize) == taskInfoSize {
            return (
                memory: Int64(taskInfo.pti_resident_size),
                userTime: taskInfo.pti_total_user,
                systemTime: taskInfo.pti_total_system
            )
        }

        return (memory: 0, userTime: 0, systemTime: 0)
    }

    private func fetchBasicProcessInfo(pid: pid_t) -> ProcessItem? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size

        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }

        // DEFENSIVE: Extract name from kp_proc.p_comm with guaranteed null termination
        // p_comm is MAXCOMLEN (16) bytes, may not be null-terminated if name is exactly 16 chars
        var pCommBytes = info.kp_proc.p_comm

        var name = withUnsafeBytes(of: &pCommBytes) { rawPtr -> String in
            let maxLen = 16 // MAXCOMLEN for p_comm
            var safeBuffer = [UInt8](repeating: 0, count: maxLen + 1)

            let bytesToCopy = min(rawPtr.count, maxLen)
            for i in 0..<bytesToCopy {
                safeBuffer[i] = rawPtr[i]
            }

            return safeBuffer.withUnsafeBufferPointer { bufPtr in
                bufPtr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: safeBuffer.count) {
                    String(cString: $0)
                }
            }
        }

        // DEFENSIVE: Clean control characters
        let cleanedName = name.trimmingCharacters(in: .controlCharacters.union(.whitespaces))
        name = cleanedName.isEmpty ? "Process \(pid)" : cleanedName

        // Check cache for full name (path-based name is more accurate)
        if let cachedName = nameCache[pid] {
            name = cachedName
        } else {
            nameCache[pid] = name
        }

        let user = fetchUsername(uid: info.kp_eproc.e_ucred.cr_uid)
        let parentPid = info.kp_eproc.e_ppid

        // Determine state from p_stat
        let state: ProcessState
        switch info.kp_proc.p_stat {
        case 5: state = .zombie
        case 4: state = .stopped
        case 1: state = .unknown
        default: state = .sleeping  // Can't determine CPU usage, assume sleeping
        }

        return ProcessItem(
            pid: pid,
            name: name,
            user: user,
            cpuUsage: 0,
            cpuUsageTotal: 0,
            memoryUsage: 0,
            threadCount: 0,
            state: state,
            icon: nil,
            parentPid: parentPid,
            startTime: nil
        )
    }

    private func determineProcessState(status: UInt32, cpuUsage: Double) -> ProcessState {
        // Status values: SIDL=1, SRUN=2, SSLEEP=3, SSTOP=4, SZOMB=5
        switch status {
        case 5: return .zombie
        case 4: return .stopped
        case 1: return .unknown
        default:
            // For runnable processes (stat == 2 or 3), use CPU usage to determine display state
            return cpuUsage > 1.0 ? .running : .sleeping
        }
    }

    private func calculateCPUUsage(pid: pid_t, userTime: UInt64, systemTime: UInt64) -> Double {
        let now = Date()
        let totalTime = userTime + systemTime

        defer {
            previousCPUTimes[pid] = (userTime, systemTime, now)
        }

        guard let previous = previousCPUTimes[pid] else {
            return 0
        }

        let timeDelta = now.timeIntervalSince(previous.timestamp)
        guard timeDelta > 0 else { return 0 }

        let previousTotal = previous.user + previous.system

        // Handle case where times might wrap or process restarted
        guard totalTime >= previousTotal else { return 0 }

        let cpuDelta = totalTime - previousTotal

        // Convert Mach absolute time to nanoseconds
        let nanoseconds = cpuDelta * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)

        // Convert nanoseconds to seconds
        let cpuSeconds = Double(nanoseconds) / 1_000_000_000

        // Calculate percentage: (CPU time / wall time) * 100
        let cpuUsage = (cpuSeconds / timeDelta) * 100

        return min(cpuUsage, 100 * Double(ProcessInfo.processInfo.processorCount))
    }

    private func fetchIcon(pid: pid_t) -> NSImage? {
        // Skip if we already know this PID has no icon
        if noIconPids.contains(pid) {
            return nil
        }

        let cacheKey = NSNumber(value: pid)
        if let cached = iconCache.object(forKey: cacheKey) {
            return cached
        }

        // Only fetch icons for regular apps (GUI apps) - skip background processes
        if let app = NSRunningApplication(processIdentifier: pid) {
            if app.activationPolicy == .regular, let icon = app.icon {
                iconCache.setObject(icon, forKey: cacheKey)
                return icon
            }
        }

        // Remember that this PID has no icon
        noIconPids.insert(pid)
        return nil
    }

    func clearCPUHistory() {
        previousCPUTimes.removeAll()
    }
}
