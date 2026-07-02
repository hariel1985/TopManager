import Foundation
import ServiceManagement

/// What the menu-bar title shows at a glance.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU %"
    case memory = "Memory %"
    case health = "Health"
    case download = "Download"
    var id: String { rawValue }
}

/// Wraps the macOS login-item API (SMAppService, macOS 13+).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("TopManager: login item toggle failed: \(error.localizedDescription)")
        }
    }
}

/// Persisted user preferences. Changes are written to `UserDefaults` and pushed
/// into the running services (monitor cadence, alert thresholds, notifications).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    @Published var refreshInterval: Double {
        didSet {
            d.set(refreshInterval, forKey: Keys.refreshInterval)
            SystemMonitor.shared.updateRefreshInterval(refreshInterval)
        }
    }
    @Published var menuBarMetric: MenuBarMetric {
        didSet { d.set(menuBarMetric.rawValue, forKey: Keys.menuBarMetric) }
    }
    @Published var notificationsEnabled: Bool {
        didSet {
            d.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
            AlertCenter.shared.notificationsEnabled = notificationsEnabled
        }
    }
    @Published var cpuAlertThreshold: Double {
        didSet {
            d.set(cpuAlertThreshold, forKey: Keys.cpuAlertThreshold)
            AlertCenter.shared.thresholds.cpuPercent = cpuAlertThreshold
        }
    }
    @Published var diskAlertPercent: Double {
        didSet {
            d.set(diskAlertPercent, forKey: Keys.diskAlertPercent)
            AlertCenter.shared.thresholds.diskUsedFraction = diskAlertPercent / 100
        }
    }
    @Published var lowBatteryPercent: Int {
        didSet {
            d.set(lowBatteryPercent, forKey: Keys.lowBatteryPercent)
            AlertCenter.shared.thresholds.lowBatteryPercent = lowBatteryPercent
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { LoginItem.setEnabled(launchAtLogin) }
    }

    private init() {
        refreshInterval = AppSettings.clampInterval(d.object(forKey: Keys.refreshInterval) as? Double ?? 3.0)
        menuBarMetric = MenuBarMetric(rawValue: d.string(forKey: Keys.menuBarMetric) ?? "") ?? .cpu
        notificationsEnabled = d.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        cpuAlertThreshold = d.object(forKey: Keys.cpuAlertThreshold) as? Double ?? 90
        diskAlertPercent = d.object(forKey: Keys.diskAlertPercent) as? Double ?? 95
        lowBatteryPercent = d.object(forKey: Keys.lowBatteryPercent) as? Int ?? 15
        launchAtLogin = LoginItem.isEnabled
    }

    /// Push all persisted values into the live services (call once on launch).
    func applyAll() {
        SystemMonitor.shared.updateRefreshInterval(refreshInterval)
        AlertCenter.shared.notificationsEnabled = notificationsEnabled
        AlertCenter.shared.thresholds.cpuPercent = cpuAlertThreshold
        AlertCenter.shared.thresholds.diskUsedFraction = diskAlertPercent / 100
        AlertCenter.shared.thresholds.lowBatteryPercent = lowBatteryPercent
    }

    /// Refresh cadence must stay in a sane range (1–30s).
    nonisolated static func clampInterval(_ value: Double) -> Double {
        min(30, max(1, value))
    }

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let menuBarMetric = "menuBarMetric"
        static let notificationsEnabled = "notificationsEnabled"
        static let cpuAlertThreshold = "cpuAlertThreshold"
        static let diskAlertPercent = "diskAlertPercent"
        static let lowBatteryPercent = "lowBatteryPercent"
    }
}
