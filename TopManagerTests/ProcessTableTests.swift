import XCTest
import AppKit
import SwiftUI
@testable import TopManager

final class ProcessTableTests: XCTestCase {

    private func item(pid: pid_t = 100, name: String = "proc", user: String = "ariel",
                      cpu: Double = 0, cpuTotal: Double = 0, energy: Double = 0,
                      memory: Int64 = 1_000_000, resident: Int64 = 2_000_000, compressed: Int64 = 0,
                      diskRead: Double = 0, state: ProcessState = .sleeping, icon: NSImage? = nil,
                      start: Date = Date(timeIntervalSince1970: 1_000)) -> ProcessItem {
        ProcessItem(pid: pid, name: name, user: user, cpuUsage: cpu, cpuUsageTotal: cpuTotal,
                    memoryUsage: memory, threadCount: 4, state: state, icon: icon, parentPid: 1,
                    startTime: start, diskReadRate: diskRead, energyImpact: energy,
                    residentMemory: resident, compressedMemory: compressed)
    }

    // MARK: Columns

    func testColumnsInDisplayOrder() {
        XCTAssertEqual(ProcessColumn.allCases.map(\.title),
                       ["Name", "PID", "CPU/Core", "CPU/Total", "Energy", "Memory", "RAM",
                        "Compressed", "Disk I/O", "Threads", "User", "State"])
    }

    func testEveryColumnSortsByItsOwnKey() {
        for column in ProcessColumn.allCases {
            XCTAssertEqual(column.sortColumn.rawValue, column.rawValue)
        }
    }

    func testTextColumnsSortAscendingFirstFiguresDescending() {
        XCTAssertTrue(ProcessColumn.name.sortsAscendingFirst)
        XCTAssertTrue(ProcessColumn.user.sortsAscendingFirst)
        XCTAssertFalse(ProcessColumn.cpu.sortsAscendingFirst)
        XCTAssertFalse(ProcessColumn.memory.sortsAscendingFirst)
        XCTAssertFalse(ProcessColumn.compressed.sortsAscendingFirst)
    }

    func testHeaderClickFlipsCurrentColumnAndStartsOthersInNaturalDirection() {
        XCTAssertTrue(ProcessColumn.cpu.sortAfterClick(current: .cpu, ascending: false) == (.cpu, true))
        XCTAssertTrue(ProcessColumn.cpu.sortAfterClick(current: .cpu, ascending: true) == (.cpu, false))
        XCTAssertTrue(ProcessColumn.memory.sortAfterClick(current: .name, ascending: true) == (.memory, false))
        XCTAssertTrue(ProcessColumn.resident.sortAfterClick(current: .memory, ascending: false) == (.resident, false))
        XCTAssertTrue(ProcessColumn.name.sortAfterClick(current: .cpu, ascending: false) == (.name, true))
    }

    // MARK: Cell content

    func testCPUToneThresholdsMatchPreviousTable() {
        XCTAssertEqual(ProcessColumn.cpu.content(for: item(cpu: 20)).tone, .primary)
        XCTAssertEqual(ProcessColumn.cpu.content(for: item(cpu: 20.1)).tone, .yellow)
        XCTAssertEqual(ProcessColumn.cpu.content(for: item(cpu: 50.1)).tone, .orange)
        XCTAssertEqual(ProcessColumn.cpu.content(for: item(cpu: 80.1)).tone, .red)
        XCTAssertEqual(ProcessColumn.cpuTotal.content(for: item(cpuTotal: 5.5)).tone, .orange)
        XCTAssertEqual(ProcessColumn.energy.content(for: item(energy: 8.5)).tone, .yellow)
    }

    func testFormatsFigures() {
        let p = item(pid: 89435, cpu: 25.54, cpuTotal: 3.184, energy: 25.6)
        XCTAssertEqual(ProcessColumn.pid.content(for: p).text, "89435")
        XCTAssertEqual(ProcessColumn.cpu.content(for: p).text, "25.5%")
        XCTAssertEqual(ProcessColumn.cpuTotal.content(for: p).text, "3.18%")
        XCTAssertEqual(ProcessColumn.energy.content(for: p).text, "25.6")
        XCTAssertEqual(ProcessColumn.memory.content(for: p).text, formatBytes(Int64(1_000_000)))
        XCTAssertEqual(ProcessColumn.resident.content(for: p).text, formatBytes(Int64(2_000_000)))
        XCTAssertTrue(ProcessColumn.memory.content(for: p).monospacedDigits)
        XCTAssertFalse(ProcessColumn.user.content(for: p).monospacedDigits)
    }

