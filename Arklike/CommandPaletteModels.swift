import Foundation

enum CommandPaletteItemKind: String, Equatable, Codable {
    case exactCommand
    case siteShortcut
    case url
    case safariTab
    case profile
    case trafficRule
    case historyOrRecent
    case search
    case settings
}

struct CommandPaletteItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let kind: CommandPaletteItemKind
    let rank: Int
    let representedURL: URL?
    let action: CommandPaletteAction
}

enum CommandPaletteAction: Equatable {
    case openURL(URL)
    case search(String)
    case switchToSafariTab(windowId: Int?, tabIndex: Int?)
    case openProfile(Int)
    case showTrafficRule(String)
    case openSettings(SettingsDestination)
    case noop(String)
}

enum SettingsDestination: String, Equatable, Codable {
    case general
    case shortcuts
    case profiles
    case commandPalette
    case trafficControl
    case permissions

    var title: String {
        switch self {
        case .general: "General Settings"
        case .shortcuts: "Shortcuts Settings"
        case .profiles: "Profiles Settings"
        case .commandPalette: "Command Palette Settings"
        case .trafficControl: "Traffic Control Settings"
        case .permissions: "Permissions Settings"
        }
    }
}

@MainActor
protocol CommandPaletteProviding {
    var providerName: String { get }
    func items(for query: String, context: CommandPaletteContext) -> [CommandPaletteItem]
}

struct CommandPaletteContext {
    let safariSnapshot: FrontmostSafariSnapshot
    let recentURLs: [URL]
}

enum CommandPaletteRanking {
    static func rank(for kind: CommandPaletteItemKind) -> Int {
        switch kind {
        case .exactCommand, .siteShortcut: 0
        case .url: 10
        case .safariTab: 20
        case .profile: 30
        case .trafficRule: 40
        case .historyOrRecent: 50
        case .search: 60
        case .settings: 70
        }
    }
}
