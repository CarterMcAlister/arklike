import AppKit
import ApplicationServices
import Combine
import Foundation

struct SafariWindowContext: Equatable, Sendable {
    let processIdentifier: pid_t
    let safariWindowId: Int?
    let accessibilityWindowNumber: Int?
    let title: String?
    let profileHint: String?
    let center: CGPoint?
    let source: Source
    let observedAt: Date

    enum Source: String, Sendable {
        case accessibilityFocusedWindow
        case appleScriptWindowEnumeration
        case unavailable
    }
}

struct FrontmostSafariSnapshot: Equatable, Sendable {
    let isSafariFrontmost: Bool
    let frontmostBundleIdentifier: String?
    let safariProcessIdentifier: pid_t?
    let activeWindow: SafariWindowContext?
    let lastActiveSafariWindow: SafariWindowContext?
    let shortcutOverridesEnabled: Bool
    let commandPaletteShortcutEnabled: Bool
    let copyURLShortcutEnabled: Bool
    let sidebarShortcutEnabled: Bool
    let profileShortcutsEnabled: Bool

    var canOverrideSafariShortcuts: Bool {
        isSafariFrontmost && shortcutOverridesEnabled
    }

    var canOpenCommandPalette: Bool {
        canOverrideSafariShortcuts && commandPaletteShortcutEnabled
    }

    var canCopyCurrentURL: Bool {
        canOverrideSafariShortcuts && copyURLShortcutEnabled
    }

    var canToggleSidebar: Bool {
        canOverrideSafariShortcuts && sidebarShortcutEnabled
    }

    var canUseProfileShortcuts: Bool {
        canOverrideSafariShortcuts && profileShortcutsEnabled
    }

    @MainActor
    static func initial(settings: AppSettings) -> FrontmostSafariSnapshot {
        FrontmostSafariSnapshot(
            isSafariFrontmost: false,
            frontmostBundleIdentifier: nil,
            safariProcessIdentifier: nil,
            activeWindow: nil,
            lastActiveSafariWindow: nil,
            shortcutOverridesEnabled: settings.safariShortcutOverridesEnabled,
            commandPaletteShortcutEnabled: settings.commandPaletteShortcutEnabled,
            copyURLShortcutEnabled: settings.copyURLShortcutEnabled,
            sidebarShortcutEnabled: settings.sidebarShortcutEnabled,
            profileShortcutsEnabled: settings.profileShortcutsEnabled
        )
    }
}

@MainActor
final class FrontmostSafariMonitor: ObservableObject {
    static let shared = FrontmostSafariMonitor()

    nonisolated static let safariBundleIdentifier = "com.apple.Safari"

    @Published private(set) var snapshot: FrontmostSafariSnapshot

    private let workspace: NSWorkspace
    private let settings: AppSettings
    private var activationObserver: NSObjectProtocol?
    private var settingsCancellable: AnyCancellable?
    private var axObserver: AXObserver?
    private var observedSafariPID: pid_t?
    private var refreshScheduleTask: Task<Void, Never>?
    private var activeWindowRefreshTask: Task<Void, Never>?
    private var windowIDResolutionTask: Task<Void, Never>?
    private var isStarted = false

