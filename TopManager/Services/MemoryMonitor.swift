import Foundation
import Darwin

final class MemoryMonitor {
    private let pageSize: UInt64

    init() {
        var pageSizeValue: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSizeValue)
        pageSize = UInt64(pageSizeValue)
    }

    func fetchMemoryInfo() -> MemoryInfo? {
        guard let vmStats = fetchVMStatistics() else { return nil }

        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let freeMemory = vmStats.freePages * pageSize
        let activeMemory = vmStats.activePages * pageSize
        let inactiveMemory = vmStats.inactivePages * pageSize
        let wiredMemory = vmStats.wiredPages * pageSize
        let compressedMemory = vmStats.compressedPages * pageSize
        let cachedMemory = vmStats.cachedPages * pageSize

        let usedMemory = activeMemory + wiredMemory + compressedMemory

        let swapInfo = fetchSwapInfo()
        let memoryPressure = fetchMemoryPressure()

        return MemoryInfo(
            totalMemory: totalMemory,
            usedMemory: usedMemory,
            freeMemory: freeMemory,
            activeMemory: activeMemory,
            inactiveMemory: inactiveMemory,
            wiredMemory: wiredMemory,
            compressedMemory: compressedMemory,
            cachedMemory: cachedMemory,
            swapUsed: swapInfo.used,
            swapTotal: swapInfo.total,
            memoryPressure: memoryPressure
        )
    }

    private func fetchVMStatistics() -> (
        freePages: UInt64,
        activePages: UInt64,
        inactivePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        cachedPages: UInt64
    )? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        return (
            freePages: UInt64(stats.free_count),
            activePages: UInt64(stats.active_count),
            inactivePages: UInt64(stats.inactive_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            cachedPages: UInt64(stats.external_page_count)
        )
    }

    private func fetchSwapInfo() -> (used: UInt64, total: UInt64) {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size

        if sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0) == 0 {
            return (UInt64(swapUsage.xsu_used), UInt64(swapUsage.xsu_total))
        }
        return (0, 0)
    }

    private func fetchMemoryPressure() -> MemoryPressure {
        var pressure: Int32 = 0
        var size = MemoryLayout<Int32>.size

        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0) == 0 {
            switch pressure {
            case 1: return .nominal
            case 2: return .warning
            case 4: return .critical
            default: return .nominal
            }
        }
        return .unknown
    }
}
