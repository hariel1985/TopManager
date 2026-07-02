import SwiftUI

/// Flushes persisted metrics history when the app is quit so history isn't lost
/// between the throttled background saves.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MetricsStore.shared.flush()
    }
}

@main
struct TopManagerApp: App {
    @StateObject private var monitor = SystemMonitor.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(AlertCenter.shared)
                .onAppear {
                    monitor.startMonitoring()
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

        // Menu Bar Extra showing CPU %
        MenuBarExtra {
            MenuBarView()
                .environmentObject(monitor)
                .environmentObject(AlertCenter.shared)
        } label: {
            if let cpu = monitor.cpuInfo {
                Text(String(format: "%.0f%%", cpu.globalUsage))
                    .monospacedDigit()
            } else {
                Image(systemName: "cpu")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
