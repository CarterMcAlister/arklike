import AppKit
import ApplicationServices
import Combine
import SwiftUI

private final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class CommandPaletteController: ObservableObject {
    static let shared = CommandPaletteController()

    let state = CommandPanelState()

    var query: String {
        get { state.query }
        set { updateInputText(newValue) }
    }
    var items: [CommandPaletteItem] { state.suggestions }
    var selectedIndex: Int {
        get { state.selectedIndex }
        set { state.selectedIndex = newValue }
    }

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var dismissEventTap: CFMachPort?
    private var dismissEventTapSource: CFRunLoopSource?
    private var refreshScheduleTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var clipboardTask: Task<Void, Never>?
    private var suggestionGeneration = 0
    private var storeCancellables: Set<AnyCancellable> = []
    private var clipboardURL: URL?
    private var webSuggestions: [String] = []

    private let recentStore = CommandPanelRecentStore.shared
    private let liveTabStore = SafariLiveTabStore.shared
    private let bookmarkStore = SafariBookmarkStore.shared
    private let suggestionComputer = CommandPanelSuggestionComputer()
    private let suggestionManager = CommandPanelSuggestionManager()

    private static let loadingPlaceholderSuggestion = CommandPanelSuggestion(
        id: "placeholder-search-empty",
        title: "Start typing to search or paste a link",
        subtitle: "Suggestions are loading…",
        kind: .search,
        scope: .all,
        representedURL: nil,
        primaryAction: .noop("Enter a query"),
        basePriority: 990
    )

    private init() {
        bindCachedStores()
    }

    func show() {
        PerformanceTimer.measure("command palette show") {
            refreshScheduleTask?.cancel()
            suggestionTask?.cancel()
            clipboardTask?.cancel()
            CommandPanelWebSuggestionService.shared.cancel()

            webSuggestions = []
            clipboardURL = nil
            state.resetForOpen()
            state.setSuggestions([Self.loadingPlaceholderSuggestion])

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
            state.requestInputFocus()

            installKeyMonitor()
            installOutsideClickMonitor()
            installDismissEventTap()
            scheduleRefresh(delay: 0.05)
            scheduleDeferredClipboardRead()
        }
    }

    func dismiss(returnFocusToSafari: Bool = true) {
        refreshScheduleTask?.cancel()
        suggestionTask?.cancel()
        clipboardTask?.cancel()
        CommandPanelWebSuggestionService.shared.cancel()
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

    func updateInputText(_ text: String) {
        state.currentInputText = text
        if state.mode == .search {
            scheduleWebSuggestions(for: state.query)
        }
        scheduleRefresh(delay: 0.035)
    }

    func moveSelection(delta: Int) {
        state.moveSelection(delta: delta)
    }

    func select(index: Int, scrollToSelection: Bool = false) {
        state.select(index: index, scrollToSelection: scrollToSelection)
    }

    func performSelected() {
        guard let item = state.selectedSuggestion else { return }
        perform(item)
    }

    func perform(_ item: CommandPaletteItem) {
        suggestionManager.recordSelection(item, query: state.query)
        switch item.action {
        case .openURL(let url):
            openURL(url, title: item.title)
        case .search(let query):
            let searchText = state.autocompleteAccepted && !state.query.isEmpty ? state.query : query
            searchWeb(searchText)
        case .switchToSafariTab(let windowId, let tabIndex):
            if let windowId, let tabIndex {
                _ = SafariAutomation.shared.activateTab(windowId: windowId, tabIndex: tabIndex)
            } else if let windowId {
                _ = SafariAutomation.shared.activateWindow(windowId: windowId)
            }
            if let url = item.representedURL { remember(url, title: item.title) }
            liveTabStore.scheduleRefresh(after: 0.5)
            dismiss(returnFocusToSafari: false)
        case .openProfile(let number):
            switch SafariProfileManager.shared.switchToProfile(number: number) {
            case .success:
                NotificationHUD.show(title: "Safari Profile", message: "Opened profile \(number).")
            case .failure(let error):
                NotificationHUD.show(title: "Could not open profile \(number)", message: error.localizedDescription)
            }
            dismiss(returnFocusToSafari: false)
        case .showTrafficRule:
            dismiss(returnFocusToSafari: false)
            SettingsWindowController.shared.show(destination: .trafficControl)
        case .openSettings(let destination):
            dismiss(returnFocusToSafari: false)
            SettingsWindowController.shared.show(destination: destination)
        case .copyURL(let url):
            ClipboardService.copy(url.absoluteString)
            NotificationHUD.show(title: "Copied URL", message: url.absoluteString)
            if state.mode == .actions { state.endActions(); refreshItems() }
        case .copyText(let text):
            ClipboardService.copy(text)
            NotificationHUD.show(title: "Copied", message: text)
            if state.mode == .actions { state.endActions(); refreshItems() }
        case .removeRecent(let url):
            recentStore.remove(url: url)
            if state.mode == .actions { state.endActions() }
            refreshItems()
        case .removeSuggestion:
            if state.mode == .actions { state.endActions() }
            refreshItems()
        case .toggleWebSuggestions:
            AppSettings.shared.webSearchSuggestionsEnabled.toggle()
            refreshItems()
        case .toggleDuplicateTabSwitching:
            AppSettings.shared.switchToExistingSafariTabInsteadOfOpeningDuplicate.toggle()
            refreshItems()
        case .clearRecents:
            recentStore.clear()
            refreshItems()
        case .clearSearchHistory:
            CommandPanelSearchHistoryStore.shared.clear()
            refreshItems()
        case .refreshSafariBookmarks:
            bookmarkStore.reload(force: true)
        case .activateScope(let scope):
            state.activeScope = scope == .all ? nil : scope
            state.endScopePicker()
            refreshItems()
        case .acceptAutocomplete(let text):
            state.autocompleteText = text
            state.acceptAutocomplete()
            refreshItems()
        case .noop:
            break
        }
    }

    func performDirectWebSearch() {
        // SupaSidebar only searches accepted autocomplete; otherwise Cmd+Return uses raw typed text.
        searchWeb(state.query)
    }

    func openActionsForSelected() {
        guard state.mode == .search, let selected = state.selectedSuggestion else { return }
        state.beginActions(for: selected)
        refreshItems()
    }

    func acceptAutocomplete() {
        state.acceptAutocomplete()
        refreshItems()
    }

    func rejectAutocomplete() {
        state.rejectAutocomplete()
        refreshItems()
    }

    private func openURL(_ url: URL, title: String? = nil) {
        if AppSettings.shared.switchToExistingSafariTabInsteadOfOpeningDuplicate,
           let tab = liveTabStore.matchingTab(for: url) {
            _ = SafariAutomation.shared.activateTab(windowId: tab.windowId, tabIndex: tab.tabIndex)
        } else {
            let preferredWindowId = FrontmostSafariMonitor.shared.activeWindowForSafariAction()?.safariWindowId
            _ = SafariAutomation.shared.openURLInNewTab(url, preferredWindowId: preferredWindowId)
        }
        remember(url, title: title)
        liveTabStore.scheduleRefresh(after: 0.5)
        dismiss(returnFocusToSafari: false)
    }

    private func searchWeb(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        CommandPanelSearchHistoryStore.shared.record(trimmed)
        if let url = SearchEngineService.shared.searchURL(for: trimmed) {
            openURL(url, title: "Search: \(trimmed)")
        } else {
            dismiss(returnFocusToSafari: false)
        }
    }

    private func refreshItems() {
        startSuggestionCompute()
    }

    private func scheduleRefresh(delay: TimeInterval = 0) {
        refreshScheduleTask?.cancel()
        refreshScheduleTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.panel?.isVisible == true else { return }
                self.startSuggestionCompute()
            }
        }
    }

    private func startSuggestionCompute() {
        suggestionTask?.cancel()
        suggestionGeneration += 1

        let generation = suggestionGeneration
        let input = makeSuggestionInput()
        let computer = suggestionComputer

        suggestionTask = Task(priority: .userInitiated) { [weak self, input, generation, computer] in
            let suggestions = await Task.detached(priority: .userInitiated) {
                PerformanceTimer.measure("command palette suggestion compute") {
                    computer.suggestions(input: input)
                }
            }.value

            await MainActor.run {
                guard let self else { return }
                guard !Task.isCancelled else { return }
                guard self.panel?.isVisible == true else { return }
                guard self.suggestionGeneration == generation else { return }
                self.state.setSuggestions(suggestions)
                self.updateAutocomplete()
            }
        }
    }

    private func scheduleDeferredClipboardRead() {
        clipboardTask?.cancel()
        clipboardTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                guard self.panel?.isVisible == true else { return }
                guard self.state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.clipboardURL = Self.clipboardURLForPanelOpen()
                self.scheduleRefresh(delay: 0)
            }
        }
    }

    private func refreshVisibleItemsOrInvalidateCache() {
        guard panel?.isVisible == true else { return }
        scheduleRefresh(delay: 0)
    }

    private func makeSuggestionInput() -> CommandPanelSuggestionInput {
        CommandPanelSuggestionInput(
            mode: state.mode,
            query: state.query,
            activeScope: state.activeScope,
            scopePickerQuery: state.scopePickerQuery,
            actionSourceSuggestion: state.actionSourceSuggestion,
            recentItems: recentStore.items,
            safariTabs: liveTabStore.tabs,
            safariTabError: liveTabStore.lastError,
            clipboardURL: clipboardURL,
            webSuggestions: webSuggestions,
            bookmarks: bookmarkStore.bookmarks,
            bookmarkError: bookmarkStore.lastError,
            isUsingStaleBookmarkCache: bookmarkStore.isUsingStaleCache,
            profiles: ProfileStore.shared.profiles,
            trafficRules: TrafficRuleStore.shared.rules,
            usageRecords: CommandPanelUsageStore.shared.recordsSnapshot,
            searchHistoryQueries: CommandPanelSearchHistoryStore.shared.queriesSnapshot,
            webSearchSuggestionsEnabled: AppSettings.shared.webSearchSuggestionsEnabled,
            switchToExistingSafariTabInsteadOfOpeningDuplicate: AppSettings.shared.switchToExistingSafariTabInsteadOfOpeningDuplicate
        )
    }

    private func bindCachedStores() {
        liveTabStore.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshVisibleItemsOrInvalidateCache()
            }
        }.store(in: &storeCancellables)

        bookmarkStore.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshVisibleItemsOrInvalidateCache()
            }
        }.store(in: &storeCancellables)

        ProfileStore.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshVisibleItemsOrInvalidateCache()
            }
        }.store(in: &storeCancellables)

        recentStore.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshVisibleItemsOrInvalidateCache()
            }
        }.store(in: &storeCancellables)

        TrafficRuleStore.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshVisibleItemsOrInvalidateCache()
            }
        }.store(in: &storeCancellables)

        AppSettings.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshVisibleItemsOrInvalidateCache()
            }
        }.store(in: &storeCancellables)

        FrontmostSafariMonitor.shared.$snapshot.sink { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                guard self.panel?.isVisible == true else { return }
                if self.panel?.isVisible == true,
                   !snapshot.isSafariFrontmost,
                   snapshot.frontmostBundleIdentifier != Bundle.main.bundleIdentifier {
                    self.dismiss(returnFocusToSafari: false)
                    return
                }
                self.scheduleRefresh(delay: 0)
            }
        }.store(in: &storeCancellables)
    }

    private func updateAutocomplete() {
        guard state.mode == .search else {
            state.autocompleteText = ""
            return
        }
        let trimmed = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !state.autocompleteAccepted else {
            state.autocompleteText = ""
            return
        }
        let candidates = state.suggestions.compactMap { suggestion -> String? in
            switch suggestion.kind {
            case .searchHistory, .webSuggestion:
                suggestion.title
            case .url, .bookmark, .historyOrRecent, .safariTab:
                suggestion.representedURL?.absoluteString ?? suggestion.title
            case .siteShortcut:
                suggestion.title
            default:
                nil
            }
        }
        if let match = candidates.first(where: { $0.count > trimmed.count && $0.lowercased().hasPrefix(trimmed.lowercased()) }) {
            state.autocompleteText = match
        } else {
            state.autocompleteText = ""
        }
    }

    private func scheduleWebSuggestions(for query: String) {
        CommandPanelWebSuggestionService.shared.suggestions(for: query) { [weak self] suggestions in
            guard let self else { return }
            guard self.webSuggestions != suggestions else { return }
            self.webSuggestions = suggestions
            self.scheduleRefresh(delay: 0)
        }
    }

    private func remember(_ url: URL, title: String? = nil) {
        let window = FrontmostSafariMonitor.shared.activeWindowForSafariAction()
        recentStore.record(url: url, title: title, windowId: window?.safariWindowId, profileHint: window?.profileHint)
    }

    private static func clipboardURLForPanelOpen() -> URL? {
        PerformanceTimer.measure("command palette pasteboard read") {
            guard let text = NSPasteboard.general.string(forType: .string) else { return nil }
            if case .url(let url) = URLParser().parse(text) { return url }
            return nil
        }
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
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            switch event.keyCode {
            case 126:
                self.moveSelection(delta: -1)
                return nil
            case 125:
                self.moveSelection(delta: 1)
                return nil
            case 36, 76:
                if flags.contains(.command) {
                    self.performDirectWebSearch()
                } else if flags.contains(.option) {
                    self.openActionsForSelected()
                } else {
                    self.performSelected()
                }
                return nil
            case 53:
                self.handleEscapeKey()
                return nil
            case 48:
                if flags.contains(.shift) {
                    self.state.cycleScope()
                    self.refreshItems()
                    return nil
                }
                if self.state.mode == .search, let scope = CommandPanelSearchScope.matchingKeyword(self.state.query) {
                    self.state.activeScope = scope == .all ? nil : scope
                    self.state.query = ""
                    self.refreshItems()
                    return nil
                }
                return event
            case 51:
                if self.state.mode == .search, self.state.query.isEmpty, self.state.activeScope != nil {
                    self.state.clearScope()
                    self.refreshItems()
                    return nil
                }
                return event
            case 124:
                if !self.state.autocompleteText.isEmpty {
                    self.acceptAutocomplete()
                    return nil
                }
                return event
            case 44:
                if self.state.mode == .search, flags.isEmpty, self.state.query.isEmpty {
                    self.state.beginScopePicker()
                    self.refreshItems()
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func handleEscapeKey() {
        if state.mode == .scopePicker {
            state.endScopePicker()
            refreshItems()
        } else if state.mode == .actions {
            state.endActions()
            refreshItems()
        } else if state.activeScope != nil {
            state.clearScope()
            refreshItems()
        } else {
            dismiss()
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
            (1 << CGEventType.leftMouseDown.rawValue)
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
        let panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 392),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Arklike Command Palette"
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.contentViewController = hosting
        return panel
    }

    private func position(panel: NSPanel) {
        let center = FrontmostSafariMonitor.shared.snapshot.activeWindow?.center
            ?? NSScreen.main.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) }
            ?? NSScreen.screens.first.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) }
        guard let center else { return }

        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2
        ))
    }
}