    private init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        self.settings = AppSettings.shared
        snapshot = .initial(settings: AppSettings.shared)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleRefresh(reason: "workspace activation", delay: 0)
            }
        }

        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.scheduleRefresh(reason: "settings changed", delay: 0)
            }
        }

        scheduleRefresh(reason: "start", delay: 0)
    }

    func scheduleRefresh(reason: String = "manual", delay: TimeInterval = 0.05) {
        refreshScheduleTask?.cancel()
        refreshScheduleTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.refresh(reason: reason)
            }
        }
    }

    func refresh(reason: String = "manual") {
        PerformanceTimer.measure("frontmost safari monitor refresh") {
            let frontmostApp = workspace.frontmostApplication
            let frontmostBundleIdentifier = frontmostApp?.bundleIdentifier
            let isSafariFrontmost = frontmostBundleIdentifier == Self.safariBundleIdentifier
            let safariPID = isSafariFrontmost ? frontmostApp?.processIdentifier : nil

            if let safariPID {
                configureAXObserverIfNeeded(for: safariPID)
                let activeWindow = snapshot.activeWindow?.processIdentifier == safariPID ? snapshot.activeWindow : nil
                publish(
                    isSafariFrontmost: true,
                    frontmostBundleIdentifier: frontmostBundleIdentifier,
                    safariProcessIdentifier: safariPID,
                    activeWindow: activeWindow
                )
                scheduleActiveWindowRefresh(pid: safariPID, frontmostBundleIdentifier: frontmostBundleIdentifier)
            } else {
                stopAXObserver()
                publish(
                    isSafariFrontmost: false,
                    frontmostBundleIdentifier: frontmostBundleIdentifier,
                    safariProcessIdentifier: nil,
                    activeWindow: nil
                )
            }
        }
    }

    func activeWindowForSafariAction() -> SafariWindowContext? {
        snapshot.activeWindow
    }

    func lastActiveWindowForSafariAction() -> SafariWindowContext? {
        lastActiveSafariWindow(from: snapshot.activeWindow) ?? snapshot.lastActiveSafariWindow
    }

    private func publish(
        isSafariFrontmost: Bool,
        frontmostBundleIdentifier: String?,
        safariProcessIdentifier: pid_t?,
        activeWindow: SafariWindowContext?
    ) {
        let nextLastActiveSafariWindow = lastActiveSafariWindow(from: activeWindow) ?? snapshot.lastActiveSafariWindow
        snapshot = FrontmostSafariSnapshot(
            isSafariFrontmost: isSafariFrontmost,
            frontmostBundleIdentifier: frontmostBundleIdentifier,
            safariProcessIdentifier: safariProcessIdentifier,
            activeWindow: activeWindow,
            lastActiveSafariWindow: nextLastActiveSafariWindow,
            shortcutOverridesEnabled: settings.safariShortcutOverridesEnabled,
            commandPaletteShortcutEnabled: settings.commandPaletteShortcutEnabled,
            copyURLShortcutEnabled: settings.copyURLShortcutEnabled,
            sidebarShortcutEnabled: settings.sidebarShortcutEnabled,
            profileShortcutsEnabled: settings.profileShortcutsEnabled
        )
    }

    private func lastActiveSafariWindow(from activeWindow: SafariWindowContext?) -> SafariWindowContext? {
        guard let activeWindow else { return nil }
        if activeWindow.safariWindowId != nil || activeWindow.accessibilityWindowNumber != nil || activeWindow.title?.isEmpty == false {
            return activeWindow
        }
        return nil
    }

    private func configureAXObserverIfNeeded(for pid: pid_t) {
        guard observedSafariPID != pid || axObserver == nil else { return }
        stopAXObserver()

        var newObserver: AXObserver?
        let status = AXObserverCreate(pid, axObserverCallback, &newObserver)
        guard status == .success, let newObserver else { return }

        let safariAppElement = AXUIElementCreateApplication(pid)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let notifications = [
            kAXFocusedWindowChangedNotification as String,
            kAXMainWindowChangedNotification as String,
            kAXWindowMovedNotification as String,
            kAXWindowResizedNotification as String
        ]

        var didRegisterNotification = false
        for notification in notifications {
            let addStatus = AXObserverAddNotification(
                newObserver,
                safariAppElement,
                notification as CFString,
                refcon
            )
            if addStatus == .success || addStatus == .notificationAlreadyRegistered {
                didRegisterNotification = true
            }
        }

        guard didRegisterNotification else { return }

        axObserver = newObserver
        observedSafariPID = pid
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )
    }

    private func stopAXObserver() {
        if let axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(axObserver),
                .commonModes
            )
        }
        activeWindowRefreshTask?.cancel()
        windowIDResolutionTask?.cancel()
        activeWindowRefreshTask = nil
        windowIDResolutionTask = nil
        axObserver = nil
        observedSafariPID = nil
    }

    fileprivate func handleAXNotification(_ notification: String) {
        scheduleRefresh(reason: "AX notification: \(notification)", delay: 0.03)
    }

    private func scheduleActiveWindowRefresh(pid: pid_t, frontmostBundleIdentifier: String?) {
        activeWindowRefreshTask?.cancel()
        let previousWindow = snapshot.activeWindow
        activeWindowRefreshTask = Task.detached(priority: .utility) { [previousWindow] in
            let activeWindow = PerformanceTimer.measure("frontmost safari AX active window") {
                SafariActiveWindowContextWorker.activeSafariWindowContext(pid: pid, previousWindow: previousWindow)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let monitor = Self.shared
                guard monitor.snapshot.safariProcessIdentifier == pid else { return }
                monitor.publish(
                    isSafariFrontmost: true,
                    frontmostBundleIdentifier: frontmostBundleIdentifier,
                    safariProcessIdentifier: pid,
                    activeWindow: activeWindow
                )
                if let activeWindow {
                    monitor.scheduleWindowIDResolution(pid: pid, title: activeWindow.title)
                }
            }
        }
    }

    private func scheduleWindowIDResolution(pid: pid_t, title: String?) {
        windowIDResolutionTask?.cancel()
        windowIDResolutionTask = Task { [weak self] in
            let resolvedID = await Task.detached(priority: .utility) {
                SafariWindowIDResolver.resolve(title: title)
            }.value

            await MainActor.run {
                guard let self else { return }
                guard self.snapshot.safariProcessIdentifier == pid else { return }
                guard let activeWindow = self.snapshot.activeWindow else { return }
                guard activeWindow.safariWindowId != resolvedID else { return }

                let updatedWindow = SafariWindowContext(
                    processIdentifier: activeWindow.processIdentifier,
                    safariWindowId: resolvedID,
                    accessibilityWindowNumber: activeWindow.accessibilityWindowNumber,
                    title: activeWindow.title,
                    profileHint: activeWindow.profileHint,
                    center: activeWindow.center,
                    source: activeWindow.source,
                    observedAt: activeWindow.observedAt
                )

                self.publish(
                    isSafariFrontmost: true,
                    frontmostBundleIdentifier: self.snapshot.frontmostBundleIdentifier,
                    safariProcessIdentifier: pid,
                    activeWindow: updatedWindow
                )
            }
        }
    }

}

