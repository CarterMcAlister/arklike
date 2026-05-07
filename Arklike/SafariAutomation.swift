import AppKit
import Foundation

struct SafariTabSnapshot: Identifiable, Equatable, Sendable {
    var id: String { "\(windowId)-\(tabIndex)" }
    let windowId: Int
    let windowTitle: String?
    let tabIndex: Int
    let title: String?
    let url: URL?
    let isActive: Bool
}

struct SafariWindowSnapshot: Identifiable, Equatable, Sendable {
    var id: Int { windowId }
    let windowId: Int
    let title: String?
    let tabs: [SafariTabSnapshot]
}

enum SafariAutomationError: LocalizedError, Equatable, Sendable {
    case safariNotRunning
    case noWindows
    case appleScriptFailed(String)
    case invalidURL
    case permissionDenied
    case unsupportedState(String)

    var errorDescription: String? {
        switch self {
        case .safariNotRunning: "Safari is not running."
        case .noWindows: "Safari has no open windows."
        case .appleScriptFailed(let message): "Safari automation failed: \(message)"
        case .invalidURL: "The URL is invalid."
        case .permissionDenied: "Arklike does not have permission to automate Safari."
        case .unsupportedState(let message): message
        }
    }
}

final class SafariAutomation {
    static let shared = SafariAutomation()

    private init() {}

