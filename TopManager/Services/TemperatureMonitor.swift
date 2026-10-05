import Foundation
import IOKit

// IOHIDEventSystemClient is the interface macOS itself uses for its thermal
// sensors. It is not in the public SDK headers, but the symbols are exported by
// IOKit and need neither root nor an entitlement (the app is not sandboxed).
@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32,
                                         _ timestamp: Int64) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double

/// Reads the Apple Silicon temperature sensors. On an Intel Mac there are no
/// such sensors (those sit behind the SMC) and it reports nil.
final class TemperatureMonitor {
    private static let temperatureEvent: Int64 = 15                 // kIOHIDEventTypeTemperature
    private static let temperatureField = Int32(temperatureEvent << 16)  // IOHIDEventFieldBase(type)

    private let client: AnyObject?
    private var cachedSensors: [(name: String, service: AnyObject)]?

    init() {
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue()
        if let client {
            // Usage page 0xff00 (Apple vendor), usage 5: temperature sensors.
            _ = IOHIDEventSystemClientSetMatching(
                client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        }
    }

    func readSensors() -> [TemperatureReading] {
        sensors().compactMap { sensor in
            guard let event = IOHIDServiceClientCopyEvent(sensor.service, Self.temperatureEvent, 0, 0)?
                .takeRetainedValue() else { return nil }
            return TemperatureReading(name: sensor.name,
                                      celsius: IOHIDEventGetFloatValue(event, Self.temperatureField))
        }
    }

    func fetchThermalInfo() -> ThermalInfo? {
        ThermalMath.summarize(readSensors())
    }

    /// The sensor list doesn't change while the system runs, so it is built once.
    private func sensors() -> [(name: String, service: AnyObject)] {
        if let cachedSensors { return cachedSensors }
        guard let client,
              let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject]
        else { return [] }
        let found = services.map { service in
            let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as? String
            return (name: name ?? "", service: service)
        }
        cachedSensors = found
        return found
    }
}
