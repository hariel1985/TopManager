import Foundation
import Darwin

final class CPUMonitor {
    private var previousCpuInfo: [processor_cpu_load_info]?
    private var previousGlobalInfo: host_cpu_load_info?
    private var pCoreCount: Int = 0
    private var eCoreCount: Int = 0
    private var isAppleSiliconCPU: Bool = false

    init() {
        detectCPUArchitecture()
    }

    private func detectCPUArchitecture() {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        isAppleSiliconCPU = machine.hasPrefix("arm64")

        if isAppleSiliconCPU {
            detectPerfLevelCounts()
        }
    }

    private func detectPerfLevelCounts() {
        var pCores: Int32 = 0
        var eCores: Int32 = 0
        var size = MemoryLayout<Int32>.size

        if sysctlbyname("hw.perflevel1.logicalcpu", &pCores, &size, nil, 0) == 0,
           sysctlbyname("hw.perflevel0.logicalcpu", &eCores, &size, nil, 0) == 0 {
            self.pCoreCount = Int(pCores)
            self.eCoreCount = Int(eCores)
        }
    }

    func fetchCPUInfo() -> CPUInfo? {
        guard let perCoreUsages = fetchPerCoreUsages(),
              let globalUsage = fetchGlobalUsage() else {
            return nil
        }

        var pCoreUsages: [CoreUsage] = []
        var eCoreUsages: [CoreUsage] = []

        if isAppleSiliconCPU && pCoreCount > 0 && eCoreCount > 0 {
            for core in perCoreUsages {
                if core.id < pCoreCount {
                    pCoreUsages.append(CoreUsage(id: core.id, usage: core.usage, coreType: .performance))
                } else {
                    eCoreUsages.append(CoreUsage(id: core.id, usage: core.usage, coreType: .efficiency))
                }
            }
        }

        return CPUInfo(
            globalUsage: globalUsage.usage,
            userUsage: globalUsage.user,
            systemUsage: globalUsage.system,
            idleUsage: globalUsage.idle,
            coreUsages: perCoreUsages,
            pCoreUsages: pCoreUsages,
            eCoreUsages: eCoreUsages
        )
    }

    private func fetchPerCoreUsages() -> [CoreUsage]? {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return nil
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(Int(numCpuInfo) * MemoryLayout<integer_t>.size)
            )
        }

        var coreUsages: [CoreUsage] = []
        let cpuLoadInfo = cpuInfo.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(numCPUs)) { ptr in
            Array(UnsafeBufferPointer(start: ptr, count: Int(numCPUs)))
        }

        for (index, currentInfo) in cpuLoadInfo.enumerated() {
            var usage = 0.0

            if let previous = previousCpuInfo, index < previous.count {
                let prevInfo = previous[index]

                let userDelta = Int64(currentInfo.cpu_ticks.0) - Int64(prevInfo.cpu_ticks.0)
                let systemDelta = Int64(currentInfo.cpu_ticks.1) - Int64(prevInfo.cpu_ticks.1)
                let idleDelta = Int64(currentInfo.cpu_ticks.2) - Int64(prevInfo.cpu_ticks.2)
                let niceDelta = Int64(currentInfo.cpu_ticks.3) - Int64(prevInfo.cpu_ticks.3)

                let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
                if totalDelta > 0 {
                    usage = Double(userDelta + systemDelta) / Double(totalDelta) * 100
                }
            }

            let coreType: CoreUsage.CoreType
            if isAppleSiliconCPU && pCoreCount > 0 {
                coreType = index < pCoreCount ? .performance : .efficiency
            } else {
                coreType = .unknown
            }

            coreUsages.append(CoreUsage(id: index, usage: usage, coreType: coreType))
        }

        previousCpuInfo = cpuLoadInfo
        return coreUsages
    }

    private func fetchGlobalUsage() -> (usage: Double, user: Double, system: Double, idle: Double)? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var cpuLoadInfo = host_cpu_load_info_data_t()

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &size)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        var usage = 0.0
        var userPct = 0.0
        var systemPct = 0.0
        var idlePct = 0.0

        if let previous = previousGlobalInfo {
            let userDelta = Int64(cpuLoadInfo.cpu_ticks.0) - Int64(previous.cpu_ticks.0)
            let systemDelta = Int64(cpuLoadInfo.cpu_ticks.1) - Int64(previous.cpu_ticks.1)
            let idleDelta = Int64(cpuLoadInfo.cpu_ticks.2) - Int64(previous.cpu_ticks.2)
            let niceDelta = Int64(cpuLoadInfo.cpu_ticks.3) - Int64(previous.cpu_ticks.3)

            let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
            if totalDelta > 0 {
                userPct = Double(userDelta + niceDelta) / Double(totalDelta) * 100
                systemPct = Double(systemDelta) / Double(totalDelta) * 100
                idlePct = Double(idleDelta) / Double(totalDelta) * 100
                usage = userPct + systemPct
            }
        }

        previousGlobalInfo = cpuLoadInfo
        return (usage, userPct, systemPct, idlePct)
    }

    var isAppleSilicon: Bool {
        isAppleSiliconCPU
    }

    var performanceCoreCount: Int {
        pCoreCount
    }

    var efficiencyCoreCount: Int {
        eCoreCount
    }
}
