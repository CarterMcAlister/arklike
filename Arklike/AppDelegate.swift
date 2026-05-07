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
        MainThreadStallDetector.start()
        configureApplicationIcon()
        NSApp.setActivationPolicy(.accessory)
        FrontmostSafariMonitor.shared.start()
        SafariBookmarkStore.shared.startPeriodicRefresh()
        ProfileStore.shared.startPeriodicRefresh()
        SafariLiveTabStore.shared.startPeriodicRefresh()
        ShortcutManager.shared.start { [weak self] action in
            self?.handleShortcut(action)
        }
        configureStatusItem()
    }

    private func configureApplicationIcon() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        PermissionsManager.shared.refreshAsync()
        FrontmostSafariMonitor.shared.scheduleRefresh(reason: "app became active")
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
            Task { @MainActor in self.openCommandPalette() }
        case .copyCurrentURL:
            copyCurrentSafariURL()
        case .toggleSafariSidebar:
            toggleSafariSidebar()
        case .profile1, .profile2, .profile3, .profile4, .profile5, .profile6, .profile7, .profile8, .profile9:
            guard let number = action.profileNumber else { return }
            Diagnostics.shared.log("Profile shortcut requested: \(number)")
            Task { @MainActor in
                switch await SafariProfileManager.shared.switchToProfileAsync(number: number) {
                case .success:
                    NotificationHUD.show(title: "Safari Profile", message: "Opened profile \(number).")
                case .failure(let error):
                    showPlaceholderAlert(title: "Could not open profile \(number)", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func openCommandPalette() {
        CommandPaletteController.shared.show()
    }

    private func copyCurrentSafariURL() {
        let preferredWindowId = FrontmostSafariMonitor.shared.activeWindowForSafariAction()?.safariWindowId
        Diagnostics.shared.log("Copy current Safari URL requested")
        Task.detached(priority: .userInitiated) {
            let result = SafariAutomation.shared.getActiveTabURL(preferredWindowId: preferredWindowId)
            await MainActor.run {
                switch result {
                case .success(let url):
                    ClipboardService.copyAsync(url.absoluteString)
                    ToastHUD.shared.showURLCopied()
                case .failure(let error):
                    self.showPlaceholderAlert(title: "Could not copy URL", message: error.localizedDescription)
                }
            }
        }
    }

    private func toggleSafariSidebar() {
        Diagnostics.shared.log("Toggle Safari sidebar requested")
        Task.detached(priority: .userInitiated) {
            let result = SafariSidebarController.shared.toggleSidebar()
            await MainActor.run {
                switch result {
                case .success:
                    NotificationHUD.show(title: "Safari Sidebar", message: "Toggled Safari’s native sidebar.")
                case .failure(let error):
                    self.showPlaceholderAlert(title: "Could not toggle Safari sidebar", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showPlaceholderAlert(title: String, message: String) {
        NotificationHUD.show(title: title, message: message)
    }
}
