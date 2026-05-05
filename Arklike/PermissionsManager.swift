import AppKit
import ApplicationServices
import CoreServices
import Foundation

enum PermissionState: Equatable {
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

struct PermissionSnapshot: Equatable {
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

    static let arklikeBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.arklike.app"

    @Published private(set) var snapshot: PermissionSnapshot

    private init() {
        snapshot = Self.makeSnapshot()
    }

    func refresh() {
        snapshot = Self.makeSnapshot()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            refresh()
        }
    }

    func requestAppleEventsPermissionForSafari() {
        _ = Self.appleEventsAuthorizationStatusForSafari(promptIfNeeded: true)
        refresh()
    }

    func openAccessibilitySettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openAutomationSettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    func setAsDefaultBrowser() {
        LSSetDefaultHandlerForURLScheme("http" as CFString, Self.arklikeBundleIdentifier as CFString)
        LSSetDefaultHandlerForURLScheme("https" as CFString, Self.arklikeBundleIdentifier as CFString)
        refresh()
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

    private static func makeSnapshot() -> PermissionSnapshot {
        let defaultBrowserBundleIdentifier = defaultBrowserBundleIdentifier(for: "http")
        let isDefaultBrowser = defaultBrowserBundleIdentifier == arklikeBundleIdentifier

        return PermissionSnapshot(
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            appleEventsSafari: appleEventsAuthorizationStatusForSafari(promptIfNeeded: false),
            defaultBrowser: isDefaultBrowser ? .granted : .denied,
            defaultBrowserBundleIdentifier: defaultBrowserBundleIdentifier
        )
    }

    private static func defaultBrowserBundleIdentifier(for scheme: String) -> String? {
        guard let url = URL(string: "\(scheme)://example.com"),
              let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return nil
        }
        return Bundle(url: applicationURL)?.bundleIdentifier
    }

    private static func appleEventsAuthorizationStatusForSafari(promptIfNeeded: Bool) -> PermissionState {
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
