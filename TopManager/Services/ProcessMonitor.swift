import Foundation
import Darwin
import AppKit

final class ProcessMonitor {
    private var previousCPUTimes: [pid_t: (user: UInt64, system: UInt64, timestamp: Date)] = [:]
    private var previousDiskIO: [pid_t: (read: UInt64, write: UInt64, idle: UInt64, timestamp: Date)] = [:]
    private var lastKnownCPU: [pid_t: Double] = [:]  // Cache last known CPU usage
    private var lastDetailed: [pid_t: DetailedSample] = [:]  // Reused on lightweight refreshes
    private let iconCache = NSCache<NSNumber, NSImage>()
    private var noIconPids: Set<pid_t> = []  // Cache for PIDs with no icon
    private var nameCache: [pid_t: String] = [:]
    private var pathCache: [pid_t: String] = [:]     // Full executable path
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
            pathCache.removeValue(forKey: pid)
            iconCache.removeObject(forKey: NSNumber(value: pid))
            previousCPUTimes.removeValue(forKey: pid)
            previousDiskIO.removeValue(forKey: pid)
            noIconPids.remove(pid)
            lastKnownCPU.removeValue(forKey: pid)
            lastDetailed.removeValue(forKey: pid)
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

        let detail: DetailedSample

        if needsDetailedInfo {
            var taskInfo = proc_taskinfo()
            let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let taskResult = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
            let hasTaskInfo = taskResult == taskInfoSize

            if hasTaskInfo {
                let rusageData = fetchRusageData(pid: pid)
                let cpu = calculateCPUUsage(
                    pid: pid,
                    userTime: rusageData.userTime,
                    systemTime: rusageData.systemTime
                )
                let extra = computeExtraRates(
                    pid: pid,
                    diskRead: rusageData.diskRead,
                    diskWrite: rusageData.diskWrite,
                    idleWakeups: rusageData.idleWakeups
                )
                detail = DetailedSample(
                    memory: rusageData.memory,
                    resident: rusageData.resident,
                    compressed: fetchCompressedMemory(pid: pid) ?? 0,
                    threads: taskInfo.pti_threadnum,
                    cpu: cpu,
                    diskReadRate: extra.readRate,
                    diskWriteRate: extra.writeRate,
                    diskReadBytes: rusageData.diskRead,
                    diskWriteBytes: rusageData.diskWrite,
                    energy: EnergyModel.impact(cpuPercent: cpu, idleWakeupsPerSec: extra.idleWakeupsPerSec)
                )
                lastDetailed[pid] = detail
            } else {
                detail = .zero
            }
        } else {
            // Lightweight refresh - reuse last known values. This used to emit
            // zeros, so ~90% of rows showed "Zero KB" memory (and 0 threads/CPU)
            // on two of every three updates.
            detail = lastDetailed[pid] ?? .zero
        }

        let memoryUsage = detail.memory
        let threadCount = detail.threads
        let cpuUsage = detail.cpu

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
            startTime: startTime,
            diskReadRate: detail.diskReadRate,
            diskWriteRate: detail.diskWriteRate,
            diskReadBytes: detail.diskReadBytes,
            diskWriteBytes: detail.diskWriteBytes,
            energyImpact: detail.energy,
            executablePath: pathCache[pid],
            residentMemory: detail.resident,
            compressedMemory: detail.compressed
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
                pathCache[pid] = path
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

    /// The expensive per-process readings (rusage + task info + derived rates).
    private struct DetailedSample {
        var memory: Int64
        var resident: Int64
        var compressed: Int64
        var threads: Int32
        var cpu: Double
        var diskReadRate: Double
        var diskWriteRate: Double
        var diskReadBytes: UInt64
        var diskWriteBytes: UInt64
        var energy: Double

        static let zero = DetailedSample(memory: 0, resident: 0, compressed: 0, threads: 0, cpu: 0,
                                         diskReadRate: 0, diskWriteRate: 0,
                                         diskReadBytes: 0, diskWriteBytes: 0, energy: 0)
    }

    private struct RusageData {
        var memory: Int64 = 0
        var resident: Int64 = 0
        var userTime: UInt64 = 0
        var systemTime: UInt64 = 0
        var diskRead: UInt64 = 0
        var diskWrite: UInt64 = 0
        var idleWakeups: UInt64 = 0
    }

