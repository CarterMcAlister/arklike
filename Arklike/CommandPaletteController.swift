import AppKit
import SwiftUI

@MainActor
final class CommandPaletteController: ObservableObject {
    static let shared = CommandPaletteController()

    @Published var query: String = "" {
        didSet { refreshItems() }
    }
    @Published private(set) var items: [CommandPaletteItem] = []
    @Published var selectedIndex: Int = 0

    private var panel: NSPanel?
    private var recentURLs: [URL] = []
    private let providers: [CommandPaletteProviding] = [
        SearchShortcutCommandProvider(),
        BasicURLSearchProvider(),
        SafariTabCommandProvider(),
        ProfileCommandProvider(),
        TrafficRuleCommandProvider(),
        RecentURLCommandProvider(),
        SettingsCommandProvider()
    ]

    private init() {
        refreshItems()
    }

    func show() {
        query = ""
        refreshItems()
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel: panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    func moveSelection(delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    func performSelected() {
        guard items.indices.contains(selectedIndex) else { return }
        perform(items[selectedIndex])
    }

    func perform(_ item: CommandPaletteItem) {
        switch item.action {
        case .openURL(let url):
            remember(url)
            let preferredWindowId = FrontmostSafariMonitor.shared.activeWindowForSafariAction()?.safariWindowId
            _ = SafariAutomation.shared.openURLInNewTab(url, preferredWindowId: preferredWindowId)
            dismiss()
        case .search(let query):
            if let url = SearchEngineService.shared.searchURL(for: query) {
                remember(url)
                let preferredWindowId = FrontmostSafariMonitor.shared.activeWindowForSafariAction()?.safariWindowId
                _ = SafariAutomation.shared.openURLInNewTab(url, preferredWindowId: preferredWindowId)
            }
            dismiss()
        case .switchToSafariTab(let windowId, let tabIndex):
            if let windowId, let tabIndex {
                _ = SafariAutomation.shared.activateTab(windowId: windowId, tabIndex: tabIndex)
            } else if let windowId {
                _ = SafariAutomation.shared.activateWindow(windowId: windowId)
            }
            dismiss()
        case .openProfile:
            dismiss()
        case .showTrafficRule:
            break
        case .openSettings:
            dismiss()
            SettingsWindowController.shared.show()
        case .noop:
            break
        }
    }

    private func refreshItems() {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = CommandPaletteContext(
            safariSnapshot: FrontmostSafariMonitor.shared.snapshot,
            recentURLs: recentURLs
        )
        items = providers
            .flatMap { provider in
                provider.items(for: normalizedQuery, context: context)
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        selectedIndex = min(selectedIndex, max(items.count - 1, 0))
    }

    private func remember(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        recentURLs = Array(recentURLs.prefix(50))
    }

    private func makePanel() -> NSPanel {
        let root = CommandPaletteView(controller: self)
        let hosting = NSHostingController(rootView: root)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Arklike Command Palette"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting
        return panel
    }

    private func position(panel: NSPanel) {
        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = targetScreen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 100
        )
        panel.setFrameOrigin(origin)
    }
}

extension SettingsDestination: CaseIterable {
    static var allCases: [SettingsDestination] {
        [.general, .shortcuts, .profiles, .commandPalette, .trafficControl, .permissions]
    }
}
