import SwiftUI
import Charts

struct PerformanceView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CPUTabView()
                .tabItem {
                    Label("CPU", systemImage: "cpu")
                }
                .tag(0)

            MemoryTabView()
                .tabItem {
                    Label("Memory", systemImage: "memorychip")
                }
                .tag(1)

            NetworkTabView()
                .tabItem {
                    Label("Network", systemImage: "network")
                }
                .tag(2)
        }
    }
}

// MARK: - CPU Tab

struct CPUTabView: View {
    @EnvironmentObject var monitor: SystemMonitor

    private let coreColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Overall CPU
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Total CPU Usage")
                                .font(.headline)
                            Spacer()
                            if let cpu = monitor.cpuInfo {
                                Text(String(format: "%.1f%%", cpu.globalUsage))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                        }

                        CPULineChart(history: monitor.cpuHistory)
                            .frame(height: 120)

                        // Legend
                        HStack(spacing: 20) {
                            ChartLegendItem(color: .blue, label: "User")
                            ChartLegendItem(color: .red, label: "System")
                            ChartLegendItem(color: .gray, label: "Total")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                }

                // Per-core charts
                if let cpu = monitor.cpuInfo {
                    // P-Cores
                    if !cpu.pCoreUsages.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Performance Cores")
                                    .font(.headline)

                                LazyVGrid(columns: coreColumns, spacing: 12) {
                                    ForEach(cpu.pCoreUsages) { core in
                                        CoreLineChartView(
                                            coreId: core.id,
                                            coreType: "P",
                                            usage: core.usage,
                                            history: monitor.coreHistories[core.id] ?? [],
                                            color: .orange
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    // E-Cores
                    if !cpu.eCoreUsages.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Efficiency Cores")
                                    .font(.headline)

                                LazyVGrid(columns: coreColumns, spacing: 12) {
                                    ForEach(cpu.eCoreUsages) { core in
                                        CoreLineChartView(
                                            coreId: core.id,
                                            coreType: "E",
                                            usage: core.usage,
                                            history: monitor.coreHistories[core.id] ?? [],
                                            color: .blue
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    // All cores (for non-Apple Silicon)
                    if cpu.pCoreUsages.isEmpty && cpu.eCoreUsages.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("CPU Cores")
                                    .font(.headline)

                                LazyVGrid(columns: coreColumns, spacing: 12) {
                                    ForEach(cpu.coreUsages) { core in
                                        CoreLineChartView(
                                            coreId: core.id,
                                            coreType: "",
                                            usage: core.usage,
                                            history: monitor.coreHistories[core.id] ?? [],
                                            color: .blue
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct CoreLineChartView: View {
    let coreId: Int
    let coreType: String
    let usage: Double
    let history: [CoreHistoryPoint]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(coreType.isEmpty ? "Core \(coreId)" : "\(coreType)\(coreId)")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.0f%%", usage))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(usageColor(usage))
            }

            // Line chart for this core
            Chart {
                ForEach(history) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Usage", point.usage)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartYScale(domain: -5...105)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 50)
            .drawingGroup()
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private func usageColor(_ usage: Double) -> Color {
        if usage > 80 { return .red }
        if usage > 50 { return .orange }
        return .primary
    }
}

// MARK: - Memory Tab

struct MemoryTabView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    // Left column: Donut chart
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Memory Composition")
                                .font(.headline)

                            MemoryDonutView()
                                .frame(height: 200)

                            if let mem = monitor.memoryInfo {
                                MemoryLegendView(memory: mem)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // Right column: Chart + Details
                    VStack(spacing: 16) {
                        // Memory history chart
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Memory Usage Over Time")
                                        .font(.headline)
                                    Spacer()
                                    if let mem = monitor.memoryInfo {
                                        Text(String(format: "%.1f%%", mem.usagePercentage))
                                            .font(.title2)
                                            .fontWeight(.semibold)
                                            .monospacedDigit()
                                    }
                                }

                                MemoryLineChart(history: monitor.memoryHistory)
                                    .frame(height: 150)

                                if let mem = monitor.memoryInfo {
                                    HStack {
                                        Text("Used: \(formatBytes(mem.usedMemory))")
                                        Spacer()
                                        Text("Free: \(formatBytes(mem.freeMemory))")
                                        Spacer()
                                        Text("Total: \(formatBytes(mem.totalMemory))")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }

                        // Memory details
                        if let mem = monitor.memoryInfo {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Memory Details")
                                        .font(.headline)

                                    HStack(spacing: 20) {
                                        MemoryStatItem(label: "Swap Used", value: formatBytes(mem.swapUsed))
                                        MemoryStatItem(label: "Swap Total", value: formatBytes(mem.swapTotal))
                                        MemoryStatItem(label: "Pressure", value: mem.memoryPressure.rawValue, color: pressureColor(mem.memoryPressure))
                                        Spacer()
                                    }
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                // GPU Memory
                if let gpu = monitor.gpuInfo {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("GPU", systemImage: "gpu")
                                    .font(.headline)
                                Text(gpu.name)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            HStack {
                                Text(gpu.memoryLabel + ":")
                                    .foregroundColor(.secondary)

                                if gpu.vramUsed > 0 {
                                    Text(formatBytes(gpu.vramUsed))
                                        .monospacedDigit()
                                    if let total = gpu.vramTotal {
                                        Text("/ \(formatBytes(total))")
                                            .foregroundColor(.secondary)
                                    }
                                } else if gpu.isUnifiedMemory {
                                    Text("Unified Memory Architecture")
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if let util = gpu.utilizationPercent {
                                    Text("GPU: \(String(format: "%.0f%%", util))")
                                        .monospacedDigit()
                                }
                            }

                            if gpu.vramUsed > 0, let total = gpu.vramTotal {
                                ProgressView(value: Double(gpu.vramUsed), total: Double(total))
                                    .tint(.purple)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding()
        }
    }

    private func pressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .nominal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .secondary
        }
    }
}

struct MemoryLegendView: View {
    let memory: MemoryInfo

    var body: some View {
        VStack(spacing: 4) {
            LegendRow(color: .blue, label: "App Memory", value: formatBytes(memory.appMemory))
            LegendRow(color: .orange, label: "Wired", value: formatBytes(memory.wiredMemory))
            LegendRow(color: .yellow, label: "Compressed", value: formatBytes(memory.compressedMemory))
            LegendRow(color: .green.opacity(0.5), label: "Cached/Free", value: formatBytes(memory.cachedMemory + memory.freeMemory))
        }
    }
}

struct LegendRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
    }
}

struct MemoryStatItem: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .foregroundColor(color)
                .monospacedDigit()
        }
    }
}

// MARK: - Network Tab

struct NetworkTabView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Download chart
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Download", systemImage: "arrow.down.circle")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                            if let net = monitor.networkInfo {
                                Text(formatBytesPerSecond(net.totalDownloadRate))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                        }

                        DownloadLineChart(history: monitor.networkHistory)
                            .frame(height: 150)
                    }
                    .padding(.vertical, 8)
                }

                // Upload chart
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Upload", systemImage: "arrow.up.circle")
                                .font(.headline)
                                .foregroundColor(.green)
                            Spacer()
                            if let net = monitor.networkInfo {
                                Text(formatBytesPerSecond(net.totalUploadRate))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                        }

                        UploadLineChart(history: monitor.networkHistory)
                            .frame(height: 150)
                    }
                    .padding(.vertical, 8)
                }

                // Network interfaces
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Network Interfaces")
                            .font(.headline)

                        if let net = monitor.networkInfo {
                            ForEach(net.interfaces.filter { $0.isActive }) { iface in
                                NetworkInterfaceRowView(interface: iface)
                            }

                            if net.interfaces.filter({ $0.isActive }).isEmpty {
                                Text("No active interfaces")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Totals
                if let net = monitor.networkInfo {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Session Totals")
                                .font(.headline)

                            HStack(spacing: 40) {
                                VStack(alignment: .leading) {
                                    Text("Downloaded")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatBytes(net.totalDownloadBytes))
                                        .monospacedDigit()
                                }

                                VStack(alignment: .leading) {
                                    Text("Uploaded")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatBytes(net.totalUploadBytes))
                                        .monospacedDigit()
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding()
        }
    }
}

struct NetworkInterfaceRowView: View {
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
    PerformanceView()
        .environmentObject(SystemMonitor.shared)
        .frame(width: 900, height: 700)
}
