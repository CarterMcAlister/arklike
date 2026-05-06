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

    @Published var webSearchSuggestionsEnabled: Bool {
        didSet { defaults.set(webSearchSuggestionsEnabled, forKey: Keys.webSearchSuggestionsEnabled) }
    }

    @Published var switchToExistingSafariTabInsteadOfOpeningDuplicate: Bool {
        didSet { defaults.set(switchToExistingSafariTabInsteadOfOpeningDuplicate, forKey: Keys.switchToExistingSafariTabInsteadOfOpeningDuplicate) }
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        safariShortcutOverridesEnabled = defaults.object(forKey: Keys.safariShortcutOverridesEnabled) as? Bool ?? true
        commandPaletteShortcutEnabled = defaults.object(forKey: Keys.commandPaletteShortcutEnabled) as? Bool ?? true
        copyURLShortcutEnabled = defaults.object(forKey: Keys.copyURLShortcutEnabled) as? Bool ?? true
        sidebarShortcutEnabled = defaults.object(forKey: Keys.sidebarShortcutEnabled) as? Bool ?? true
        profileShortcutsEnabled = defaults.object(forKey: Keys.profileShortcutsEnabled) as? Bool ?? true
        webSearchSuggestionsEnabled = defaults.object(forKey: Keys.webSearchSuggestionsEnabled) as? Bool ?? false
        switchToExistingSafariTabInsteadOfOpeningDuplicate = defaults.object(forKey: Keys.switchToExistingSafariTabInsteadOfOpeningDuplicate) as? Bool ?? true
    }

    func resetShortcutOverrideDefaults() {
        safariShortcutOverridesEnabled = true
        commandPaletteShortcutEnabled = true
        copyURLShortcutEnabled = true
        sidebarShortcutEnabled = true
        profileShortcutsEnabled = true
        webSearchSuggestionsEnabled = false
        switchToExistingSafariTabInsteadOfOpeningDuplicate = true
    }
}

private enum Keys {
    static let safariShortcutOverridesEnabled = "safariShortcutOverridesEnabled"
    static let commandPaletteShortcutEnabled = "commandPaletteShortcutEnabled"
    static let copyURLShortcutEnabled = "copyURLShortcutEnabled"
    static let sidebarShortcutEnabled = "sidebarShortcutEnabled"
    static let profileShortcutsEnabled = "profileShortcutsEnabled"
    static let webSearchSuggestionsEnabled = "webSearchSuggestionsEnabled"
    static let switchToExistingSafariTabInsteadOfOpeningDuplicate = "switchToExistingSafariTabInsteadOfOpeningDuplicate"
}
