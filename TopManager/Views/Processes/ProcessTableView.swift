import SwiftUI
import AppKit

// MARK: - Presentation (pure, unit-tested)

/// Colour role of a cell's text or leading symbol.
enum ProcessCellTone: Equatable {
    case primary, secondary, green, yellow, orange, red

    var color: NSColor {
        switch self {
        case .primary: return .labelColor
        case .secondary: return .secondaryLabelColor
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .orange: return .systemOrange
        case .red: return .systemRed
        }
    }
}

/// Everything one table cell displays. Cells only touch AppKit when this changes.
struct ProcessCellContent: Equatable {
    enum Leading: Equatable {
        case none
        case icon(NSImage)
        case symbol(String, ProcessCellTone)

        static func == (lhs: Leading, rhs: Leading) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none): return true
            case let (.icon(a), .icon(b)): return a === b
            case let (.symbol(a, aTone), .symbol(b, bTone)): return a == b && aTone == bTone
            default: return false
            }
        }
    }

    var text: String
    var tone: ProcessCellTone = .primary
    var leading: Leading = .none
    var monospacedDigits = false
}

/// The Processes table's columns, in display order.
enum ProcessColumn: String, CaseIterable {
    case name, pid, cpu, cpuTotal, energy, memory, resident, compressed, disk, threads, user, state

    var sortColumn: ProcessSortColumn {
        guard let column = ProcessSortColumn(rawValue: rawValue) else {
            preconditionFailure("ProcessColumn.\(rawValue) has no matching ProcessSortColumn")
        }
        return column
    }

    var title: String {
        switch self {
        case .name: return "Name"
        case .pid: return "PID"
        case .cpu: return "CPU/Core"
        case .cpuTotal: return "CPU/Total"
        case .energy: return "Energy"
        case .memory: return "Memory"
        case .resident: return "RAM"
        case .compressed: return "Compressed"
        case .disk: return "Disk I/O"
        case .threads: return "Threads"
        case .user: return "User"
        case .state: return "State"
        }
    }

    var width: CGFloat {
        switch self {
        case .name: return 220
        case .pid, .energy, .threads: return 60
        case .cpu, .cpuTotal: return 70
        case .memory, .resident, .user: return 80
        case .compressed: return 85
        case .disk, .state: return 90
        }
    }

    /// Text columns sort A→Z on first click; figures sort largest first.
    var sortsAscendingFirst: Bool {
        switch self {
        case .name, .pid, .user, .state: return true
        default: return false
        }
    }

    /// Sort order after a click on this column's header: the current column
    /// flips direction, any other column starts in its natural direction.
    func sortAfterClick(current: ProcessSortColumn, ascending: Bool) -> (column: ProcessSortColumn, ascending: Bool) {
        sortColumn == current ? (current, !ascending) : (sortColumn, sortsAscendingFirst)
    }

    func content(for process: ProcessItem) -> ProcessCellContent {
        switch self {
        case .name:
            return ProcessCellContent(text: process.name,
                                      leading: process.icon.map { .icon($0) } ?? .symbol("app.dashed", .secondary))
        case .pid:
            return ProcessCellContent(text: String(process.pid), monospacedDigits: true)
        case .cpu:
            return ProcessCellContent(text: String(format: "%.1f%%", process.cpuUsage),
                                      tone: Self.tone(process.cpuUsage, yellow: 20, orange: 50, red: 80),
                                      monospacedDigits: true)
        case .cpuTotal:
            return ProcessCellContent(text: String(format: "%.2f%%", process.cpuUsageTotal),
                                      tone: Self.tone(process.cpuUsageTotal, yellow: 2, orange: 5, red: 10),
                                      monospacedDigits: true)
        case .energy:
            return ProcessCellContent(text: String(format: "%.1f", process.energyImpact),
                                      tone: Self.tone(process.energyImpact, yellow: 8, orange: 20, red: 50),
                                      monospacedDigits: true)
        case .memory:
            return ProcessCellContent(text: formatBytes(process.memoryUsage), monospacedDigits: true)
        case .resident:
            return ProcessCellContent(text: formatBytes(process.residentMemory), monospacedDigits: true)
        case .compressed:
            return process.compressedMemory > 0
                ? ProcessCellContent(text: formatBytes(process.compressedMemory), monospacedDigits: true)
                : ProcessCellContent(text: "—", tone: .secondary)
        case .disk:
            return process.diskTotalRate > 0
                ? ProcessCellContent(text: formatBytesPerSecond(process.diskTotalRate), monospacedDigits: true)
                : ProcessCellContent(text: "—", tone: .secondary)
        case .threads:
            return ProcessCellContent(text: String(process.threadCount), monospacedDigits: true)
        case .user:
            return ProcessCellContent(text: process.user)
        case .state:
            return ProcessCellContent(text: process.state.rawValue,
                                      leading: .symbol(process.state.symbol, Self.tone(for: process.state)))
        }
    }

