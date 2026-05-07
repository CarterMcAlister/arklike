import Foundation

// MARK: - Scopes / modes

enum CommandPanelSearchScope: String, CaseIterable, Equatable, Codable, Identifiable, Sendable {
    case all
    case recents
    case liveTabs
    case bookmarks
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .recents: "Recents"
        case .liveTabs: "Live Tabs"
        case .bookmarks: "Bookmarks"
        case .settings: "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .recents: "clock"
        case .liveTabs: "safari"
        case .bookmarks: "book"
        case .settings: "gearshape"
        }
    }

    var keywords: [String] {
        switch self {
        case .all: ["all", "everything"]
        case .recents: ["recent", "recents", "history"]
        case .liveTabs: ["tab", "tabs", "live tabs", "livetabs"]
        case .bookmarks: ["bookmark", "bookmarks", "favorite", "favorites", "saved"]
        case .settings: ["settings", "tools", "commands", "actions"]
        }
    }

    static let cyclingOrder: [CommandPanelSearchScope] = [.all, .recents, .liveTabs, .bookmarks, .settings]

    static func matchingKeyword(_ text: String) -> CommandPanelSearchScope? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return allCases.first { scope in
            scope.keywords.contains(normalized)
        }
    }
}

enum CommandPanelMode: Equatable, Sendable {
    case search
    case scopePicker
    case actions
}

// MARK: - Suggestions

enum CommandPanelSuggestionKind: String, Equatable, Codable, Sendable {
    case exactCommand
    case siteShortcut
    case url
    case pasteAndGo
    case safariTab
    case profile
    case trafficRule
    case historyOrRecent
    case searchHistory
    case webSuggestion
    case search
    case settings
    case bookmark
    case scope
    case action
    case permission
}

typealias CommandPaletteItemKind = CommandPanelSuggestionKind

struct CommandPanelAlternateAction: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String
    let action: CommandPaletteAction
}

struct CommandPanelSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let kind: CommandPanelSuggestionKind
    let scope: CommandPanelSearchScope?
    let iconSystemName: String
    let representedURL: URL?
    let primaryAction: CommandPaletteAction
    let alternateActions: [CommandPanelAlternateAction]
    let basePriority: Int
    var fuzzyScore: Double
    var usageScore: Double
    var lastUsedAt: Date?
    var matchRanges: [Range<String.Index>]
    var titleMatchRanges: [Range<String.Index>]
    var subtitleMatchRanges: [Range<String.Index>]

    var action: CommandPaletteAction { primaryAction }
    var rank: Int { basePriority }

    init(
        id: String,
        title: String,
        subtitle: String,
        kind: CommandPanelSuggestionKind,
        scope: CommandPanelSearchScope?,
        iconSystemName: String? = nil,
        representedURL: URL?,
        primaryAction: CommandPaletteAction,
        alternateActions: [CommandPanelAlternateAction] = [],
        basePriority: Int,
        fuzzyScore: Double = 0,
        usageScore: Double = 0,
        lastUsedAt: Date? = nil,
        matchRanges: [Range<String.Index>] = [],
        titleMatchRanges: [Range<String.Index>] = [],
        subtitleMatchRanges: [Range<String.Index>] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.scope = scope
        self.iconSystemName = iconSystemName ?? kind.defaultIconName
        self.representedURL = representedURL
        self.primaryAction = primaryAction
        self.alternateActions = alternateActions
        self.basePriority = basePriority
        self.fuzzyScore = fuzzyScore
        self.usageScore = usageScore
        self.lastUsedAt = lastUsedAt
        self.matchRanges = matchRanges
        self.titleMatchRanges = titleMatchRanges
        self.subtitleMatchRanges = subtitleMatchRanges
    }

    static func == (lhs: CommandPanelSuggestion, rhs: CommandPanelSuggestion) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.kind == rhs.kind
            && lhs.scope == rhs.scope
            && lhs.representedURL == rhs.representedURL
            && lhs.primaryAction == rhs.primaryAction
            && lhs.basePriority == rhs.basePriority
            && lhs.fuzzyScore == rhs.fuzzyScore
            && lhs.usageScore == rhs.usageScore
            && lhs.lastUsedAt == rhs.lastUsedAt
    }
}

