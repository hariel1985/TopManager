import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        TabView {
            ProcessView()
                .tabItem {
                    Label("Processes", systemImage: "list.bullet.rectangle")
                }

            AppsView()
                .tabItem {
                    Label("Apps", systemImage: "square.grid.2x2")
                }

            PerformanceView()
                .tabItem {
                    Label("Performance", systemImage: "chart.line.uptrend.xyaxis")
                }

            PowerStorageView()
                .tabItem {
                    Label("Power & Storage", systemImage: "battery.100.bolt")
                }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    ContentView()
        .environmentObject(SystemMonitor.shared)
}
