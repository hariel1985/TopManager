import Foundation
import IOKit
import Metal

final class GPUMonitor {
    private let isAppleSilicon: Bool
    private let chipName: String
    private let gpuCoreCount: Int?

    init() {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        isAppleSilicon = machine.hasPrefix("arm64")
        chipName = GPUMonitor.getChipName()
        gpuCoreCount = GPUMonitor.getGPUCoreCount()
    }

    private static func getGPUCoreCount() -> Int? {
        // Try to get GPU core count from Metal
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        // For Apple Silicon, we can infer from the chip name or use Metal properties
        // Metal doesn't directly expose core count, but we can check recommended working set size
        // as a proxy or use the chip name to look up known values

        // Try IOKit for more detailed info
        let matchingDict = IOServiceMatching("AGXAccelerator")
        var iterator: io_iterator_t = 0

        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }

            let service = IOIteratorNext(iterator)
            if service != 0 {
                defer { IOObjectRelease(service) }

                if let props = IORegistryEntryCreateCFProperty(
                    service,
                    "gpu-core-count" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? Int {
                    return props
                }
            }
        }

        // Fallback: infer from device name
        let name = device.name.lowercased()
        if name.contains("m3 max") { return 40 }
        if name.contains("m3 pro") { return 18 }
        if name.contains("m3") { return 10 }
        if name.contains("m2 ultra") { return 76 }
        if name.contains("m2 max") { return 38 }
        if name.contains("m2 pro") { return 19 }
        if name.contains("m2") { return 10 }
        if name.contains("m1 ultra") { return 64 }
        if name.contains("m1 max") { return 32 }
        if name.contains("m1 pro") { return 16 }
        if name.contains("m1") { return 8 }

        return nil
    }

    private static func getChipName() -> String {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)

        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)

        let brandString = String(cString: brand)

        // For Apple Silicon, this returns "Apple M1", "Apple M2", etc.
        if brandString.hasPrefix("Apple") {
            return brandString
        }

        // Fallback: try to get chip from IOKit
        return getAppleSiliconChipName() ?? "Apple GPU"
    }

    private static func getAppleSiliconChipName() -> String? {
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        if let modelData = IORegistryEntryCreateCFProperty(
            platformExpert,
            "model" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Data {
            let model = String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""

            // Map model identifiers to chip names
            if model.contains("Mac14") || model.contains("Mac15") {
                return "Apple M2/M3"
            } else if model.contains("Mac13") {
                return "Apple M2"
            } else if model.contains("Mac12") || model.contains("MacBookAir10") || model.contains("MacBookPro17") || model.contains("MacBookPro18") || model.contains("Macmini9") || model.contains("iMac21") {
                return "Apple M1"
            }
        }

        return nil
    }

    func fetchGPUInfo() -> GPUInfo? {
        if isAppleSilicon {
            return fetchAppleSiliconGPUInfo()
        } else {
            return fetchDiscreteGPUInfo()
        }
    }

    /// Walks an `io_iterator_t` and returns the first non-`nil` value `body`
    /// produces, releasing **every** object it pulled out of the iterator.
    ///
    /// The obvious `while` + `defer { release; next() }` shape leaks one
    /// `io_object_t` whenever the loop is left with `break`/`return`, because
    /// the deferred `IOIteratorNext` hands back an object nobody releases. At a
    /// GPU poll every few seconds that leaks tens of thousands of mach port
    /// rights per day.
    private static func firstMatch<T>(in iterator: io_iterator_t, _ body: (io_service_t) -> T?) -> T? {
        var result: T?
        while result == nil {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            result = body(service)
            IOObjectRelease(service)
        }
        return result
    }

    private func fetchAppleSiliconGPUInfo() -> GPUInfo? {
        // Apple Silicon uses unified memory - get memory pressure instead
        let totalMemory = ProcessInfo.processInfo.physicalMemory

        // Try to get GPU utilization from IOKit
        var utilizationPercent: Double? = nil
        var inUseSystemMemory: UInt64 = 0

        let matchingDict = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0

        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }

            _ = Self.firstMatch(in: iterator) { service -> Bool? in
                guard let props = IORegistryEntryCreateCFProperty(
                    service,
                    "PerformanceStatistics" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? [String: Any] else { return nil }

                // Try various keys for GPU memory on Apple Silicon
                if let inUse = props["In use system memory"] as? UInt64 {
                    inUseSystemMemory = inUse
                } else if let inUse = props["Alloc system memory"] as? UInt64 {
                    inUseSystemMemory = inUse
                } else if let inUse = props["inUseSystemMemory"] as? UInt64 {
                    inUseSystemMemory = inUse
                }

                // GPU utilization
                if let util = props["Device Utilization %"] as? Int {
                    utilizationPercent = Double(util)
                } else if let util = props["GPU Activity(%)"] as? Int {
                    utilizationPercent = Double(util)
                }

                return true
            }
        }

        // For Apple Silicon, show unified memory usage
        return GPUInfo(
            name: chipName + " GPU",
            vramUsed: inUseSystemMemory,
            vramTotal: inUseSystemMemory > 0 ? totalMemory : nil,
            utilizationPercent: utilizationPercent,
            isUnifiedMemory: true,
            coreCount: gpuCoreCount
        )
    }

    private func fetchDiscreteGPUInfo() -> GPUInfo? {
        let matchingDict = IOServiceMatching("IOAccelerator")

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        return Self.firstMatch(in: iterator) { service -> GPUInfo? in
            var name = "GPU"
            if let modelData = IORegistryEntryCreateCFProperty(
                service,
                "model" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? Data {
                name = String(data: modelData, encoding: .utf8)?
                    .trimmingCharacters(in: .controlCharacters) ?? "GPU"
            }

            if let props = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {

                let vramUsed = (props["vramUsedBytes"] as? UInt64)
                    ?? (props["VRAM,totalMB"] as? UInt64).map { $0 * 1024 * 1024 }
                    ?? (props["inUseVidMemoryBytes"] as? UInt64)
                    ?? 0

                let vramFree = props["vramFreeBytes"] as? UInt64
                let vramTotal: UInt64?

                if let free = vramFree {
                    vramTotal = vramUsed + free
                } else if let totalMB = props["VRAM,totalMB"] as? UInt64 {
                    vramTotal = totalMB * 1024 * 1024
                } else {
                    vramTotal = nil
                }

                let utilization = props["Device Utilization %"] as? Double
                    ?? props["GPU Core Utilization"] as? Double

                return GPUInfo(
                    name: name,
                    vramUsed: vramUsed,
                    vramTotal: vramTotal,
                    utilizationPercent: utilization,
                    isUnifiedMemory: false
                )
            }

            return nil
        }
    }
}