typealias CommandPaletteItem = CommandPanelSuggestion

extension CommandPanelSuggestionKind {
    var defaultIconName: String {
        switch self {
        case .exactCommand: "command"
        case .siteShortcut: "magnifyingglass.circle"
        case .url: "globe"
        case .pasteAndGo: "doc.on.clipboard"
        case .safariTab: "safari"
        case .profile: "person.crop.circle"
        case .trafficRule: "arrow.triangle.branch"
        case .historyOrRecent: "clock"
        case .searchHistory: "clock.arrow.circlepath"
        case .webSuggestion, .search: "magnifyingglass"
        case .settings: "gearshape"
        case .bookmark: "book"
        case .scope: "line.3.horizontal.decrease.circle"
        case .action: "bolt"
        case .permission: "exclamationmark.triangle"
        }
    }
}

enum CommandPaletteAction: Equatable, Sendable {
    case openURL(URL)
    case search(String)
    case switchToSafariTab(windowId: Int?, tabIndex: Int?)
    case openProfile(Int)
    case showTrafficRule(String)
    case openSettings(SettingsDestination)
    case copyURL(URL)
    case copyText(String)
    case removeRecent(URL)
    case removeSuggestion(String)
    case toggleWebSuggestions
    case toggleDuplicateTabSwitching
    case clearRecents
    case clearSearchHistory
    case refreshSafariBookmarks
    case activateScope(CommandPanelSearchScope)
    case acceptAutocomplete(String)
    case noop(String)
}

enum SettingsDestination: String, Equatable, Codable, CaseIterable, Sendable {
    case general
    case shortcuts
    case profiles
    case commandPalette
    case trafficControl
    case permissions
    case diagnostics

    var title: String {
        switch self {
        case .general: "General Settings"
        case .shortcuts: "Shortcuts Settings"
        case .profiles: "Profiles Settings"
        case .commandPalette: "Command Palette Settings"
        case .trafficControl: "Traffic Control Settings"
        case .permissions: "Permissions Settings"
        case .diagnostics: "Diagnostics Settings"
        }
    }
}

protocol CommandPanelSuggestionProviding: Sendable {
    var providerName: String { get }
    func suggestions(for query: String, input: CommandPanelSuggestionInput) -> [CommandPanelSuggestion]
}

typealias CommandPaletteProviding = CommandPanelSuggestionProviding

struct CommandPanelContext {
    let safariSnapshot: FrontmostSafariSnapshot
    let recentItems: [CommandPanelRecentItem]
    let safariTabs: [SafariTabSnapshot]
    let safariTabError: SafariAutomationError?
    let clipboardURL: URL?
    let webSuggestions: [String]
    let bookmarks: [SafariBookmark]
    let bookmarkError: String?
}

typealias CommandPaletteContext = CommandPanelContext

enum CommandPaletteRanking {
    static func rank(for kind: CommandPanelSuggestionKind) -> Int {
        switch kind {
        case .exactCommand, .siteShortcut, .pasteAndGo: 0
        case .url: 10
        case .safariTab: 20
        case .bookmark: 30
        case .profile: 40
        case .trafficRule: 50
        case .historyOrRecent, .searchHistory: 60
        case .webSuggestion: 70
        case .search: 80
        case .settings: 90
        case .scope: 0
        case .action: 0
        case .permission: 5
        }
    }
}

enum CommandPanelSuggestionLimits {
    static let visible = 15
    static let searchSuggestionReserve = 6
    static let emptySourceCandidates = 12
    static let querySourceCandidates = 60
    static let fallbackFuzzyCandidates = 24
}
