import AppKit

/// Reports whether any TopManager window is actually on screen: the main window,
/// the menu-bar popover or Settings — as opposed to closed, minimized, fully
/// covered, or on another Space.
///
/// Why this exists: on macOS 26 several framework paths leak a little on every
/// view update (SwiftUI `Table` cell updates, AppKit text-cell KVO dependencies,
/// an Observation registrar created inside DesignLibrary). SwiftUI keeps updating
/// a minimized or covered window, so leaving the main window open all day grew
/// the app by several hundred MB. `SystemMonitor` stops publishing while this
/// reports `false`, which confines that growth to the time someone is looking.
@MainActor
final class WindowVisibility {
    static let shared = WindowVisibility()

    private(set) var isAnyWindowVisible = true
    private var onChange: ((Bool) -> Void)?
    private var tokens: [NSObjectProtocol] = []

    private init() {}

    func start(onChange: @escaping (Bool) -> Void) {
        guard tokens.isEmpty else { return }
        self.onChange = onChange

        let names = [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification]
        for name in names {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // willClose arrives while the window is still on screen, so
                // re-check on a later turn, once it is actually gone.
                Task { @MainActor in self?.recompute() }
            })
        }
        recompute()
    }

    private func recompute() {
        let visible = NSApp.windows.contains(where: Self.countsAsVisible)
        guard visible != isAnyWindowVisible else { return }
        isAnyWindowVisible = visible
        onChange?(visible)
    }

    /// The status item's host window is permanently on screen; counting it would
    /// keep the UI publishing forever.
    private static func countsAsVisible(_ window: NSWindow) -> Bool {
        window.isVisible
            && window.occlusionState.contains(.visible)
            && !String(describing: type(of: window)).contains("StatusBarWindow")
    }
}
