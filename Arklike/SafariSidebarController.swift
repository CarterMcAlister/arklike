import Foundation

final class SafariSidebarController {
    static let shared = SafariSidebarController()

    private init() {}

    func toggleSidebar() -> Result<Void, SafariAutomationError> {
        let menuScript = """
        tell application "Safari" to activate
        tell application "System Events"
            if not (exists process "Safari") then return "ERROR:Safari not running"
            tell process "Safari"
                try
                    click menu item "Show Sidebar" of menu "View" of menu bar 1
                    return "OK"
                on error
                    try
                        click menu item "Hide Sidebar" of menu "View" of menu bar 1
                        return "OK"
                    on error errMsg
                        return "ERROR:" & errMsg
                    end try
                end try
            end tell
        end tell
        """

        if case .success = run(menuScript) {
            return .success(())
        }

        let keyboardFallback = """
        tell application "Safari" to activate
        tell application "System Events"
            if not (exists process "Safari") then return "ERROR:Safari not running"
            keystroke "l" using {command down, shift down}
            return "OK"
        end tell
        """
        return run(keyboardFallback)
    }

    private func run(_ source: String) -> Result<Void, SafariAutomationError> {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.appleScriptFailed("Could not compile sidebar script."))
        }
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? errorInfo.description
            return .failure(.appleScriptFailed(message))
        }
        let output = descriptor.stringValue ?? ""
        if output == "OK" || output.isEmpty { return .success(()) }
        if output == "ERROR:Safari not running" { return .failure(.safariNotRunning) }
        if output.hasPrefix("ERROR:") { return .failure(.unsupportedState(output)) }
        return .success(())
    }
}
