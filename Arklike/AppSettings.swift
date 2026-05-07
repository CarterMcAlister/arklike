import Foundation

struct SearchShortcut: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var keyword: String
    var aliasesText: String
    var name: String
    var urlTemplate: String
    var isEnabled: Bool

    var aliases: [String] {
        aliasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    var normalizedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var normalizedTokens: [String] {
        ([normalizedKeyword] + aliases).filter { !$0.isEmpty }
    }

    static let defaults: [SearchShortcut] = [
        SearchShortcut(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, keyword: "gh", aliasesText: "github", name: "GitHub", urlTemplate: "https://github.com/search?q={query}", isEnabled: true),
        SearchShortcut(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, keyword: "yt", aliasesText: "youtube", name: "YouTube", urlTemplate: "https://www.youtube.com/results?search_query={query}", isEnabled: true),
        SearchShortcut(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, keyword: "b", aliasesText: "bing", name: "Bing", urlTemplate: "https://www.bing.com/search?q={query}", isEnabled: true)
    ]
}

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

    @Published var searchShortcuts: [SearchShortcut] {
        didSet { saveSearchShortcuts() }
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
        searchShortcuts = Self.loadSearchShortcuts(from: defaults)
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

    func addSearchShortcut() {
        searchShortcuts.append(SearchShortcut(id: UUID(), keyword: "", aliasesText: "", name: "New Shortcut", urlTemplate: SearchEngineService.defaultTemplate, isEnabled: true))
    }

    func deleteSearchShortcut(id: SearchShortcut.ID) {
        searchShortcuts.removeAll { $0.id == id }
    }

    func resetSearchShortcuts() {
        searchShortcuts = SearchShortcut.defaults
    }

    private static func loadSearchShortcuts(from defaults: UserDefaults) -> [SearchShortcut] {
        guard let data = defaults.data(forKey: Keys.searchShortcuts),
              let decoded = try? JSONDecoder().decode([SearchShortcut].self, from: data) else {
            return SearchShortcut.defaults
        }
        return decoded
    }

    private func saveSearchShortcuts() {
        guard let data = try? JSONEncoder().encode(searchShortcuts) else { return }
        defaults.set(data, forKey: Keys.searchShortcuts)
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
    static let searchShortcuts = "searchShortcuts"
}