#if DEBUG
extension CommandPaletteController {
    static func preview(mode: CommandPanelMode = .search) -> CommandPaletteController {
        PreviewFixtures.configureAppState()
        let controller = shared
        controller.webSuggestions = ["swift concurrency", "swiftui command palette"]
        controller.clipboardURL = URL(string: "https://developer.apple.com")
        controller.state.resetForOpen()

        switch mode {
        case .search:
            controller.state.query = "git"
            controller.state.autocompleteText = "github.com"
            controller.state.setSuggestions(PreviewFixtures.commandPaletteSuggestions)
            controller.state.selectedIndex = 0
        case .scopePicker:
            controller.state.beginScopePicker()
            controller.state.scopePickerQuery = "tab"
            controller.state.setSuggestions(CommandPanelSearchScope.allCases.map { scope in
                CommandPanelSuggestion(
                    id: "preview-scope-\(scope.rawValue)",
                    title: scope.title,
                    subtitle: "Limit command palette results to \(scope.title.lowercased())",
                    kind: .scope,
                    scope: scope,
                    representedURL: nil,
                    primaryAction: .activateScope(scope),
                    basePriority: 0
                )
            })
            controller.state.selectedIndex = 2
        case .actions:
            let source = PreviewFixtures.commandPaletteSuggestions[0]
            controller.state.query = "github"
            controller.state.beginActions(for: source)
            controller.state.setSuggestions([
                CommandPanelSuggestion(id: "preview-action-open", title: "Open", subtitle: source.subtitle, kind: .action, scope: nil, iconSystemName: "arrow.up.right.square", representedURL: source.representedURL, primaryAction: source.primaryAction, basePriority: 0),
                CommandPanelSuggestion(id: "preview-action-copy", title: "Copy URL", subtitle: source.representedURL?.absoluteString ?? "", kind: .action, scope: nil, iconSystemName: "doc.on.doc", representedURL: source.representedURL, primaryAction: .copyText(source.representedURL?.absoluteString ?? ""), basePriority: 1),
                CommandPanelSuggestion(id: "preview-action-settings", title: "Open Traffic Control Settings", subtitle: "Edit routing rules", kind: .action, scope: nil, iconSystemName: "gearshape", representedURL: nil, primaryAction: .openSettings(.trafficControl), basePriority: 2)
            ])
            controller.state.selectedIndex = 1
        }

        return controller
    }
}
#endif

private let commandPaletteDismissEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<CommandPaletteController>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated { controller.handleDismissEventTap(event: event, type: type) }
}
