import SwiftUI

/// The main window's tab shell.
///
/// IMPORTANT: this view must stay free of any observable dependency
/// (`@EnvironmentObject`, `@StateObject`, `@State`, …). On macOS, every
/// re-evaluation of a body containing `.tabItem` permanently retains the
/// wrapped `AnyView(Label(…))` inside the AppKit tab bridge, so a body that
/// re-runs on the monitor's refresh cadence leaks ~6 KB per tick (≈440 MB over
/// three days). With no stored properties SwiftUI evaluates this body exactly
/// once. The tab *contents* observe `SystemMonitor` themselves.
struct ContentView: View {
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
