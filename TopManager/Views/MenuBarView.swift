import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cpu = monitor.cpuInfo {
                HStack {
                    Image(systemName: "cpu")
                        .frame(width: 16)
                    Text("CPU:")
                    Spacer()
                    Text(String(format: "%.1f%%", cpu.globalUsage))
                        .monospacedDigit()
                }
            }

            if let mem = monitor.memoryInfo {
                HStack {
                    Image(systemName: "memorychip")
                        .frame(width: 16)
                    Text("Memory:")
                    Spacer()
                    Text(String(format: "%.1f%%", mem.usagePercentage))
                        .monospacedDigit()
                }
            }

            if let net = monitor.networkInfo {
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .frame(width: 16)
                    Text("Download:")
                    Spacer()
                    Text(formatBytesPerSecond(net.totalDownloadRate))
                        .monospacedDigit()
                }

                HStack {
                    Image(systemName: "arrow.up.circle")
                        .frame(width: 16)
                    Text("Upload:")
                    Spacer()
                    Text(formatBytesPerSecond(net.totalUploadRate))
                        .monospacedDigit()
                }
            }

            if let gpu = monitor.gpuInfo {
                HStack {
                    Image(systemName: "gpu")
                        .frame(width: 16)
                    Text("GPU VRAM:")
                    Spacer()
                    Text(formatBytes(gpu.vramUsed))
                        .monospacedDigit()
                }
            }

            Divider()

            Button("Open TopManager") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 220)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(SystemMonitor.shared)
}
