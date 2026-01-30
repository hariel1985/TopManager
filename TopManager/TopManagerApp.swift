import SwiftUI

@main
struct TopManagerApp: App {
    @StateObject private var monitor = SystemMonitor.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .onAppear {
                    monitor.startMonitoring()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Menu Bar Extra showing CPU %
        MenuBarExtra {
            MenuBarView()
                .environmentObject(monitor)
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
