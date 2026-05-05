import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            DefaultBrowserRouter.shared.routeIncomingURL(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        FrontmostSafariMonitor.shared.start()
        ShortcutManager.shared.start { [weak self] action in
            self?.handleShortcut(action)
        }
        configureStatusItem()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        PermissionsManager.shared.refresh()
        FrontmostSafariMonitor.shared.refresh(reason: "app became active")
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ""
        item.button?.image = MenuBarIcon.arkImage()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Arklike"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Open Command Palette",
            action: #selector(openCommandPalette),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Settings",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        for menuItem in menu.items {
            menuItem.target = self
        }

        item.menu = menu
        statusItem = item
    }

    private func handleShortcut(_ action: ShortcutAction) {
        switch action {
        case .commandPalette:
            openCommandPalette()
        case .copyCurrentURL:
            copyCurrentSafariURL()
        case .toggleSafariSidebar:
            toggleSafariSidebar()
        case .profile1, .profile2, .profile3, .profile4, .profile5, .profile6, .profile7, .profile8, .profile9:
            guard let number = action.profileNumber else { return }
            Diagnostics.shared.log("Profile shortcut requested: \(number)")
            switch SafariProfileManager.shared.switchToProfile(number: number) {
            case .success:
                NotificationHUD.show(title: "Safari Profile", message: "Opened profile \(number).")
            case .failure(let error):
                showPlaceholderAlert(title: "Could not open profile \(number)", message: error.localizedDescription)
            }
        }
    }

    @objc private func openCommandPalette() {
        CommandPaletteController.shared.show()
    }

    private func copyCurrentSafariURL() {
        let preferredWindowId = FrontmostSafariMonitor.shared.activeWindowForSafariAction()?.safariWindowId
        Diagnostics.shared.log("Copy current Safari URL requested")
        switch SafariAutomation.shared.getActiveTabURL(preferredWindowId: preferredWindowId) {
        case .success(let url):
            ClipboardService.copy(url.absoluteString)
            ToastHUD.shared.showURLCopied()
        case .failure(let error):
            showPlaceholderAlert(title: "Could not copy URL", message: error.localizedDescription)
        }
    }

    private func toggleSafariSidebar() {
        Diagnostics.shared.log("Toggle Safari sidebar requested")
        switch SafariSidebarController.shared.toggleSidebar() {
        case .success:
            NotificationHUD.show(title: "Safari Sidebar", message: "Toggled Safari’s native sidebar.")
        case .failure(let error):
            showPlaceholderAlert(title: "Could not toggle Safari sidebar", message: error.localizedDescription)
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showPlaceholderAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
