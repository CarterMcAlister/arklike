import Foundation

struct SafariWindowIDResolver: Sendable {
    struct WindowSummary: Sendable {
        let id: Int
        let title: String?
    }

    static func resolve(title: String?) -> Int? {
        let windows = PerformanceTimer.measure("safari window id appleScript resolution") {
            enumeratedWindows()
        }
        guard !windows.isEmpty else { return nil }
        if let title, !title.isEmpty,
           let matched = windows.first(where: { $0.title == title }) {
            return matched.id
        }
        return windows.first?.id
    }

    private static func enumeratedWindows() -> [WindowSummary] {
        let source = """
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

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return [] }
        let descriptor = script.executeAndReturnError(&error)
        guard error == nil, let output = descriptor.stringValue, !output.isEmpty else { return [] }
        return output
            .components(separatedBy: .newlines)
            .compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard let idText = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let id = Int(idText) else { return nil }
                let title = parts.dropFirst().joined(separator: "\t").nilIfEmpty
                return WindowSummary(id: id, title: title)
            }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
