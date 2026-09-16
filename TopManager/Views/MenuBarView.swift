import SwiftUI

/// The compact menu-bar title. Renders whichever metric the user picked.
/// Reads `MenuBarStatus`, not `SystemMonitor`, so it keeps updating while the
/// monitor's view publishing is paused.
struct MenuBarLabel: View {
    @ObservedObject var status: MenuBarStatus
    @ObservedObject var settings: AppSettings
    @ObservedObject var alerts: AlertCenter

    var body: some View {
        switch settings.menuBarMetric {
        case .cpu:
            textOrIcon(status.cpuText, icon: "cpu")
        case .memory:
            textOrIcon(status.memoryText, icon: "memorychip")
        case .health:
            Text("♥ \(alerts.healthScore)").monospacedDigit()
        case .download:
            textOrIcon(status.downloadText, icon: "arrow.down")
        }
    }

    @ViewBuilder private func textOrIcon(_ text: String?, icon: String) -> some View {
        if let text { Text(text).monospacedDigit() } else { Image(systemName: icon) }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var alertCenter: AlertCenter

    private var topCPU: [ProcessItem] {
        monitor.processes.sorted { $0.cpuUsage > $1.cpuUsage }.prefix(3).map { $0 }
    }

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

            if !topCPU.isEmpty {
                Divider()
                Text("Top CPU Consumers")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(topCPU) { process in
                    HStack(spacing: 6) {
                        Text(process.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(String(format: "%.0f%%", process.cpuUsage))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                        Button {
                            _ = monitor.terminateProcess(process.pid, expectedStartTime: process.startTime)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Quit \(process.name)")
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