    func testZeroCompressedAndIdleDiskShowSecondaryDash() {
        for column in [ProcessColumn.compressed, .disk] {
            let content = column.content(for: item())
            XCTAssertEqual(content.text, "—")
            XCTAssertEqual(content.tone, .secondary)
        }
        XCTAssertEqual(ProcessColumn.compressed.content(for: item(compressed: 5_000_000)).text,
                       formatBytes(Int64(5_000_000)))
        XCTAssertNotEqual(ProcessColumn.disk.content(for: item(diskRead: 2048)).text, "—")
    }

    func testNameShowsAppIconOrPlaceholderSymbol() {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        XCTAssertEqual(ProcessColumn.name.content(for: item(icon: icon)).leading, .icon(icon))
        XCTAssertEqual(ProcessColumn.name.content(for: item()).leading, .symbol("app.dashed", .secondary))
        // Icons compare by identity, so an equal-looking copy still counts as a change.
        XCTAssertNotEqual(ProcessCellContent.Leading.icon(icon), .icon(NSImage(size: icon.size)))
    }

    func testStateShowsTintedSymbol() {
        let running = ProcessColumn.state.content(for: item(state: .running))
        XCTAssertEqual(running.text, "Running")
        XCTAssertEqual(running.leading, .symbol(ProcessState.running.symbol, .green))
        XCTAssertEqual(ProcessColumn.tone(for: .zombie), .red)
        XCTAssertEqual(ProcessColumn.tone(for: .sleeping), .secondary)
    }

    // MARK: Update detection

    func testRowsDifferDetectsValueOrderAndIdentityChanges() {
        let a = item(pid: 1), b = item(pid: 2)
        let differ = ProcessTableView.Coordinator.rowsDiffer
        XCTAssertFalse(differ([a, b], [a, b]))
        XCTAssertTrue(differ([a, b], [b, a]))                         // re-sorted
        XCTAssertTrue(differ([a, b], [a]))                            // process exited
        XCTAssertTrue(differ([a, b], [a, item(pid: 2, cpu: 9)]))      // figure changed
        XCTAssertTrue(differ([a, b], [a, item(pid: 2, name: "new")])) // PID reused
        XCTAssertTrue(differ([a, b], [a, item(pid: 2, start: Date(timeIntervalSince1970: 2_000))]))
    }
}

final class ProcessFilterSortTests: XCTestCase {

    private func p(_ pid: pid_t, _ name: String, cpu: Double = 0, memory: Int64 = 0, compressed: Int64 = 0) -> ProcessItem {
        ProcessItem(pid: pid, name: name, user: "ariel", cpuUsage: cpu, cpuUsageTotal: cpu / 8, memoryUsage: memory,
                    threadCount: 1, state: .sleeping, icon: nil, parentPid: 1, startTime: nil,
                    compressedMemory: compressed)
    }

    private lazy var sample = [
        p(1, "launchd"),
        p(300, "Finder", cpu: 12, memory: 200_000_000, compressed: 50_000_000),
        p(200, "Teams", cpu: 3, memory: 900_000_000, compressed: 800_000_000),
        p(400, "zsh", cpu: 40, memory: 5_000_000),
    ]

    private func pids(_ column: ProcessSortColumn, ascending: Bool, search: String = "") -> [pid_t] {
        ProcessView.filterAndSort(sample, search: search, by: column, ascending: ascending).map(\.pid)
    }

    func testFigureColumnsSortBothWays() {
        XCTAssertEqual(pids(.compressed, ascending: false), [200, 300, 1, 400])   // ties fall back to PID
        XCTAssertEqual(pids(.compressed, ascending: true), [1, 400, 300, 200])
        XCTAssertEqual(pids(.memory, ascending: false), [200, 300, 400, 1])
        XCTAssertEqual(pids(.cpu, ascending: false), [400, 300, 200, 1])
    }

    func testNameSortIsCaseInsensitive() {
        XCTAssertEqual(pids(.name, ascending: true), [300, 1, 200, 400])
        XCTAssertEqual(pids(.name, ascending: false), [400, 200, 1, 300])
    }

    func testSearchMatchesNameOrPid() {
        XCTAssertEqual(pids(.pid, ascending: true, search: "fin"), [300])
        XCTAssertEqual(pids(.pid, ascending: true, search: "40"), [400])
        XCTAssertEqual(pids(.pid, ascending: true, search: ""), [1, 200, 300, 400])
    }
}

/// Drives the real coordinator against a real (window-less) NSTableView.
final class ProcessTableCoordinatorTests: XCTestCase {

    private final class Harness {
        var selection: Set<pid_t> = []
        var sort: (ProcessSortColumn, Bool) = (.cpu, false)
        var opened: [pid_t] = []
        var terminated: [pid_t] = []
        var deleteKeyPresses = 0
        let table = ProcessNSTableView()
        var coordinator: ProcessTableView.Coordinator!

