import SwiftUI
import AppKit

/// Deep-dive inspector for a single process, presented as a sheet. Shows live
/// stats (looked up from the monitor by PID) plus on-demand details that are too
/// expensive to compute for every row every cycle: full path, launch arguments,
/// and open-file-descriptor count.
struct ProcessInspectorSheet: View {
    let initialProcess: ProcessItem
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.dismiss) private var dismiss

    @State private var arguments: [String] = []
    @State private var openFiles: Int?
    @State private var loadedDetails = false

    /// Prefer the latest live snapshot for this PID; fall back to the one we opened with.
    private var process: ProcessItem {
        monitor.processes.first { $0.pid == initialProcess.pid } ?? initialProcess
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    liveStats
                    pathSection
                    detailsSection
                }
            }

            Divider()
            footer
        }
        .padding(20)
        .frame(width: 460, height: 560)
        .task(id: initialProcess.pid) {
            let pid = initialProcess.pid
            let result = await Task.detached(priority: .userInitiated) {
                (args: fetchProcessArguments(pid: pid), files: fetchOpenFileCount(pid: pid))
            }.value
            arguments = result.args
            openFiles = result.files
            loadedDetails = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let icon = process.icon {
                Image(nsImage: icon).resizable().frame(width: 44, height: 44)
            } else {
                Image(systemName: "app.dashed").font(.system(size: 40)).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(process.name).font(.title2).fontWeight(.semibold).lineLimit(1)
                Text("PID \(process.pid)  •  \(process.user)").foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: process.state.symbol)
                Text(process.state.rawValue)
            }
            .foregroundColor(stateColor(process.state))
        }
    }

    private var liveStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                  alignment: .leading, spacing: 12) {
            DetailRow(label: "CPU (core)", value: String(format: "%.1f%%", process.cpuUsage))
            DetailRow(label: "CPU (total)", value: String(format: "%.2f%%", process.cpuUsageTotal))
            DetailRow(label: "Energy", value: String(format: "%.1f", process.energyImpact))
            DetailRow(label: "Memory", value: formatBytes(process.memoryUsage))
            DetailRow(label: "RAM", value: formatBytes(process.residentMemory))
            DetailRow(label: "Compressed", value: process.compressedMemory > 0 ? formatBytes(process.compressedMemory) : "—")
            DetailRow(label: "Threads", value: "\(process.threadCount)")
            DetailRow(label: "Open files", value: openFiles.map(String.init) ?? "…")
            DetailRow(label: "Disk read/s", value: process.diskReadRate > 0 ? formatBytesPerSecond(process.diskReadRate) : "—")
            DetailRow(label: "Disk write/s", value: process.diskWriteRate > 0 ? formatBytesPerSecond(process.diskWriteRate) : "—")
            DetailRow(label: "Disk total", value: formatBytes(process.diskReadBytes + process.diskWriteBytes))
            DetailRow(label: "Parent PID", value: "\(process.parentPid)")
            if let start = process.startTime {
                DetailRow(label: "Started", value: formatDate(start))
            }
        }
    }

    @ViewBuilder private var pathSection: some View {
        if let path = process.executablePath {
            VStack(alignment: .leading, spacing: 4) {
                Text("Path").font(.caption).foregroundColor(.secondary)
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Launch arguments").font(.caption).foregroundColor(.secondary)
            if !loadedDetails {
                Text("Loading…").font(.caption).foregroundColor(.secondary)
            } else if arguments.isEmpty {
                Text("Unavailable (process may be owned by another user)")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text(arguments.joined(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let path = process.executablePath {
                Button {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } label: { Label("Reveal in Finder", systemImage: "folder") }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                } label: { Label("Copy Path", systemImage: "doc.on.doc") }
            }
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }

    private func stateColor(_ state: ProcessState) -> Color {
        switch state {
        case .running: return .green
        case .sleeping: return .secondary
        case .stopped: return .orange
        case .zombie: return .red
        case .unknown: return .secondary
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .monospacedDigit()
        }
    }
}

#Preview {
    ProcessInspectorSheet(initialProcess: ProcessItem(
        pid: 1234, name: "Safari", user: "ariel",
        cpuUsage: 12.5, cpuUsageTotal: 1.56,
        memoryUsage: 512 * 1024 * 1024, threadCount: 42,
        state: .running, icon: nil, parentPid: 1, startTime: Date(),
        diskReadRate: 2048, diskWriteRate: 1024,
        diskReadBytes: 900_000, diskWriteBytes: 400_000,
        energyImpact: 14.2, executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
    ))
    .environmentObject(SystemMonitor.shared)
}
