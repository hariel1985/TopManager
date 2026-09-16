import SwiftUI
import UserNotifications

/// Flushes persisted metrics history when the app is quit, and lets alert banners
/// appear even while TopManager is the foreground app (macOS suppresses an app's
/// own notifications in the foreground unless the delegate opts in).
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        // Start here rather than in the main window's onAppear: the app can launch
        // with no window at all (state restoration after the window was closed),
        // and the menu bar, alerts and history must run regardless.
        Task { @MainActor in
            SystemMonitor.shared.startMonitoring()
            AppSettings.shared.applyAll()
            AlertCenter.shared.requestNotificationAuthorization()
            WindowVisibility.shared.start { SystemMonitor.shared.setUIVisible($0) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func applicationWillTerminate(_ notification: Notification) {
        MetricsStore.shared.flush()
    }
}

@main
struct TopManagerApp: App {
    @StateObject private var monitor = SystemMonitor.shared
    @StateObject private var settings = AppSettings.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(AlertCenter.shared)
                .environmentObject(settings)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                MetricsStore.shared.flush()
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }

        // Menu Bar Extra with configurable metric
        MenuBarExtra {
            MenuBarView()
                .environmentObject(monitor)
                .environmentObject(AlertCenter.shared)
                .environmentObject(settings)
        } label: {
            MenuBarLabel(status: MenuBarStatus.shared, settings: settings, alerts: AlertCenter.shared)
        }
        .menuBarExtraStyle(.window)
    }
}
