import AppKit
import ApplicationServices
import CoreServices
import Foundation

enum PermissionState: Equatable, Sendable {
    case granted
    case denied
    case unknown

    var label: String {
        switch self {
        case .granted: "Granted"
        case .denied: "Not granted"
        case .unknown: "Unknown"
        }
    }
}

struct PermissionSnapshot: Equatable, Sendable {
    let accessibility: PermissionState
    let appleEventsSafari: PermissionState
    let defaultBrowser: PermissionState
    let defaultBrowserBundleIdentifier: String?

    var canOpenCommandPalette: Bool { true }

    var canAutomateSafariTabs: Bool {
        appleEventsSafari == .granted
    }

    var canSwitchProfilesOrMenus: Bool {
        appleEventsSafari == .granted && accessibility == .granted
    }
}

@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    nonisolated static let arklikeBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.arklike.app"

    @Published private(set) var snapshot: PermissionSnapshot
    @Published private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?

    private init() {
        snapshot = PermissionSnapshot(
            accessibility: .unknown,
            appleEventsSafari: .unknown,
            defaultBrowser: .unknown,
            defaultBrowserBundleIdentifier: nil
        )
    }

    func refresh() {
        refreshAsync()
    }

    func refreshAsync() {
        refreshTask?.cancel()
        isRefreshing = true
        refreshTask = Task.detached(priority: .utility) {
            let snapshot = PerformanceTimer.measure("permission snapshot") {
                Self.makeSnapshot()
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                Self.shared.snapshot = snapshot
                Self.shared.isRefreshing = false
            }
        }
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAsync()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            refreshAsync()
        }
    }

    func requestAppleEventsPermissionForSafari() {
        Task.detached(priority: .userInitiated) {
            _ = Self.appleEventsAuthorizationStatusForSafari(promptIfNeeded: true)
            await MainActor.run {
                Self.shared.refreshAsync()
            }
        }
    }

    func openAccessibilitySettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openAutomationSettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    func openFullDiskAccessSettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    func setAsDefaultBrowser() {
        LSSetDefaultHandlerForURLScheme("http" as CFString, Self.arklikeBundleIdentifier as CFString)
        LSSetDefaultHandlerForURLScheme("https" as CFString, Self.arklikeBundleIdentifier as CFString)
        refreshAsync()
    }

    func openDefaultBrowserSettings() {
        if !openSettingsURL("x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            _ = openSettingsURL("x-apple.systempreferences:")
        }
    }

    @discardableResult
    private func openSettingsURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return NSWorkspace.shared.open(url)
    }

    nonisolated private static func makeSnapshot() -> PermissionSnapshot {
        let defaultBrowserBundleIdentifier = defaultBrowserBundleIdentifier(for: "http")
        let isDefaultBrowser = defaultBrowserBundleIdentifier == arklikeBundleIdentifier

        return PermissionSnapshot(
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            appleEventsSafari: appleEventsAuthorizationStatusForSafari(promptIfNeeded: false),
            defaultBrowser: isDefaultBrowser ? .granted : .denied,
            defaultBrowserBundleIdentifier: defaultBrowserBundleIdentifier
        )
    }

    nonisolated private static func defaultBrowserBundleIdentifier(for scheme: String) -> String? {
        guard let url = URL(string: "\(scheme)://example.com"),
              let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return nil
        }
        return Bundle(url: applicationURL)?.bundleIdentifier
    }

    nonisolated private static func appleEventsAuthorizationStatusForSafari(promptIfNeeded: Bool) -> PermissionState {
        let safariBundleIdentifier = "com.apple.Safari"
        var target = AEAddressDesc()
        let createStatus = safariBundleIdentifier.withCString { pointer in
            AECreateDesc(
                typeApplicationBundleID,
                pointer,
                safariBundleIdentifier.utf8.count,
                &target
            )
        }

        guard createStatus == noErr else {
            return .unknown
        }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            typeWildCard,
            typeWildCard,
            promptIfNeeded
        )

        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .denied
        default:
            return .unknown
        }
    }
}

#if DEBUG
extension PermissionsManager {
    func applyPreviewSnapshot(_ snapshot: PermissionSnapshot) {
        self.snapshot = snapshot
    }
}
#endif
