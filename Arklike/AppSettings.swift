import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var safariShortcutOverridesEnabled: Bool {
        didSet { defaults.set(safariShortcutOverridesEnabled, forKey: Keys.safariShortcutOverridesEnabled) }
    }

    @Published var commandPaletteShortcutEnabled: Bool {
        didSet { defaults.set(commandPaletteShortcutEnabled, forKey: Keys.commandPaletteShortcutEnabled) }
    }

    @Published var copyURLShortcutEnabled: Bool {
        didSet { defaults.set(copyURLShortcutEnabled, forKey: Keys.copyURLShortcutEnabled) }
    }

    @Published var sidebarShortcutEnabled: Bool {
        didSet { defaults.set(sidebarShortcutEnabled, forKey: Keys.sidebarShortcutEnabled) }
    }

    @Published var profileShortcutsEnabled: Bool {
        didSet { defaults.set(profileShortcutsEnabled, forKey: Keys.profileShortcutsEnabled) }
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        safariShortcutOverridesEnabled = defaults.object(forKey: Keys.safariShortcutOverridesEnabled) as? Bool ?? true
        commandPaletteShortcutEnabled = defaults.object(forKey: Keys.commandPaletteShortcutEnabled) as? Bool ?? true
        copyURLShortcutEnabled = defaults.object(forKey: Keys.copyURLShortcutEnabled) as? Bool ?? true
        sidebarShortcutEnabled = defaults.object(forKey: Keys.sidebarShortcutEnabled) as? Bool ?? true
        profileShortcutsEnabled = defaults.object(forKey: Keys.profileShortcutsEnabled) as? Bool ?? true
    }

    func resetShortcutOverrideDefaults() {
        safariShortcutOverridesEnabled = true
        commandPaletteShortcutEnabled = true
        copyURLShortcutEnabled = true
        sidebarShortcutEnabled = true
        profileShortcutsEnabled = true
    }
}

private enum Keys {
    static let safariShortcutOverridesEnabled = "safariShortcutOverridesEnabled"
    static let commandPaletteShortcutEnabled = "commandPaletteShortcutEnabled"
    static let copyURLShortcutEnabled = "copyURLShortcutEnabled"
    static let sidebarShortcutEnabled = "sidebarShortcutEnabled"
    static let profileShortcutsEnabled = "profileShortcutsEnabled"
}