    func listWindowsAndTabs() -> Result<[SafariWindowSnapshot], SafariAutomationError> {
        let script = """
        tell application "System Events"
            if not (exists process "Safari") then return "ERROR:Safari not running"
        end tell
        tell application "Safari"
            if (count of windows) is 0 then return ""
            set windowLines to {}
            repeat with safariWindow in windows
                set windowIdText to (id of safariWindow) as text
                set windowName to ""
                try
                    set windowName to name of safariWindow
                end try
                set activeTabIndex to 0
                try
                    set activeTabIndex to index of current tab of safariWindow
                end try
                repeat with safariTab in tabs of safariWindow
                    set tabIndexText to (index of safariTab) as text
                    set tabName to ""
                    set tabURL to ""
                    try
                        set tabName to name of safariTab
                    end try
                    try
                        set tabURL to URL of safariTab
                    end try
                    set isActiveText to "0"
                    if (tabIndexText as integer) is activeTabIndex then set isActiveText to "1"
                    set end of windowLines to windowIdText & tab & windowName & tab & tabIndexText & tab & tabName & tab & tabURL & tab & isActiveText
                end repeat
            end repeat
            set AppleScript's text item delimiters to linefeed
            set outputText to windowLines as text
            set AppleScript's text item delimiters to ""
            return outputText
        end tell
        """

        switch runAppleScript(script) {
        case .success(let output):
            if output == "ERROR:Safari not running" { return .failure(.safariNotRunning) }
            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .success([]) }
            return .success(parseTabSnapshots(output))
        case .failure(let error):
            return .failure(error)
        }
    }

    func getActiveTabURL(preferredWindowId: Int? = nil) -> Result<URL, SafariAutomationError> {
        let windowSelector: String
        if let preferredWindowId {
            windowSelector = """
            set targetWindow to missing value
            repeat with safariWindow in windows
                if (id of safariWindow) is \(preferredWindowId) then
                    set targetWindow to safariWindow
                    exit repeat
                end if
            end repeat
            if targetWindow is missing value then set targetWindow to front window
            """
        } else {
            windowSelector = "set targetWindow to front window"
        }

        let script = """
        tell application "System Events"
            if not (exists process "Safari") then return "ERROR:Safari not running"
        end tell
        tell application "Safari"
            if (count of windows) is 0 then return "ERROR:No windows"
            \(windowSelector)
            set activeTab to current tab of targetWindow
            set tabURL to URL of activeTab
            return tabURL
        end tell
        """

        switch runAppleScript(script) {
        case .success(let output):
            if output == "ERROR:Safari not running" { return .failure(.safariNotRunning) }
            if output == "ERROR:No windows" { return .failure(.noWindows) }
            guard let url = URL(string: output), !output.isEmpty else { return .failure(.invalidURL) }
            return .success(url)
        case .failure(let error):
            return .failure(error)
        }
    }

    func activateWindow(windowId: Int) -> Result<Void, SafariAutomationError> {
        let script = """
        tell application "Safari" to activate
        tell application "Safari"
            repeat with safariWindow in windows
                if (id of safariWindow) is \(windowId) then
                    set index of safariWindow to 1
                    exit repeat
                end if
            end repeat
        end tell
        tell application "System Events"
            tell process "Safari"
                try
                    perform action "AXRaise" of window 1
                end try
            end tell
        end tell
        return "OK"
        """
        return voidResult(script)
    }

    func activateTab(windowId: Int, tabIndex: Int) -> Result<Void, SafariAutomationError> {
        let script = """
        tell application "Safari" to activate
        tell application "Safari"
            repeat with safariWindow in windows
                if (id of safariWindow) is \(windowId) then
                    set current tab of safariWindow to tab \(tabIndex) of safariWindow
                    set index of safariWindow to 1
                    tell application "System Events"
                        tell process "Safari"
                            try
                                perform action "AXRaise" of window 1
                            end try
                        end tell
                    end tell
                    return "OK"
                end if
            end repeat
            return "ERROR:Window not found"
        end tell
        """
        return voidResult(script)
    }

    func openURLInNewTab(_ url: URL, preferredWindowId: Int? = nil) -> Result<Void, SafariAutomationError> {
        let escapedURL = Self.escapeAppleScript(url.absoluteString)
        let windowSelector: String
        if let preferredWindowId {
            windowSelector = """
            set targetWindow to missing value
            repeat with safariWindow in windows
                if (id of safariWindow) is \(preferredWindowId) then
                    set targetWindow to safariWindow
                    exit repeat
                end if
            end repeat
            if targetWindow is missing value then set targetWindow to front window
            """
        } else {
            windowSelector = "set targetWindow to front window"
        }
        let script = """
        tell application "Safari"
            activate
            if (count of windows) is 0 then
                make new document with properties {URL:"\(escapedURL)"}
            else
                \(windowSelector)
                tell targetWindow
                    set newTab to make new tab at end of tabs with properties {URL:"\(escapedURL)"}
                    set current tab to newTab
                end tell
            end if
            return "OK"
        end tell
        """
        return voidResult(script)
    }

    func openURLInNewWindow(_ url: URL) -> Result<Void, SafariAutomationError> {
        let escapedURL = Self.escapeAppleScript(url.absoluteString)
        let script = """
        tell application "Safari"
            activate
            make new document with properties {URL:"\(escapedURL)"}
            return "OK"
        end tell
        """
        return voidResult(script)
    }

    func activateSafari() -> Result<Void, SafariAutomationError> {
        voidResult("""
        tell application "Safari"
            activate
            return "OK"
        end tell
        """)
    }

    private func voidResult(_ script: String) -> Result<Void, SafariAutomationError> {
        switch runAppleScript(script) {
        case .success(let output):
            if output.hasPrefix("ERROR:") { return .failure(.unsupportedState(output)) }
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    private func parseTabSnapshots(_ output: String) -> [SafariWindowSnapshot] {
        var grouped: [Int: (title: String?, tabs: [SafariTabSnapshot])] = [:]
        for line in output.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 6,
                  let windowId = Int(parts[0]),
                  let tabIndex = Int(parts[2]) else { continue }
            let windowTitle = parts[1].nilIfEmpty
            let title = parts[3].nilIfEmpty
            let url = URL(string: parts[4])
            let isActive = parts[5] == "1"
            let tab = SafariTabSnapshot(
                windowId: windowId,
                windowTitle: windowTitle,
                tabIndex: tabIndex,
                title: title,
                url: url,
                isActive: isActive
            )
            var entry = grouped[windowId] ?? (windowTitle, [])
            entry.tabs.append(tab)
            grouped[windowId] = entry
        }
        return grouped
            .map { SafariWindowSnapshot(windowId: $0.key, title: $0.value.title, tabs: $0.value.tabs.sorted { $0.tabIndex < $1.tabIndex }) }
            .sorted { $0.windowId < $1.windowId }
    }

    private func runAppleScript(_ source: String) -> Result<String, SafariAutomationError> {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.appleScriptFailed("Could not compile AppleScript."))
        }
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? errorInfo.description
            if message.localizedCaseInsensitiveContains("not authorized") || message.localizedCaseInsensitiveContains("not permitted") {
                return .failure(.permissionDenied)
            }
            return .failure(.appleScriptFailed(message))
        }
        return .success(descriptor.stringValue ?? "")
    }

    private static func escapeAppleScript(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum SafariTabSnapshotLoader {
    static func listWindowsAndTabs() -> Result<[SafariWindowSnapshot], SafariAutomationError> {
        let script = """
        tell application "System Events"
            if not (exists process "Safari") then return "ERROR:Safari not running"
        end tell
        tell application "Safari"
            if (count of windows) is 0 then return ""
            set windowLines to {}
            repeat with safariWindow in windows
                set windowIdText to (id of safariWindow) as text
                set windowName to ""
                try
                    set windowName to name of safariWindow
                end try
                set activeTabIndex to 0
                try
                    set activeTabIndex to index of current tab of safariWindow
                end try
                repeat with safariTab in tabs of safariWindow
                    set tabIndexText to (index of safariTab) as text
                    set tabName to ""
                    set tabURL to ""
                    try
                        set tabName to name of safariTab
                    end try
                    try
                        set tabURL to URL of safariTab
                    end try
                    set isActiveText to "0"
                    if (tabIndexText as integer) is activeTabIndex then set isActiveText to "1"
                    set end of windowLines to windowIdText & tab & windowName & tab & tabIndexText & tab & tabName & tab & tabURL & tab & isActiveText
                end repeat
            end repeat
            set AppleScript's text item delimiters to linefeed
            set outputText to windowLines as text
            set AppleScript's text item delimiters to ""
            return outputText
        end tell
        """

        switch runAppleScript(script) {
        case .success(let output):
            if output == "ERROR:Safari not running" { return .failure(.safariNotRunning) }
            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .success([]) }
            return .success(parseTabSnapshots(output))
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func parseTabSnapshots(_ output: String) -> [SafariWindowSnapshot] {
        var grouped: [Int: (title: String?, tabs: [SafariTabSnapshot])] = [:]
        for line in output.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 6,
                  let windowId = Int(parts[0]),
                  let tabIndex = Int(parts[2]) else { continue }
            let windowTitle = parts[1].nilIfEmpty
            let title = parts[3].nilIfEmpty
            let url = URL(string: parts[4])
            let isActive = parts[5] == "1"
            let tab = SafariTabSnapshot(
                windowId: windowId,
                windowTitle: windowTitle,
                tabIndex: tabIndex,
                title: title,
                url: url,
                isActive: isActive
            )
            var entry = grouped[windowId] ?? (windowTitle, [])
            entry.tabs.append(tab)
            grouped[windowId] = entry
        }
        return grouped
            .map { SafariWindowSnapshot(windowId: $0.key, title: $0.value.title, tabs: $0.value.tabs.sorted { $0.tabIndex < $1.tabIndex }) }
            .sorted { $0.windowId < $1.windowId }
    }

    private static func runAppleScript(_ source: String) -> Result<String, SafariAutomationError> {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.appleScriptFailed("Could not compile AppleScript."))
        }
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? errorInfo.description
            if message.localizedCaseInsensitiveContains("not authorized") || message.localizedCaseInsensitiveContains("not permitted") {
                return .failure(.permissionDenied)
            }
            return .failure(.appleScriptFailed(message))
        }
        return .success(descriptor.stringValue ?? "")
    }
}
