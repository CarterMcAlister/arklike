import AppKit
import ApplicationServices
import Foundation

@MainActor
final class SafariProfileManager {
    static let shared = SafariProfileManager()

    private init() {}

    func switchToProfileAsync(number: Int) async -> Result<Void, SafariAutomationError> {
        guard let profile = ProfileStore.shared.profile(number: number) else {
            ProfileStore.shared.refreshFromSafariAsync()
            return .failure(.unsupportedState("No named Safari profile was discovered for Ctrl+\(number). Open Safari, then refresh Profiles in Arklike Settings."))
        }
        return await switchToProfileAsync(profile)
    }

    func switchToProfileAsync(_ profile: Profile) async -> Result<Void, SafariAutomationError> {
        await Task.detached(priority: .userInitiated) {
            if SafariProfileScriptRunner.switchToExistingWindow(for: profile) {
                return .success(())
            }
            return SafariProfileScriptRunner.performNewProfileWindow(profile: profile)
        }.value
    }

    func openURLAsync(_ url: URL, in profile: Profile) async -> Result<Void, SafariAutomationError> {
        switch await switchToProfileAsync(profile) {
        case .success:
            return await Task.detached(priority: .userInitiated) {
                SafariAutomation.shared.openURLInNewTab(url, preferredWindowId: nil)
            }.value
        case .failure(let error):
            return .failure(error)
        }
    }
}

enum SafariProfileScriptRunner {
    static func discoverProfileNames() -> Result<[String], SafariAutomationError> {
        let script = """
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

    static func switchToExistingWindow(for profile: Profile) -> Bool {
        guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: FrontmostSafariMonitor.safariBundleIdentifier).first else {
            return false
        }
        let appElement = AXUIElementCreateApplication(safari.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return false }

        let deadline = Date().addingTimeInterval(1.5)
        let needle = profile.effectiveMenuName.lowercased()
        for window in windows where Date() < deadline {
            let haystack = accessibilityStrings(from: window, maxDepth: 3, deadline: deadline).joined(separator: "\n").lowercased()
            if haystack.contains(needle) {
                safari.activate(options: [.activateAllWindows])
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return true
            }
        }
        return false
    }

    static func performNewProfileWindow(profile: Profile) -> Result<Void, SafariAutomationError> {
        let title = escapeAppleScript("New \(profile.effectiveMenuName) Window")
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

    private static func accessibilityStrings(from element: AXUIElement, maxDepth: Int, deadline: Date) -> [String] {
        guard maxDepth >= 0, Date() < deadline else { return [] }
        var result: [String] = []
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] where Date() < deadline {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success {
                if let string = value as? String, !string.isEmpty {
                    result.append(string)
                } else if let attributed = value as? NSAttributedString, !attributed.string.isEmpty {
                    result.append(attributed.string)
                }
            }
        }

        guard maxDepth > 0, Date() < deadline else { return result }
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children.prefix(40) where Date() < deadline {
                result.append(contentsOf: accessibilityStrings(from: child, maxDepth: maxDepth - 1, deadline: deadline))
            }
        }
        return result
    }

    private static func run(_ source: String) -> Result<String, SafariAutomationError> {
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