    static func tone(_ value: Double, yellow: Double, orange: Double, red: Double) -> ProcessCellTone {
        if value > red { return .red }
        if value > orange { return .orange }
        if value > yellow { return .yellow }
        return .primary
    }

    static func tone(for state: ProcessState) -> ProcessCellTone {
        switch state {
        case .running: return .green
        case .stopped: return .orange
        case .zombie: return .red
        case .sleeping, .unknown: return .secondary
        }
    }
}

// MARK: - Table

/// Callbacks from the table back into `ProcessView`.
struct ProcessTableActions {
    var open: (ProcessItem) -> Void
    var terminate: (ProcessItem) -> Void
    var forceKill: (ProcessItem) -> Void
    var suspend: (ProcessItem) -> Void
    var resume: (ProcessItem) -> Void
    var deleteKey: () -> Void
}

/// The process list as a plain AppKit `NSTableView`.
///
/// Replaces SwiftUI's `Table`, which on macOS 26 retained AutoLayout and
/// view-graph objects on every data update — tens of MB an hour while the window
/// was visible — on top of an NSHostingView per cell. Measured side by side
/// (6 min, window visible, scrolling): heap growth fell from ~600 KB/min to
/// ~35 KB/min and the starting footprint from 67 MB to 49 MB.
/// Cells here are reused AppKit views, and an update rewrites only the fields
/// that changed in rows that are on screen; the table reloads only once, on
/// its first update.
struct ProcessTableView: NSViewRepresentable {
    let processes: [ProcessItem]
    @Binding var selection: Set<ProcessItem.ID>
    let sortColumn: ProcessSortColumn
    let sortAscending: Bool
    let onSort: (ProcessSortColumn, Bool) -> Void
    let actions: ProcessTableActions

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let table = ProcessNSTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.rowHeight = 24

        for column in ProcessColumn.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = column == .name ? 170 : 40
            tableColumn.resizingMask = column == .name ? [.autoresizingMask, .userResizingMask] : .userResizingMask
            table.addTableColumn(tableColumn)
        }
        // Remembers column widths and order between launches.
        table.autosaveName = "ProcessTable"
        table.autosaveTableColumns = true

        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.onDelete = { [weak coordinator] in coordinator?.parent.actions.deleteKey() }

        let menu = NSMenu()
        menu.delegate = coordinator
        table.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        coordinator.tableView = table
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: ProcessTableView
        weak var tableView: NSTableView?
        private var rows: [ProcessItem] = []
        private var isSyncing = false
        /// The first update must reload: right after `dataSource` is set, the
        /// table still has an initial load pending, and `noteNumberOfRowsChanged`
        /// on top of it doubles the row count (blank rows below the list).
        private var needsInitialLoad = true
        private var shownSort: (column: ProcessSortColumn, ascending: Bool)?

        init(parent: ProcessTableView) {
            self.parent = parent
        }

        // MARK: Updates

        func update() {
            guard let tableView else { return }
            isSyncing = true
            defer { isSyncing = false }

            let newRows = parent.processes
            if needsInitialLoad {
                needsInitialLoad = false
                rows = newRows
                tableView.reloadData()
            } else if Self.rowsDiffer(rows, newRows) {
                let countChanged = newRows.count != rows.count
                rows = newRows
                if countChanged { tableView.noteNumberOfRowsChanged() }
                refreshPreparedCells(in: tableView)
            }

            let selected = IndexSet(rows.indices.filter { parent.selection.contains(rows[$0].pid) })
            if selected != tableView.selectedRowIndexes {
                tableView.selectRowIndexes(selected, byExtendingSelection: false)
            }

            if shownSort?.column != parent.sortColumn || shownSort?.ascending != parent.sortAscending {
                showSortIndicator(in: tableView)
            }
        }

        /// Sorting is driven by `ProcessView`, not by NSTableView's sort descriptors:
        /// the built-in header toggling ignored the prototypes' direction, so figure
        /// columns started smallest-first.
        private func showSortIndicator(in tableView: NSTableView) {
            for tableColumn in tableView.tableColumns {
                tableView.setIndicatorImage(nil, in: tableColumn)
            }
            let identifier = NSUserInterfaceItemIdentifier(parent.sortColumn.rawValue)
            if let tableColumn = tableView.tableColumn(withIdentifier: identifier) {
                let name = parent.sortAscending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator"
                tableView.setIndicatorImage(NSImage(named: name), in: tableColumn)
                tableView.highlightedTableColumn = tableColumn
            }
            shownSort = (parent.sortColumn, parent.sortAscending)
        }

        /// `ProcessItem ==` compares live figures only, so also catch a PID that
        /// now belongs to a different process.
        static func rowsDiffer(_ old: [ProcessItem], _ new: [ProcessItem]) -> Bool {
            guard old.count == new.count else { return true }
            for (a, b) in zip(old, new) where a != b || a.name != b.name || a.startTime != b.startTime || a.user != b.user {
                return true
            }
            return false
        }

        /// Rewrites the cells AppKit currently holds views for (on screen plus its
        /// small overdraw margin). Rows outside get configured when they scroll in.
        private func refreshPreparedCells(in tableView: NSTableView) {
            let range = tableView.rows(in: tableView.preparedContentRect)
            guard range.length > 0 else { return }
            for row in range.location..<min(range.location + range.length, rows.count) {
                for (index, tableColumn) in tableView.tableColumns.enumerated() {
                    guard let column = ProcessColumn(rawValue: tableColumn.identifier.rawValue),
                          let cell = tableView.view(atColumn: index, row: row, makeIfNecessary: false) as? ProcessTableCellView
                    else { continue }
                    cell.apply(column.content(for: rows[row]))
                }
            }
        }

        // MARK: Data source & delegate

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let identifier = tableColumn?.identifier,
                  let column = ProcessColumn(rawValue: identifier.rawValue),
                  row < rows.count else { return nil }
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ProcessTableCellView
                ?? ProcessTableCellView(identifier: identifier)
            cell.apply(column.content(for: rows[row]))
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncing, let tableView else { return }
            parent.selection = Set(tableView.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].pid : nil })
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            guard let column = ProcessColumn(rawValue: tableColumn.identifier.rawValue) else { return }
            let next = column.sortAfterClick(current: parent.sortColumn, ascending: parent.sortAscending)
            parent.onSort(next.column, next.ascending)
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < rows.count else { return }
            parent.actions.open(rows[row])
        }

        // MARK: Context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            // A right-click sets clickedRow; a menu opened from the keyboard or
            // VoiceOver has none, so fall back to the selection.
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard row >= 0, row < rows.count else { return }
            if !tableView.selectedRowIndexes.contains(row) {
                tableView.selectRowIndexes([row], byExtendingSelection: false)
            }
            // Actions get the clicked process directly rather than reading the
            // selection back through SwiftUI state, which may not have updated yet.
            let process = rows[row]
            let actions = parent.actions
            addItem("Get Info (⌘I)", to: menu) { actions.open(process) }
            menu.addItem(.separator())
            addItem("Terminate (⌫)", to: menu) { actions.terminate(process) }
            addItem("Force Kill (⌘⌫)", to: menu) { actions.forceKill(process) }
            menu.addItem(.separator())
            addItem("Suspend", to: menu) { actions.suspend(process) }
            addItem("Resume", to: menu) { actions.resume(process) }
            menu.addItem(.separator())
            addItem("Copy PID", to: menu) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(process.pid), forType: .string)
            }
        }

        private final class MenuAction {
            let run: () -> Void
            init(_ run: @escaping () -> Void) { self.run = run }
        }

        private func addItem(_ title: String, to menu: NSMenu, run: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MenuAction(run)
            menu.addItem(item)
        }

        @objc private func performMenuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? MenuAction)?.run()
        }
    }
}

