import Foundation
import os

@MainActor
final class Diagnostics: ObservableObject {
    static let shared = Diagnostics()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arklike.app", category: "Arklike")
    @Published private(set) var events: [String] = []
    @Published var lastRoutingDecision: String = "None"

    private init() {}

    func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        events.insert("\(Date()): \(message)", at: 0)
        events = Array(events.prefix(200))
    }

    func copyDiagnostics() {
        ClipboardService.copy(report())
    }

    func report() -> String {
        let permissions = PermissionsManager.shared.snapshot
        let safari = FrontmostSafariMonitor.shared.snapshot
        let profiles = ProfileStore.shared.profiles.map { "\($0.assignedNumber): \($0.displayName) [menu=New \($0.effectiveMenuName) Window]" }.joined(separator: "\n")
        return """
        Arklike Diagnostics
        ===================
        App path: \(Bundle.main.bundleURL.path)
        Bundle id: \(Bundle.main.bundleIdentifier ?? "Unknown")
        Accessibility: \(permissions.accessibility.label)
        Apple Events Safari: \(permissions.appleEventsSafari.label)
        Default Browser: \(permissions.defaultBrowser.label) \(permissions.defaultBrowserBundleIdentifier ?? "")
        Safari frontmost: \(safari.isSafariFrontmost)
        Active Safari window id: \(safari.activeWindow?.safariWindowId.map(String.init) ?? "Unknown")
        Active Safari title: \(safari.activeWindow?.title ?? "Unknown")
        Profiles:
        \(profiles.isEmpty ? "None configured" : profiles)
        Last routing decision: \(lastRoutingDecision)
        Recent events:
        \(events.joined(separator: "\n"))
        """
    }
}
