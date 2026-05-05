import AppKit
import ApplicationServices
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
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var dismissEventTap: CFMachPort?
    private var dismissEventTapSource: CFRunLoopSource?
    private var recentURLs: [URL] = []
    private var cachedSafariTabs: [SafariTabSnapshot] = []
    private var tabRefreshWorkItem: DispatchWorkItem?
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
        tabRefreshWorkItem?.cancel()
        cachedSafariTabs = []
        selectedIndex = 0
        query = ""
        refreshItems()

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel: panel)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            panel.makeKey()
        }

        installKeyMonitor()
        installOutsideClickMonitor()
        installDismissEventTap()
        scheduleSafariTabRefresh()
    }

    func dismiss(returnFocusToSafari: Bool = true) {
        tabRefreshWorkItem?.cancel()
        tabRefreshWorkItem = nil
        removeKeyMonitor()
        removeOutsideClickMonitor()
        removeDismissEventTap()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            panel?.orderOut(nil)
        }
        if returnFocusToSafari {
            restoreSafariFocus()
        }
    }

    func moveSelection(delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    func select(index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
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
            dismiss(returnFocusToSafari: false)
        case .search(let query):
            if let url = SearchEngineService.shared.searchURL(for: query) {
                remember(url)
                let preferredWindowId = FrontmostSafariMonitor.shared.activeWindowForSafariAction()?.safariWindowId
                _ = SafariAutomation.shared.openURLInNewTab(url, preferredWindowId: preferredWindowId)
            }
            dismiss(returnFocusToSafari: false)
        case .switchToSafariTab(let windowId, let tabIndex):
            if let windowId, let tabIndex {
                _ = SafariAutomation.shared.activateTab(windowId: windowId, tabIndex: tabIndex)
            } else if let windowId {
                _ = SafariAutomation.shared.activateWindow(windowId: windowId)
            }
            dismiss(returnFocusToSafari: false)
        case .openProfile:
            dismiss(returnFocusToSafari: false)
        case .showTrafficRule:
            break
        case .openSettings:
            dismiss(returnFocusToSafari: false)
            SettingsWindowController.shared.show()
        case .noop:
            break
        }
    }

    private func refreshItems() {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = CommandPaletteContext(
            safariSnapshot: FrontmostSafariMonitor.shared.snapshot,
            recentURLs: recentURLs,
            safariTabs: cachedSafariTabs
        )
        items = providers
            .flatMap { provider in provider.items(for: normalizedQuery, context: context) }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        selectedIndex = min(selectedIndex, max(items.count - 1, 0))
    }

    private func scheduleSafariTabRefresh() {
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.panel?.isVisible == true else { return }
                if case .success(let windows) = SafariAutomation.shared.listWindowsAndTabs() {
                    self.cachedSafariTabs = windows.flatMap(\.tabs)
                    self.refreshItems()
                }
            }
        }
        tabRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func remember(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        recentURLs = Array(recentURLs.prefix(50))
    }

    private func restoreSafariFocus() {
        if let windowId = FrontmostSafariMonitor.shared.snapshot.activeWindow?.safariWindowId {
            _ = SafariAutomation.shared.activateWindow(windowId: windowId)
        } else if let safari = NSRunningApplication.runningApplications(withBundleIdentifier: FrontmostSafariMonitor.safariBundleIdentifier).first {
            safari.activate(options: [.activateAllWindows])
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 126:
                self.moveSelection(delta: -1)
                return nil
            case 125:
                self.moveSelection(delta: 1)
                return nil
            case 36, 76:
                self.performSelected()
                return nil
            case 53:
                self.dismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.dismiss()
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    private func installDismissEventTap() {
        guard dismissEventTap == nil else { return }
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        )
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: commandPaletteDismissEventTapCallback,
            userInfo: refcon
        ) else {
            Diagnostics.shared.log("Could not install command palette dismiss event tap. Accessibility permission may be missing.")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        dismissEventTap = tap
        dismissEventTapSource = source
    }

    private func removeDismissEventTap() {
        if let dismissEventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), dismissEventTapSource, .commonModes) }
        if let dismissEventTap { CFMachPortInvalidate(dismissEventTap) }
        dismissEventTap = nil
        dismissEventTapSource = nil
    }

    fileprivate func handleDismissEventTap(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let dismissEventTap { CGEvent.tapEnable(tap: dismissEventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let panel, panel.isVisible else {
            removeDismissEventTap()
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == 53 {
                dismiss()
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            let point = event.location
            if !panel.frame.contains(point) {
                dismiss()
            }
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func makePanel() -> NSPanel {
        let root = CommandPaletteView(controller: self)
        let hosting = NSHostingController(rootView: root)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 392),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Arklike Command Palette"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.toolbar = nil
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.contentViewController = hosting
        return panel
    }

    private func position(panel: NSPanel) {
        let center = activeSafariWindowCenterInAppKitCoordinates()
            ?? NSScreen.main.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) }
            ?? NSScreen.screens.first.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) }
        guard let center else { return }

        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2
        ))
    }

    private func activeSafariWindowCenterInAppKitCoordinates() -> NSPoint? {
        guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: FrontmostSafariMonitor.safariBundleIdentifier).first else { return nil }
        let appElement = AXUIElementCreateApplication(safari.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let window = windowValue else { return nil }
        let element = window as! AXUIElement
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var quartzOrigin = CGPoint.zero
        var windowSize = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &quartzOrigin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &windowSize) else { return nil }

        let quartzCenter = CGPoint(
            x: quartzOrigin.x + windowSize.width / 2,
            y: quartzOrigin.y + windowSize.height / 2
        )

        // AX window positions use Quartz/display coordinates (top-left origin per
        // display). NSWindow positioning uses AppKit screen coordinates
        // (bottom-left origin). Convert through the display that contains the
        // Safari window center so centering works on every monitor arrangement.
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            let displayBounds = CGDisplayBounds(displayID)
            guard displayBounds.contains(quartzCenter) else { continue }

            let xWithinDisplay = quartzCenter.x - displayBounds.minX
            let yWithinDisplayFromTop = quartzCenter.y - displayBounds.minY
            return NSPoint(
                x: screen.frame.minX + xWithinDisplay,
                y: screen.frame.maxY - yWithinDisplayFromTop
            )
        }

        // Single-display fallback if display matching fails.
        if let screen = NSScreen.main {
            return NSPoint(
                x: screen.frame.minX + quartzCenter.x,
                y: screen.frame.maxY - quartzCenter.y
            )
        }
        return nil
    }
}

extension SettingsDestination: CaseIterable {
    static var allCases: [SettingsDestination] {
        [.general, .shortcuts, .profiles, .commandPalette, .trafficControl, .permissions]
    }
}

private let commandPaletteDismissEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<CommandPaletteController>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated { controller.handleDismissEventTap(event: event, type: type) }
}