private enum SafariActiveWindowContextWorker {
    static func activeSafariWindowContext(pid: pid_t, previousWindow: SafariWindowContext?) -> SafariWindowContext? {
        if var axContext = accessibilityFocusedWindowContext(pid: pid) {
            if let previousWindow,
               previousWindow.processIdentifier == pid,
               previousWindow.title == axContext.title,
               axContext.safariWindowId == nil {
                axContext = SafariWindowContext(
                    processIdentifier: axContext.processIdentifier,
                    safariWindowId: previousWindow.safariWindowId,
                    accessibilityWindowNumber: axContext.accessibilityWindowNumber,
                    title: axContext.title,
                    profileHint: axContext.profileHint,
                    center: axContext.center,
                    source: axContext.source,
                    observedAt: axContext.observedAt
                )
            }
            return axContext
        }

        return SafariWindowContext(
            processIdentifier: pid,
            safariWindowId: nil,
            accessibilityWindowNumber: nil,
            title: nil,
            profileHint: nil,
            center: nil,
            source: .unavailable,
            observedAt: Date()
        )
    }

    private static func accessibilityFocusedWindowContext(pid: pid_t) -> SafariWindowContext? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        guard focusedStatus == .success, let focusedWindowValue else { return nil }

        let windowElement = focusedWindowValue as! AXUIElement
        let title = stringAttribute(kAXTitleAttribute, from: windowElement)
        let axWindowNumber = intAttribute("AXWindowNumber", from: windowElement)
        let center = accessibilityWindowCenterInAppKitCoordinates(from: windowElement)

        return SafariWindowContext(
            processIdentifier: pid,
            safariWindowId: nil,
            accessibilityWindowNumber: axWindowNumber,
            title: title,
            profileHint: profileHint(from: title),
            center: center,
            source: .accessibilityFocusedWindow,
            observedAt: Date()
        )
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success else { return nil }
        return value as? String
    }

    private static func intAttribute(_ attribute: String, from element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success, let value else { return nil }

        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private static func accessibilityWindowCenterInAppKitCoordinates(from element: AXUIElement) -> CGPoint? {
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

        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            let displayBounds = CGDisplayBounds(displayID)
            guard displayBounds.contains(quartzCenter) else { continue }

            let xWithinDisplay = quartzCenter.x - displayBounds.minX
            let yWithinDisplayFromTop = quartzCenter.y - displayBounds.minY
            return CGPoint(
                x: screen.frame.minX + xWithinDisplay,
                y: screen.frame.maxY - yWithinDisplayFromTop
            )
        }

        if let screen = NSScreen.main {
            return CGPoint(
                x: screen.frame.minX + quartzCenter.x,
                y: screen.frame.maxY - quartzCenter.y
            )
        }
        return nil
    }

    private static func profileHint(from title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        let bracketPatterns: [(Character, Character)] = [("[", "]"), ("(", ")")]
        for (open, close) in bracketPatterns {
            guard let start = title.firstIndex(of: open),
                  let end = title[start...].firstIndex(of: close),
                  start < end else { continue }
            let candidate = title[title.index(after: start)..<end]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty { return candidate }
        }
        return nil
    }
}

#if DEBUG
extension FrontmostSafariMonitor {
    func applyPreviewSnapshot(_ snapshot: FrontmostSafariSnapshot) {
        stopAXObserver()
        self.snapshot = snapshot
    }
}
#endif

private let axObserverCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else { return }
    let monitor = Unmanaged<FrontmostSafariMonitor>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    let notificationName = notification as String
    Task { @MainActor in
        monitor.handleAXNotification(notificationName)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