    private func fetchRusageData(pid: pid_t) -> RusageData {
        var rusage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
            }
        }

        if result == 0 {
            return RusageData(
                memory: Int64(rusage.ri_phys_footprint),
                resident: Int64(rusage.ri_resident_size),
                userTime: rusage.ri_user_time,
                systemTime: rusage.ri_system_time,
                diskRead: rusage.ri_diskio_bytesread,
                diskWrite: rusage.ri_diskio_byteswritten,
                idleWakeups: rusage.ri_pkg_idle_wkups
            )
        }

        // Fallback to proc_taskinfo if rusage fails (no disk/wakeup data available)
        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize) == taskInfoSize {
            return RusageData(
                memory: Int64(taskInfo.pti_resident_size),
                resident: Int64(taskInfo.pti_resident_size),
                userTime: taskInfo.pti_total_user,
                systemTime: taskInfo.pti_total_system
            )
        }

        return RusageData()
    }

    /// Computes per-second disk read/write and idle-wakeup rates from cumulative
    /// counters, using the previous snapshot. Mirrors the CPU delta approach.
    private func computeExtraRates(pid: pid_t, diskRead: UInt64, diskWrite: UInt64, idleWakeups: UInt64)
        -> (readRate: Double, writeRate: Double, idleWakeupsPerSec: Double) {
        let now = Date()
        defer { previousDiskIO[pid] = (diskRead, diskWrite, idleWakeups, now) }

        guard let prev = previousDiskIO[pid] else { return (0, 0, 0) }
        let dt = now.timeIntervalSince(prev.timestamp)
        guard dt > 0 else { return (0, 0, 0) }

        let readRate = diskRead >= prev.read ? Double(diskRead - prev.read) / dt : 0
        let writeRate = diskWrite >= prev.write ? Double(diskWrite - prev.write) / dt : 0
        let idleRate = idleWakeups >= prev.idle ? Double(idleWakeups - prev.idle) / dt : 0
        return (readRate, writeRate, idleRate)
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

// MARK: - On-demand deep inspection (called only when the inspector is open)

/// Pure parser for a KERN_PROCARGS2 buffer, split out so it is unit-testable
/// without a live process. Layout: [Int32 argc][exec_path\0][\0 padding][argv…][envp…]
enum ProcArgs {
    static func parse(_ bytes: [UInt8]) -> (path: String, args: [String])? {
        guard bytes.count > 4 else { return nil }
        // argc: first 4 bytes, host little-endian (arm64/x86_64)
        let argc = Int(bytes[0]) | (Int(bytes[1]) << 8) | (Int(bytes[2]) << 16) | (Int(bytes[3]) << 24)
        guard argc >= 0 else { return nil }

        var i = 4
        let pathStart = i
        while i < bytes.count && bytes[i] != 0 { i += 1 }
        let path = String(decoding: bytes[pathStart..<i], as: UTF8.self)

        // Skip the NUL padding between exec_path and argv[0]
        while i < bytes.count && bytes[i] == 0 { i += 1 }

        var args: [String] = []
        var consumed = 0
        while consumed < argc && i < bytes.count {
            let start = i
            while i < bytes.count && bytes[i] != 0 { i += 1 }
            args.append(String(decoding: bytes[start..<i], as: UTF8.self))
            i += 1 // skip the NUL terminator
            consumed += 1
        }
        return (path, args)
    }
}

/// Fetches the launch arguments for a process (works for the current user's
/// processes without elevated privileges; returns [] when denied/unavailable).
func fetchProcessArguments(pid: pid_t) -> [String] {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }

    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
    // sysctl may shrink `size`; only parse what was actually written.
    return ProcArgs.parse(Array(buffer.prefix(size)))?.args ?? []
}

/// Memory of a process currently held by the compressor, at its original
/// (uncompressed) size. macOS does not track swap per process: when compressor
/// segments are paged out to disk they stay counted here, so this is the
/// closest per-process "swapped" figure that exists — Activity Monitor's
/// "Compressed Memory" and `top`'s CMPRS show the same value.
///
/// Needs only a task *name* port, which the kernel hands out for processes of
/// the same user; returns `nil` for other users' and system processes.
func fetchCompressedMemory(pid: pid_t) -> Int64? {
    var port: mach_port_name_t = 0
    guard task_name_for_pid(mach_task_self_, pid, &port) == KERN_SUCCESS else { return nil }
    defer { mach_port_deallocate(mach_task_self_, port) }

    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(port, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int64(info.compressed) : nil
}

/// Counts open file descriptors for a process (files, sockets, pipes, …).
func fetchOpenFileCount(pid: pid_t) -> Int? {
    let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
    guard bufferSize > 0 else { return nil }
    return Int(bufferSize) / MemoryLayout<proc_fdinfo>.stride
}