/// Adds the plain Delete / Forward Delete key (⌘⌫ is handled by `KeyboardShortcutHandler`).
final class ProcessNSTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad])
        if (event.keyCode == 51 || event.keyCode == 117) && modifiers.isEmpty {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}

/// A reusable cell: optional 16 pt leading image plus a label, laid out by hand
/// (no constraints) and updated field by field.
final class ProcessTableCellView: NSTableCellView {
    private static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private static let digitFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private static let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))

    private let label = NSTextField(labelWithString: "")
    private let leadingView = NSImageView()
    private var content: ProcessCellContent?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.lineBreakMode = .byTruncatingTail
        label.font = Self.font
        leadingView.imageScaling = .scaleProportionallyUpOrDown
        leadingView.isHidden = true
        addSubview(leadingView)
        addSubview(label)
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(_ new: ProcessCellContent) {
        guard new != content else { return }
        let old = content
        content = new

        if new.text != old?.text { label.stringValue = new.text }
        if new.tone != old?.tone { label.textColor = new.tone.color }
        if new.monospacedDigits != old?.monospacedDigits {
            label.font = new.monospacedDigits ? Self.digitFont : Self.font
        }
        if new.leading != old?.leading {
            switch new.leading {
            case .none:
                leadingView.image = nil
                leadingView.isHidden = true
            case .icon(let image):
                leadingView.image = image
                leadingView.contentTintColor = nil
                leadingView.isHidden = false
            case .symbol(let name, let tone):
                leadingView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
                leadingView.contentTintColor = tone.color
                leadingView.isHidden = false
            }
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        var x: CGFloat = 0
        if !leadingView.isHidden {
            leadingView.frame = NSRect(x: 0, y: floor((height - 16) / 2), width: 16, height: 16)
            x = 22
        }
        label.frame = NSRect(x: x, y: floor((height - Self.lineHeight) / 2),
                             width: max(0, bounds.width - x), height: Self.lineHeight)
    }
}
