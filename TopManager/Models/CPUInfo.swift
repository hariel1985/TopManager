import Foundation

struct CPUInfo {
    let globalUsage: Double
    let userUsage: Double
    let systemUsage: Double
    let idleUsage: Double
    let coreUsages: [CoreUsage]
    let pCoreUsages: [CoreUsage]
    let eCoreUsages: [CoreUsage]
    let timestamp: Date

    init(
        globalUsage: Double,
        userUsage: Double,
        systemUsage: Double,
        idleUsage: Double,
        coreUsages: [CoreUsage],
        pCoreUsages: [CoreUsage] = [],
        eCoreUsages: [CoreUsage] = [],
        timestamp: Date = Date()
    ) {
        self.globalUsage = globalUsage
        self.userUsage = userUsage
        self.systemUsage = systemUsage
        self.idleUsage = idleUsage
        self.coreUsages = coreUsages
        self.pCoreUsages = pCoreUsages
        self.eCoreUsages = eCoreUsages
        self.timestamp = timestamp
    }
}

struct CoreUsage: Identifiable {
    let id: Int
    let usage: Double
    let coreType: CoreType

    enum CoreType: String {
        case performance = "P"
        case efficiency = "E"
        case unknown = ""
    }

    init(id: Int, usage: Double, coreType: CoreType = .unknown) {
        self.id = id
        self.usage = usage
        self.coreType = coreType
    }
}

struct CPUHistoryPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let usage: Double
    let userUsage: Double
    let systemUsage: Double
}

struct CoreHistoryPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let usage: Double
}