        func view(_ rows: [ProcessItem]) -> ProcessTableView {
            ProcessTableView(
                processes: rows,
                selection: Binding(get: { self.selection }, set: { self.selection = $0 }),
                sortColumn: sort.0, sortAscending: sort.1,
                onSort: { self.sort = ($0, $1) },
                actions: ProcessTableActions(open: { self.opened.append($0.pid) },
                                             terminate: { self.terminated.append($0.pid) },
                                             forceKill: { _ in }, suspend: { _ in }, resume: { _ in },
                                             deleteKey: { self.deleteKeyPresses += 1 }))
        }

        /// Mirrors makeNSView + updateNSView.
        func show(_ rows: [ProcessItem]) {
            let view = view(rows)
            if coordinator == nil {
                coordinator = view.makeCoordinator()
                for column in ProcessColumn.allCases {
                    table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue)))
                }
                table.dataSource = coordinator
                table.delegate = coordinator
                table.onDelete = { self.deleteKeyPresses += 1 }
                coordinator.tableView = table
            }
            coordinator.parent = view
            coordinator.update()
        }
    }

    private func item(_ pid: pid_t, _ name: String) -> ProcessItem {
        ProcessItem(pid: pid, name: name, user: "ariel", cpuUsage: 0, cpuUsageTotal: 0, memoryUsage: 0,
                    threadCount: 1, state: .sleeping, icon: nil, parentPid: 1, startTime: nil)
    }

    @MainActor
    func testSelectionFollowsTheProcessWhenRowsReorder() {
        let h = Harness()
        let a = item(10, "a"), b = item(20, "b"), c = item(30, "c")
        h.show([a, b, c])
        XCTAssertEqual(h.table.numberOfRows, 3, "first load must not double the row count")

        h.table.selectRowIndexes([1], byExtendingSelection: false)      // user clicks "b"
        XCTAssertEqual(h.selection, [20])

        h.show([c, a, b])                                                // re-sorted by a refresh
        XCTAssertEqual(h.table.selectedRowIndexes, [2])
        XCTAssertEqual(h.selection, [20], "syncing the table must not write back into the binding")

        h.show([c, a])                                                   // "b" exited
        XCTAssertEqual(h.table.numberOfRows, 2)
        XCTAssertTrue(h.table.selectedRowIndexes.isEmpty)
    }

    @MainActor
    func testHeaderClickReportsNextSort() {
        let h = Harness()
        h.show([item(1, "a")])
        let memory = h.table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("memory"))!
        h.coordinator.tableView(h.table, didClick: memory)
        XCTAssertTrue(h.sort == (.memory, false))
        h.show([item(1, "a")])                                           // SwiftUI re-renders with the new sort
        h.coordinator.tableView(h.table, didClick: memory)
        XCTAssertTrue(h.sort == (.memory, true))
    }

    @MainActor
    func testContextMenuUsesSelectedRowWithoutRightClick() throws {
        let h = Harness()
        h.show([item(10, "a"), item(20, "b")])

        let empty = NSMenu()
        h.coordinator.menuNeedsUpdate(empty)
        XCTAssertTrue(empty.items.isEmpty, "no click and no selection: nothing to act on")

        h.table.selectRowIndexes([1], byExtendingSelection: false)
        let menu = NSMenu()
        h.coordinator.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.map(\.title),
                       ["Get Info (⌘I)", "Terminate (⌫)", "Force Kill (⌘⌫)", "Suspend", "Resume", "Copy PID"])

        for title in ["Get Info (⌘I)", "Terminate (⌫)"] {
            let entry = try XCTUnwrap(menu.items.first { $0.title == title })
            _ = (entry.target as? NSObject)?.perform(entry.action, with: entry)
        }
        XCTAssertEqual(h.opened, [20])
        XCTAssertEqual(h.terminated, [20])
    }

    @MainActor
    func testDeleteKeyTriggersTerminateButCommandDeleteDoesNot() throws {
        let h = Harness()
        h.show([item(1, "a")])
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                           windowNumber: 0, context: nil, characters: "\u{8}",
                                           charactersIgnoringModifiers: "\u{8}", isARepeat: false, keyCode: code))
        }
        h.table.keyDown(with: try key(51, []))
        h.table.keyDown(with: try key(117, [.function]))                 // forward delete
        XCTAssertEqual(h.deleteKeyPresses, 2)
        h.table.keyDown(with: try key(51, [.command]))                   // ⌘⌫ belongs to Force Kill
        XCTAssertEqual(h.deleteKeyPresses, 2)
    }
}
