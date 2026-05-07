import AppKit

struct ClipboardService {
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    static func copyAsync(_ string: String) {
        Task.detached(priority: .utility) {
            copy(string)
        }
    }
}
