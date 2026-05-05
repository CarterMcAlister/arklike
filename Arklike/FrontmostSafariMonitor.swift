import AppKit
import ApplicationServices
import Combine
import Foundation

struct SafariWindowContext: Equatable {
    let processIdentifier: pid_t
    let safariWindowId: Int?
    let accessibilityWindowNumber: Int?
    let title: String?
    let profileHint: String?
    let source: Source
    let observedAt: Date

    enum Source: String {
        case accessibilityFocusedWindow
        case appleScriptWindowEnumeration
        case unavailable
    }
}

struct FrontmostSafariSnapshot: Equatable {
    let isSafariFrontmost: Bool
    let frontmostBundleIdentifier: String?
    let safariProcessIdentifier: pid_t?
    let activeWindow: SafariWindowContext?
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

    static let safariBundleIdentifier = "com.apple.Safari"

    @Published private(set) var snapshot: FrontmostSafariSnapshot

    private let workspace: NSWorkspace
    private let settings: AppSettings
    private var activationObserver: NSObjectProtocol?
    private var settingsCancellable: AnyCancellable?
    private var axObserver: AXObserver?
    private var observedSafariPID: pid_t?
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
                self?.refresh(reason: "workspace activation")
            }
        }

        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reason: "settings changed")
            }
        }

        refresh(reason: "start")
    }

    func refresh(reason: String = "manual") {
        let frontmostApp = workspace.frontmostApplication
        let frontmostBundleIdentifier = frontmostApp?.bundleIdentifier
        let isSafariFrontmost = frontmostBundleIdentifier == Self.safariBundleIdentifier
        let safariPID = isSafariFrontmost ? frontmostApp?.processIdentifier : nil

        if let safariPID {
            configureAXObserverIfNeeded(for: safariPID)
            let activeWindow = activeSafariWindowContext(pid: safariPID)
            publish(
                isSafariFrontmost: true,
                frontmostBundleIdentifier: frontmostBundleIdentifier,
                safariProcessIdentifier: safariPID,
                activeWindow: activeWindow
            )
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

    func activeWindowForSafariAction() -> SafariWindowContext? {
        if snapshot.isSafariFrontmost {
            refresh(reason: "action requested")
        }
        return snapshot.activeWindow
    }

    private func publish(
        isSafariFrontmost: Bool,
        frontmostBundleIdentifier: String?,
        safariProcessIdentifier: pid_t?,
        activeWindow: SafariWindowContext?
    ) {
        snapshot = FrontmostSafariSnapshot(
            isSafariFrontmost: isSafariFrontmost,
            frontmostBundleIdentifier: frontmostBundleIdentifier,
            safariProcessIdentifier: safariProcessIdentifier,
            activeWindow: activeWindow,
            shortcutOverridesEnabled: settings.safariShortcutOverridesEnabled,
            commandPaletteShortcutEnabled: settings.commandPaletteShortcutEnabled,
            copyURLShortcutEnabled: settings.copyURLShortcutEnabled,
            sidebarShortcutEnabled: settings.sidebarShortcutEnabled,
            profileShortcutsEnabled: settings.profileShortcutsEnabled
        )
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
        axObserver = nil
        observedSafariPID = nil
    }

    fileprivate func handleAXNotification(_ notification: String) {
        refresh(reason: "AX notification: \(notification)")
    }

    private func activeSafariWindowContext(pid: pid_t) -> SafariWindowContext? {
        if let axContext = accessibilityFocusedWindowContext(pid: pid) {
            if axContext.safariWindowId != nil || axContext.title != nil {
                return axContext
            }
        }

        if let scriptContext = appleScriptEnumeratedFrontWindowContext(pid: pid) {
            return scriptContext
        }

        return SafariWindowContext(
            processIdentifier: pid,
            safariWindowId: nil,
            accessibilityWindowNumber: nil,
            title: nil,
            profileHint: nil,
            source: .unavailable,
            observedAt: Date()
        )
    }

    private func accessibilityFocusedWindowContext(pid: pid_t) -> SafariWindowContext? {
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
        let safariWindowId = appleScriptWindowIdMatching(title: title, axWindowNumber: axWindowNumber)

        return SafariWindowContext(
            processIdentifier: pid,
            safariWindowId: safariWindowId,
            accessibilityWindowNumber: axWindowNumber,
            title: title,
            profileHint: Self.profileHint(from: title),
            source: .accessibilityFocusedWindow,
            observedAt: Date()
        )
    }

    private func appleScriptEnumeratedFrontWindowContext(pid: pid_t) -> SafariWindowContext? {
        guard let firstWindow = appleScriptEnumeratedWindows().first else { return nil }

        return SafariWindowContext(
            processIdentifier: pid,
            safariWindowId: firstWindow.id,
            accessibilityWindowNumber: nil,
            title: firstWindow.title,
            profileHint: Self.profileHint(from: firstWindow.title),
            source: .appleScriptWindowEnumeration,
            observedAt: Date()
        )
    }

    private struct AppleScriptWindowSummary {
        let id: Int
        let title: String?
    }

    private func appleScriptEnumeratedWindows() -> [AppleScriptWindowSummary] {
        let script = """
        tell application "Safari"
            if (count of windows) is 0 then return ""
            set outputLines to {}
            repeat with safariWindow in windows
                set windowIdText to (id of safariWindow) as text
                set windowName to ""
                try
                    set windowName to name of safariWindow
                end try
                set end of outputLines to windowIdText & tab & windowName
            end repeat
            set AppleScript's text item delimiters to linefeed
            set outputText to outputLines as text
            set AppleScript's text item delimiters to ""
            return outputText
        end tell
        """

        guard let output = runAppleScript(script), !output.isEmpty else { return [] }
        return output
            .components(separatedBy: .newlines)
            .compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard let idText = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let id = Int(idText) else { return nil }
                let title = parts.dropFirst().joined(separator: "\t").nilIfEmpty
                return AppleScriptWindowSummary(id: id, title: title)
            }
    }

    private func appleScriptWindowIdMatching(title: String?, axWindowNumber: Int?) -> Int? {
        let windows = appleScriptEnumeratedWindows()
        guard !windows.isEmpty else { return nil }

        // Safari AppleScript does not expose AXWindowNumber. Keep the value in the
        // signature so later OS-specific mapping can be added without changing
        // callers, but prefer exact title matching over blindly using front window.
        _ = axWindowNumber
        if let title, !title.isEmpty,
           let matched = windows.first(where: { $0.title == title }) {
            return matched.id
        }

        return windows.first?.id
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let descriptor = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return descriptor.stringValue
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success else { return nil }
        return value as? String
    }

    private func intAttribute(_ attribute: String, from element: AXUIElement) -> Int? {
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

    private static func profileHint(from title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }

        // Safari does not expose a stable profile identifier. Keep only weak hints
        // that later profile-routing code can compare against user-configured names.
        let bracketPatterns: [(Character, Character)] = [("[", "]"), ("(", ")")]
        for (open, close) in bracketPatterns {
            guard let start = title.firstIndex(of: open),
                  let end = title[start...].firstIndex(of: close),
                  start < end else { continue }
            let candidate = title[title.index(after: start)..<end]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                return candidate
            }
        }

        return nil
    }
}

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
