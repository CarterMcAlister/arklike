import AppKit
import SwiftUI

extension Notification.Name {
    static let arklikeSettingsDestinationRequested = Notification.Name("arklikeSettingsDestinationRequested")
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show(destination: SettingsDestination = .general) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .arklikeSettingsDestinationRequested, object: destination)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView(initialDestination: destination))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Arklike Settings"
        window.setContentSize(NSSize(width: 760, height: 780))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
