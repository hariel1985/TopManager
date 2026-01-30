import SwiftUI
import AppKit

struct RunningApp: Identifiable {
    let id: pid_t
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let isActive: Bool
    let isHidden: Bool
    let launchDate: Date?
    var cpuUsage: Double
    var memoryUsage: Int64
}

struct AppsView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @State private var runningApps: [RunningApp] = []
    @State private var selectedApp: Set<pid_t> = []
    @State private var sortOrder: [KeyPathComparator<RunningApp>] = [
        .init(\.name, order: .forward)
    ]
    @State private var searchText = ""

    var filteredApps: [RunningApp] {
        let filtered = runningApps.filter {
            searchText.isEmpty ||
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        return filtered.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary bar
            HStack {
                Text("\(runningApps.count) apps")
                    .foregroundColor(.secondary)

                Spacer()

                if let activeApp = runningApps.first(where: { $0.isActive }) {
                    HStack(spacing: 4) {
                        Text("Active:")
                            .foregroundColor(.secondary)
                        if let icon = activeApp.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 14, height: 14)
                        }
                        Text(activeApp.name)
                            .fontWeight(.medium)
                    }
                }

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Apps table
            Table(filteredApps, selection: $selectedApp, sortOrder: $sortOrder) {
                TableColumn("") { app in
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "app.dashed")
                            .frame(width: 20, height: 20)
                    }
                }
                .width(28)

                TableColumn("Name", value: \.name) { app in
                    HStack(spacing: 6) {
                        Text(app.name)
                            .lineLimit(1)
                        if app.isActive {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                        if app.isHidden {
                            Image(systemName: "eye.slash")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .width(min: 150, ideal: 200)

                TableColumn("PID", value: \.pid) { app in
                    Text("\(app.pid)")
                        .monospacedDigit()
                }
                .width(60)

                TableColumn("CPU %", value: \.cpuUsage) { app in
                    Text(String(format: "%.1f%%", app.cpuUsage))
                        .monospacedDigit()
                        .foregroundColor(cpuColor(app.cpuUsage))
                }
                .width(70)

                TableColumn("Memory", value: \.memoryUsage) { app in
                    Text(formatBytes(app.memoryUsage))
                        .monospacedDigit()
                }
                .width(90)

                TableColumn("Bundle ID") { app in
                    Text(app.bundleIdentifier ?? "-")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .width(min: 150, ideal: 200)
            }
            .contextMenu(forSelectionType: pid_t.self) { selection in
                if let pid = selection.first, let app = runningApps.first(where: { $0.pid == pid }) {
                    Button("Activate") {
                        activateApp(pid: pid)
                    }
                    Button("Hide") {
                        hideApp(pid: pid)
                    }
                    Divider()
                    Button("Quit") {
                        quitApp(pid: pid)
                    }
                    Button("Force Quit") {
                        forceQuitApp(pid: pid)
                    }
                    Divider()
                    Button("Copy Bundle ID") {
                        if let bundleId = app.bundleIdentifier {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(bundleId, forType: .string)
                        }
                    }
                    .disabled(app.bundleIdentifier == nil)
                }
            } primaryAction: { selection in
                if let pid = selection.first {
                    activateApp(pid: pid)
                }
            }
        }
        .onAppear {
            refreshApps()
        }
        .onChange(of: monitor.processes) { _ in
            refreshApps()
        }
    }

    private func refreshApps() {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications

        // Build a map of PID to process info for CPU/memory data
        let processMap = Dictionary(uniqueKeysWithValues: monitor.processes.map { ($0.pid, $0) })

        runningApps = apps.compactMap { app -> RunningApp? in
            // Only include regular apps (not background agents)
            guard app.activationPolicy == .regular else { return nil }

            let pid = app.processIdentifier
            let processInfo = processMap[pid]

            return RunningApp(
                id: pid,
                pid: pid,
                name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                bundleIdentifier: app.bundleIdentifier,
                icon: app.icon,
                isActive: app.isActive,
                isHidden: app.isHidden,
                launchDate: app.launchDate,
                cpuUsage: processInfo?.cpuUsage ?? 0,
                memoryUsage: processInfo?.memoryUsage ?? 0
            )
        }
    }

    private func activateApp(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func hideApp(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.hide()
        }
    }

    private func quitApp(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.terminate()
        }
    }

    private func forceQuitApp(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.forceTerminate()
        }
    }

    private func cpuColor(_ usage: Double) -> Color {
        if usage > 80 {
            return .red
        } else if usage > 50 {
            return .orange
        } else if usage > 20 {
            return .yellow
        }
        return .primary
    }
}

#Preview {
    AppsView()
        .environmentObject(SystemMonitor.shared)
}
