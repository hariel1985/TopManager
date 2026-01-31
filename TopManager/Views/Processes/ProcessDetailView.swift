import SwiftUI

struct ProcessDetailView: View {
    let process: ProcessItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                if let icon = process.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 48))
                }

                VStack(alignment: .leading) {
                    Text(process.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("PID: \(process.pid)")
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    HStack {
                        Image(systemName: process.state.symbol)
                        Text(process.state.rawValue)
                    }
                    .foregroundColor(stateColor(process.state))
                }
            }

            Divider()

            // Details grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], alignment: .leading, spacing: 12) {
                DetailRow(label: "CPU Usage", value: String(format: "%.1f%%", process.cpuUsage))
                DetailRow(label: "Memory", value: formatBytes(process.memoryUsage))
                DetailRow(label: "Threads", value: "\(process.threadCount)")
                DetailRow(label: "User", value: process.user)
                DetailRow(label: "Parent PID", value: "\(process.parentPid)")

                if let startTime = process.startTime {
                    DetailRow(label: "Started", value: formatDate(startTime))
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 300)
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
    ProcessDetailView(process: ProcessItem(
        pid: 1234,
        name: "Safari",
        user: "ariel",
        cpuUsage: 12.5,
        cpuUsageTotal: 1.56,
        memoryUsage: 512 * 1024 * 1024,
        threadCount: 42,
        state: .running,
        icon: nil,
        parentPid: 1,
        startTime: Date()
    ))
}
