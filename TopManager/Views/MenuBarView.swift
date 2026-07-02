import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var alertCenter: AlertCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "heart.text.square")
                    .frame(width: 16)
                    .foregroundColor(healthColor)
                Text("Health:")
                Spacer()
                Text("\(alertCenter.healthScore)/100")
                    .monospacedDigit()
                    .foregroundColor(healthColor)
                if alertCenter.activeAlertCount > 0 {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.orange)
                }
            }
            Divider()

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

            if let power = monitor.powerInfo, power.hasBattery {
                HStack {
                    Image(systemName: power.isCharging ? "battery.100.bolt" : "battery.100")
                        .frame(width: 16)
                    Text("Battery:")
                    Spacer()
                    Text("\(power.currentCharge)%")
                        .monospacedDigit()
                    if let toEmpty = power.timeToEmpty {
                        Text("(\(BatteryMath.formatMinutes(toEmpty)))")
                            .foregroundColor(.secondary)
                    }
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
        .frame(width: 240)
    }

    private var healthColor: Color {
        switch alertCenter.healthScore {
        case 85...: return .green
        case 70..<85: return .mint
        case 50..<70: return .orange
        default: return .red
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(SystemMonitor.shared)
}
