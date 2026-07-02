import SwiftUI
import UserNotifications

/// Flushes persisted metrics history when the app is quit, and lets alert banners
/// appear even while TopManager is the foreground app (macOS suppresses an app's
/// own notifications in the foreground unless the delegate opts in).
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
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
                .onAppear {
                    monitor.startMonitoring()
                    settings.applyAll()
                    AlertCenter.shared.requestNotificationAuthorization()
                }
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
            MenuBarLabel(monitor: monitor, settings: settings, alerts: AlertCenter.shared)
        }
        .menuBarExtraStyle(.window)
    }
}
