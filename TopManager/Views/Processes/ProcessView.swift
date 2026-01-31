import SwiftUI

enum ProcessSortColumn: String {
    case name, pid, cpu, cpuTotal, memory, threads, user, state
}

struct ProcessView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @State private var searchText = ""
    @State private var selectedProcess: Set<ProcessItem.ID> = []
    @State private var sortColumn: ProcessSortColumn = .cpu
    @State private var sortAscending: Bool = false
    @State private var displayedProcesses: [ProcessItem] = []

    // Keep sortOrder for Table binding compatibility
    @State private var sortOrder: [KeyPathComparator<ProcessItem>] = [
        .init(\.cpuUsage, order: .reverse)
    ]

    // Confirmation dialogs
    @State private var showTerminateConfirm = false
    @State private var showForceKillConfirm = false
    @State private var processToKill: ProcessItem?

    // "Don't ask again" preference (only for Terminate, not Force Kill)
    @AppStorage("skipTerminateConfirm") private var skipTerminateConfirm = false

    // Error handling
    @State private var showErrorAlert = false
    @State private var errorTitle = ""
    @State private var errorMessage = ""

    // Protected system processes that cannot be force-killed via UI
    private static let protectedProcesses = ["kernel_task", "launchd", "WindowServer", "loginwindow"]

    private func isProtectedProcess(_ name: String) -> Bool {
        Self.protectedProcesses.contains(name)
    }

    private func updateDisplayedProcesses() {
        let filtered = monitor.processes.filter {
            searchText.isEmpty ||
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            String($0.pid).contains(searchText)
        }

        displayedProcesses = filtered.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch sortColumn {
            case .name:
                comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            case .pid:
                comparison = lhs.pid < rhs.pid ? .orderedAscending : (lhs.pid > rhs.pid ? .orderedDescending : .orderedSame)
            case .cpu:
                comparison = lhs.cpuUsage < rhs.cpuUsage ? .orderedAscending : (lhs.cpuUsage > rhs.cpuUsage ? .orderedDescending : .orderedSame)
            case .cpuTotal:
                comparison = lhs.cpuUsageTotal < rhs.cpuUsageTotal ? .orderedAscending : (lhs.cpuUsageTotal > rhs.cpuUsageTotal ? .orderedDescending : .orderedSame)
            case .memory:
                comparison = lhs.memoryUsage < rhs.memoryUsage ? .orderedAscending : (lhs.memoryUsage > rhs.memoryUsage ? .orderedDescending : .orderedSame)
            case .threads:
                comparison = lhs.threadCount < rhs.threadCount ? .orderedAscending : (lhs.threadCount > rhs.threadCount ? .orderedDescending : .orderedSame)
            case .user:
                comparison = lhs.user.localizedCaseInsensitiveCompare(rhs.user)
            case .state:
                comparison = lhs.state.rawValue.compare(rhs.state.rawValue)
            }

            // Primary sort
            if comparison != .orderedSame {
                return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
            }

            // Tiebreaker: sort by PID for stability
            return lhs.pid < rhs.pid
        }
    }

    var selectedProcessItem: ProcessItem? {
        guard let pid = selectedProcess.first else { return nil }
        return monitor.processes.first { $0.pid == pid }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary bar - separate view to avoid re-rendering table
            ProcessSummaryBar(processCount: displayedProcesses.count, searchText: $searchText)

            Divider()

            // Process table
            Table(displayedProcesses, selection: $selectedProcess, sortOrder: $sortOrder) {
                TableColumn("") { process in
                    if let icon = process.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "app.dashed")
                            .frame(width: 16, height: 16)
                    }
                }
                .width(24)

                TableColumn("Name", value: \.name) { process in
                    Text(process.name)
                        .lineLimit(1)
                }
                .width(min: 150, ideal: 200)

                TableColumn("PID", value: \.pid) { process in
                    Text("\(process.pid)")
                        .monospacedDigit()
                }
                .width(60)

                TableColumn("CPU/Core", value: \.cpuUsage) { process in
                    Text(String(format: "%.1f%%", process.cpuUsage))
                        .monospacedDigit()
                        .foregroundColor(cpuColor(process.cpuUsage))
                }
                .width(70)

                TableColumn("CPU/Total", value: \.cpuUsageTotal) { process in
                    Text(String(format: "%.2f%%", process.cpuUsageTotal))
                        .monospacedDigit()
                        .foregroundColor(cpuColorTotal(process.cpuUsageTotal))
                }
                .width(70)

                TableColumn("Memory", value: \.memoryUsage) { process in
                    Text(formatBytes(process.memoryUsage))
                        .monospacedDigit()
                }
                .width(80)

                TableColumn("Threads", value: \.threadCount) { process in
                    Text("\(process.threadCount)")
                        .monospacedDigit()
                }
                .width(60)

                TableColumn("User", value: \.user) { process in
                    Text(process.user)
                        .lineLimit(1)
                }
                .width(80)

                TableColumn("State", value: \.state.rawValue) { process in
                    HStack(spacing: 4) {
                        Image(systemName: process.state.symbol)
                            .foregroundColor(stateColor(process.state))
                        Text(process.state.rawValue)
                    }
                }
                .width(90)
            }
            .contextMenu(forSelectionType: ProcessItem.ID.self) { selection in
                if let pid = selection.first,
                   let process = monitor.processes.first(where: { $0.pid == pid }) {
                    Button("Terminate (⌫)") {
                        initiateTerminate()
                    }
                    Button("Force Kill (⌘⌫)") {
                        initiateForceKill()
                    }
                    Divider()
                    Button("Suspend") {
                        performSuspend(process: process)
                    }
                    Button("Resume") {
                        performResume(process: process)
                    }
                    Divider()
                    Button("Copy PID") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(pid)", forType: .string)
                    }
                }
            } primaryAction: { selection in
                // Double-click action
            }
            .onDeleteCommand {
                initiateTerminate()
            }
        }
        .onAppear {
            updateDisplayedProcesses()
        }
        .onChange(of: monitor.processes) { _ in
            updateDisplayedProcesses()
        }
        .onChange(of: searchText) { _ in
            updateDisplayedProcesses()
        }
        .onChange(of: sortColumn) { _ in
            updateDisplayedProcesses()
        }
        .onChange(of: sortAscending) { _ in
            updateDisplayedProcesses()
        }
        .onChange(of: sortOrder) { newOrder in
            guard let comparator = newOrder.first else { return }

            // Detect which column and direction from the KeyPathComparator
            let ascending = comparator.order == .forward

            // Use string representation of keypath to determine column
            let keyPathString = String(describing: comparator)

            if keyPathString.contains("cpuUsageTotal") {
                sortColumn = .cpuTotal
            } else if keyPathString.contains("cpuUsage") {
                sortColumn = .cpu
            } else if keyPathString.contains("memoryUsage") {
                sortColumn = .memory
            } else if keyPathString.contains("name") {
                sortColumn = .name
            } else if keyPathString.contains("pid") {
                sortColumn = .pid
            } else if keyPathString.contains("threadCount") {
                sortColumn = .threads
            } else if keyPathString.contains("user") {
                sortColumn = .user
            } else if keyPathString.contains("state") {
                sortColumn = .state
            }

            sortAscending = ascending
        }
        .background(
            KeyboardShortcutHandler(
                onCommandBackspace: { initiateForceKill() }
            )
        )
        .sheet(isPresented: $showTerminateConfirm) {
            if let process = processToKill {
                ConfirmationSheet(
                    title: "Terminate Process",
                    message: "Are you sure you want to terminate \"\(process.name)\" (PID: \(process.pid))?",
                    actionTitle: "Terminate",
                    isDestructive: true,
                    skipPreferenceKey: "skipTerminateConfirm",
                    onConfirm: {
                        performTerminate(process: process)
                    },
                    onCancel: {}
                )
            }
        }
        .sheet(isPresented: $showForceKillConfirm) {
            if let process = processToKill {
                ConfirmationSheet(
                    title: "Force Kill Process",
                    message: "Are you sure you want to force kill \"\(process.name)\" (PID: \(process.pid))?\n\nThis will immediately terminate the process without allowing it to save data.",
                    actionTitle: "Force Kill",
                    isDestructive: true,
                    // SAFETY: Force Kill always requires confirmation - no "Don't ask again" option
                    skipPreferenceKey: nil,
                    onConfirm: {
                        performForceKill(process: process)
                    },
                    onCancel: {}
                )
            }
        }
        .alert(errorTitle, isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func initiateTerminate() {
        guard let process = selectedProcessItem else { return }
        processToKill = process

        if skipTerminateConfirm {
            performTerminate(process: process)
        } else {
            showTerminateConfirm = true
        }
    }

    private func initiateForceKill() {
        guard let process = selectedProcessItem else { return }

        // SAFETY: Prevent force-killing critical system processes
        if isProtectedProcess(process.name) {
            errorTitle = "Cannot Force Kill System Process"
            errorMessage = "\"\(process.name)\" is a critical system process.\n\nForce killing this process would crash your system or cause immediate logout."
            showErrorAlert = true
            return
        }

        processToKill = process
        // SAFETY: Force Kill always requires confirmation - no "Don't ask again" option
        showForceKillConfirm = true
    }

    private func performTerminate(process: ProcessItem) {
        let result = monitor.terminateProcess(process.pid, expectedStartTime: process.startTime)
        handleProcessControlResult(result, action: "terminate", processName: process.name)
    }

    private func performForceKill(process: ProcessItem) {
        let result = monitor.forceKillProcess(process.pid, expectedStartTime: process.startTime)
        handleProcessControlResult(result, action: "force kill", processName: process.name)
    }

    private func performSuspend(process: ProcessItem) {
        let result = monitor.suspendProcess(process.pid, expectedStartTime: process.startTime)
        handleProcessControlResult(result, action: "suspend", processName: process.name)
    }

    private func performResume(process: ProcessItem) {
        let result = monitor.resumeProcess(process.pid, expectedStartTime: process.startTime)
        handleProcessControlResult(result, action: "resume", processName: process.name)
    }

    private func handleProcessControlResult(_ result: Result<Void, ProcessControlError>, action: String, processName: String) {
        switch result {
        case .success:
            break // Success - no action needed
        case .failure(let error):
            errorTitle = "Unable to \(action) \"\(processName)\""
            errorMessage = "\(error.errorDescription ?? "Unknown error")\n\n\(error.recoverySuggestion ?? "")"
            showErrorAlert = true
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

    private func cpuColorTotal(_ usage: Double) -> Color {
        if usage > 10 {
            return .red
        } else if usage > 5 {
            return .orange
        } else if usage > 2 {
            return .yellow
        }
        return .primary
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
}

struct ConfirmationSheet: View {
    let title: String
    let message: String
    let actionTitle: String
    let isDestructive: Bool
    let skipPreferenceKey: String?  // nil = don't show "Don't ask again" option
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dontAskAgain = false
    @AppStorage private var skipConfirm: Bool

    init(
        title: String,
        message: String,
        actionTitle: String,
        isDestructive: Bool,
        skipPreferenceKey: String? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.isDestructive = isDestructive
        self.skipPreferenceKey = skipPreferenceKey
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        // Use a dummy key if skipPreferenceKey is nil (won't be used anyway)
        self._skipConfirm = AppStorage(wrappedValue: false, skipPreferenceKey ?? "_unused_")
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isDestructive ? "exclamationmark.triangle.fill" : "questionmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(isDestructive ? .orange : .blue)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Only show "Don't ask again" if a preference key is provided
            if skipPreferenceKey != nil {
                Toggle("Don't ask again", isOn: $dontAskAgain)
                    .toggleStyle(.checkbox)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(actionTitle) {
                    if dontAskAgain && skipPreferenceKey != nil {
                        skipConfirm = true
                    }
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(isDestructive ? .red : .accentColor)
            }
        }
        .padding(24)
        .frame(width: 350)
    }
}

struct KeyboardShortcutHandler: NSViewRepresentable {
    let onCommandBackspace: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureView()
        view.onCommandBackspace = onCommandBackspace
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyCaptureView {
            view.onCommandBackspace = onCommandBackspace
        }
    }

    class KeyCaptureView: NSView {
        var onCommandBackspace: (() -> Void)?

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // Backspace = keyCode 51
            if event.keyCode == 51 && event.modifierFlags.contains(.command) {
                onCommandBackspace?()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}

struct ProcessSummaryBar: View {
    @EnvironmentObject var monitor: SystemMonitor
    let processCount: Int
    @Binding var searchText: String

    var body: some View {
        HStack {
            Text("\(processCount) processes")
                .foregroundColor(.secondary)

            Spacer()

            if let cpu = monitor.cpuInfo {
                Text("CPU: \(String(format: "%.1f%%", cpu.globalUsage))")
                    .monospacedDigit()
            }

            if let mem = monitor.memoryInfo {
                Text("Memory: \(formatBytes(mem.usedMemory)) / \(formatBytes(mem.totalMemory))")
                    .monospacedDigit()
            }

            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    ProcessView()
        .environmentObject(SystemMonitor.shared)
}
