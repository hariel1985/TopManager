import SwiftUI

struct PowerStorageView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // System Status and GPU side by side
                HStack(alignment: .top, spacing: 20) {
                    // System Status (left column)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("System Status", systemImage: "thermometer.medium")
                                .font(.headline)

                            HStack {
                                Text("macOS:")
                                Spacer()
                                Text(ProcessInfo.processInfo.operatingSystemVersionString)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Uptime:")
                                Spacer()
                                Text(formatUptime(ProcessInfo.processInfo.systemUptime))
                                    .monospacedDigit()
                            }

                            HStack {
                                Text("Thermal State:")
                                Spacer()
                                ThermalStateView(state: monitor.thermalState)
                            }

                            if let cpu = monitor.cpuInfo {
                                HStack {
                                    Text("CPU Usage:")
                                    Spacer()
                                    Text(String(format: "%.1f%%", cpu.globalUsage))
                                        .monospacedDigit()
                                }

                                HStack {
                                    Text("CPU Cores:")
                                    Spacer()
                                    Text("\(cpu.coreUsages.count)")
                                        .monospacedDigit()
                                }
                            }

                            if let mem = monitor.memoryInfo {
                                HStack {
                                    Text("Memory:")
                                    Spacer()
                                    Text("\(formatBytes(mem.usedMemory)) / \(formatBytes(mem.totalMemory))")
                                        .monospacedDigit()
                                }
                            }

                            if monitor.isAppleSilicon {
                                HStack {
                                    Text("Architecture:")
                                    Spacer()
                                    Text("Apple Silicon")
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // GPU Info (right column)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            if let gpu = monitor.gpuInfo {
                                HStack {
                                    Label("GPU", systemImage: "cpu.fill")
                                        .font(.headline)
                                    Spacer()
                                }

                                HStack {
                                    Text("Name:")
                                    Spacer()
                                    Text(gpu.name)
                                        .foregroundColor(.secondary)
                                }

                                if let cores = gpu.coreCount {
                                    HStack {
                                        Text("GPU Cores:")
                                        Spacer()
                                        Text("\(cores)")
                                            .monospacedDigit()
                                    }
                                }

                                HStack {
                                    Text("VRAM Used:")
                                    Spacer()
                                    Text(formatBytes(gpu.vramUsed))
                                        .monospacedDigit()
                                }

                                if let total = gpu.vramTotal {
                                    HStack {
                                        Text("VRAM Total:")
                                        Spacer()
                                        Text(formatBytes(total))
                                            .monospacedDigit()
                                    }

                                    ProgressView(value: Double(gpu.vramUsed), total: Double(total))
                                        .tint(.purple)
                                }

                                if let utilization = gpu.utilizationPercent {
                                    HStack {
                                        Text("Utilization:")
                                        Spacer()
                                        Text(String(format: "%.1f%%", utilization))
                                            .monospacedDigit()
                                    }
                                }
                            } else {
                                Label("GPU", systemImage: "cpu.fill")
                                    .font(.headline)
                                Text("Loading GPU info...")
                                    .foregroundColor(.secondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Storage
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Storage", systemImage: "internaldrive")
                            .font(.headline)

                        if let diskInfo = monitor.diskInfo {
                            ForEach(diskInfo.volumes) { volume in
                                DiskUsageView(volume: volume)
                            }
                        } else {
                            Text("Loading storage information...")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Network Interfaces
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Network Interfaces", systemImage: "network")
                            .font(.headline)

                        if let networkInfo = monitor.networkInfo {
                            ForEach(networkInfo.interfaces.filter { $0.isActive }) { iface in
                                NetworkInterfaceRow(interface: iface)
                            }

                            if networkInfo.interfaces.filter({ $0.isActive }).isEmpty {
                                Text("No active interfaces")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding()
        }
    }
}

struct ThermalStateView: View {
    let state: ProcessInfo.ThermalState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: stateIcon)
                .foregroundColor(stateColor)
            Text(stateText)
                .foregroundColor(stateColor)
        }
    }

    private var stateIcon: String {
        switch state {
        case .nominal: return "checkmark.circle.fill"
        case .fair: return "exclamationmark.circle.fill"
        case .serious: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        @unknown default: return "questionmark.circle"
        }
    }

    private var stateColor: Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }

    private var stateText: String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

struct NetworkInterfaceRow: View {
    let interface: NetworkInterface

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(interface.displayName)
                    .fontWeight(.medium)
                Spacer()
                Text(interface.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .foregroundColor(.blue)
                    Text(formatBytesPerSecond(interface.downloadRate))
                        .monospacedDigit()
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .foregroundColor(.green)
                    Text(formatBytesPerSecond(interface.uploadRate))
                        .monospacedDigit()
                }
            }
            .font(.caption)

            Divider()
        }
    }
}

#Preview {
    PowerStorageView()
        .environmentObject(SystemMonitor.shared)
        .frame(width: 600, height: 700)
}
