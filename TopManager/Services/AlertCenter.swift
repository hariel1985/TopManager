import Foundation
import Combine
import UserNotifications

/// The proactive brain: each refresh it computes the system health score and
/// evaluates alert conditions, firing a native notification + inbox entry on the
/// transition into each condition (never duplicating a still-active alert).
@MainActor
final class AlertCenter: ObservableObject {
    static let shared = AlertCenter()

    @Published var healthScore: Int = 100
    @Published var diagnosis: [String] = []
    @Published var alerts: [SystemAlert] = []                // inbox, newest first
    @Published private(set) var activeKinds: Set<AlertKind> = []

    @Published var thresholds = AlertThresholds()
    @Published var notificationsEnabled = true

    private let inboxLimit = 50
    private var cpuCount = 0
    private var procCount = 0
    private var notificationsAuthorized = false

    private init() {}

    var activeAlertCount: Int { activeKinds.count }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.notificationsAuthorized = granted }
        }
    }

    func evaluate(cpuUsage: Double,
                  memory: MemoryInfo?,
                  disk: DiskInfo?,
                  thermal: ThermalLevel,
                  topProcess: ProcessItem?,
                  power: PowerInfo?) {
        let diskFraction = disk?.volumes.map { $0.usagePercentage / 100 }.max() ?? 0

        // Health score + diagnosis
        let input = HealthInput(
            cpuUsage: cpuUsage,
            memoryPressure: memory?.memoryPressure ?? .unknown,
            swapUsedBytes: memory?.swapUsed ?? 0,
            thermal: thermal,
            diskUsedFraction: diskFraction
        )
        healthScore = HealthModel.score(input)
        diagnosis = HealthModel.diagnosis(input)

        // CPU (sustained)
        let cpuEval = AlertEvaluator.sustained(breached: cpuUsage >= thresholds.cpuPercent,
                                               previousCount: cpuCount,
                                               requiredCycles: thresholds.cpuSustainedCycles)
        cpuCount = cpuEval.count
        setActive(.cpuHigh, active: cpuEval.firing,
                  title: "High CPU usage",
                  message: String(format: "CPU has stayed above %.0f%% (now %.0f%%).", thresholds.cpuPercent, cpuUsage),
                  severity: .warning)

        // Memory pressure
        let memCritical = thresholds.memoryPressureCritical && memory?.memoryPressure == .critical
        setActive(.memoryPressure, active: memCritical,
                  title: "Critical memory pressure",
                  message: "The system is very low on memory. Consider closing apps.",
                  severity: .critical)

        // Disk
        let diskFull = diskFraction >= thresholds.diskUsedFraction
        setActive(.diskFull, active: diskFull,
                  title: "Disk almost full",
                  message: String(format: "A volume is %.0f%% full.", diskFraction * 100),
                  severity: .warning)

        // Thermal
        let thermalBad = thresholds.thermalSerious && (thermal == .serious || thermal == .critical)
        setActive(.thermal, active: thermalBad,
                  title: "System is running hot",
                  message: "Thermal state is elevated; performance may be throttled.",
                  severity: thermal == .critical ? .critical : .warning)

        // Runaway process (sustained)
        let runaway = (topProcess?.cpuUsage ?? 0) >= thresholds.processCpuPercent
        let procEval = AlertEvaluator.sustained(breached: runaway,
                                                previousCount: procCount,
                                                requiredCycles: thresholds.processSustainedCycles)
        procCount = procEval.count
        setActive(.runawayProcess, active: procEval.firing,
                  title: "Runaway process",
                  message: topProcess.map { "\($0.name) (PID \($0.pid)) is using \(Int($0.cpuUsage))% CPU." } ?? "",
                  severity: .warning)

        // Low battery
        let lowBattery = (power?.hasBattery ?? false)
            && !(power?.isPluggedIn ?? true)
            && (power?.currentCharge ?? 100) <= thresholds.lowBatteryPercent
        setActive(.lowBattery, active: lowBattery,
                  title: "Low battery",
                  message: "Battery is at \(power?.currentCharge ?? 0)% and not charging.",
                  severity: .warning)
    }

    private func setActive(_ kind: AlertKind, active: Bool, title: String, message: String, severity: AlertSeverity) {
        if active {
            guard !activeKinds.contains(kind) else { return }   // de-dup: already firing
            activeKinds.insert(kind)
            let alert = SystemAlert(kind: kind, title: title, message: message, severity: severity, timestamp: Date())
            alerts.insert(alert, at: 0)
            if alerts.count > inboxLimit { alerts.removeLast(alerts.count - inboxLimit) }
            postNotification(alert)
        } else {
            activeKinds.remove(kind)
        }
    }

    private func postNotification(_ alert: SystemAlert) {
        guard notificationsEnabled, notificationsAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.sound = alert.severity == .critical ? .defaultCritical : .default
        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func clearInbox() {
        alerts.removeAll()
    }
}
