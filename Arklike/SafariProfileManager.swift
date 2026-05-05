import AppKit
import ApplicationServices
import Foundation

@MainActor
final class SafariProfileManager {
    static let shared = SafariProfileManager()

    private init() {}

    func switchToProfile(number: Int) -> Result<Void, SafariAutomationError> {
        if ProfileStore.shared.profiles.isEmpty {
            _ = ProfileStore.shared.refreshFromSafari()
        }
        guard let profile = ProfileStore.shared.profile(number: number) else {
            return .failure(.unsupportedState("No named Safari profile was discovered for Ctrl+\(number). Open Safari, then refresh Profiles in Arklike Settings."))
        }
        return switchToProfile(profile)
    }

    func switchToProfile(_ profile: Profile) -> Result<Void, SafariAutomationError> {
        if switchToExistingWindow(for: profile) {
            Diagnostics.shared.log("Switched to existing Safari profile window: \(profile.displayName)")
            return .success(())
        }
        Diagnostics.shared.log("No existing Safari profile window found for \(profile.displayName); opening a new one")
        return openNewWindow(profile: profile)
    }

    func openNewWindow(profile: Profile) -> Result<Void, SafariAutomationError> {
        performNewProfileWindow(profile: profile)
    }

    func openURL(_ url: URL, in profile: Profile) -> Result<Void, SafariAutomationError> {
        switch switchToProfile(profile) {
        case .success:
            return SafariAutomation.shared.openURLInNewTab(url, preferredWindowId: nil)
        case .failure(let error):
            return .failure(error)
        }
    }

    func discoverProfileNames() -> Result<[String], SafariAutomationError> {
        let script = """
        tell application "Safari" to activate
        tell application "System Events"
            if not (exists process "Safari") then return "ERROR:Safari not running"
            tell process "Safari"
                set profileNames to {}
                tell menu "File" of menu bar 1
                    repeat with menuItem in menu items
                        set itemTitle to name of menuItem
                        if itemTitle starts with "New " and itemTitle ends with " Window" and itemTitle is not "New Window" and itemTitle is not "New Private Window" and itemTitle is not "New Tab" then
                            set profileName to text 5 thru -8 of itemTitle
                            if profileName is not "" and profileName is not "Private" then set end of profileNames to profileName
                        end if
                    end repeat
                end tell
                set AppleScript's text item delimiters to linefeed
                set outputText to profileNames as text
                set AppleScript's text item delimiters to ""
                return outputText
            end tell
        end tell
        """
        switch run(script) {
        case .success(let output):
            if output == "ERROR:Safari not running" { return .failure(.safariNotRunning) }
            let names = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            return .success(Array(NSOrderedSet(array: names)) as? [String] ?? names)
        case .failure(let error):
            return .failure(error)
        }
    }

    // Backwards-compatible wrapper for older callers.
    func discoverProfiles() -> Result<[String], SafariAutomationError> {
        discoverProfileNames()
    }

    private func switchToExistingWindow(for profile: Profile) -> Bool {
        guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: FrontmostSafariMonitor.safariBundleIdentifier).first else {
            return false
        }
        let appElement = AXUIElementCreateApplication(safari.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return false }

        let needle = profile.effectiveMenuName.lowercased()
        for window in windows {
            let haystack = accessibilityStrings(from: window, maxDepth: 5).joined(separator: "\n").lowercased()
            if haystack.contains(needle) {
                safari.activate(options: [.activateAllWindows])
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return true
            }
        }
        return false
    }

    private func accessibilityStrings(from element: AXUIElement, maxDepth: Int) -> [String] {
        guard maxDepth >= 0 else { return [] }
        var result: [String] = []
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success {
                if let string = value as? String, !string.isEmpty {
                    result.append(string)
                } else if let attributed = value as? NSAttributedString, !attributed.string.isEmpty {
                    result.append(attributed.string)
                }
            }
        }

        guard maxDepth > 0 else { return result }
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children.prefix(80) {
                result.append(contentsOf: accessibilityStrings(from: child, maxDepth: maxDepth - 1))
            }
        }
        return result
    }

    private func performNewProfileWindow(profile: Profile) -> Result<Void, SafariAutomationError> {
        let title = Self.escapeAppleScript("New \(profile.effectiveMenuName) Window")
        let script = """
        tell application "Safari" to activate
        tell application "System Events"
            if not (exists process "Safari") then return "ERROR:Safari not running"
            tell process "Safari"
                tell menu "File" of menu bar 1
                    try
                        click menu item "\(title)"
                        return "OK"
                    on error errMsg
                        return "ERROR:" & errMsg
                    end try
                end tell
            end tell
        end tell
        """
        switch run(script) {
        case .success(let output):
            if output == "OK" { return .success(()) }
            if output == "ERROR:Safari not running" { return .failure(.safariNotRunning) }
            return .failure(.unsupportedState(output))
        case .failure(let error):
            return .failure(error)
        }
    }

    private func run(_ source: String) -> Result<String, SafariAutomationError> {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(.appleScriptFailed("Could not compile profile script.")) }
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? errorInfo.description
            return .failure(.appleScriptFailed(message))
        }
        return .success(descriptor.stringValue ?? "")
    }

    private static func escapeAppleScript(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
