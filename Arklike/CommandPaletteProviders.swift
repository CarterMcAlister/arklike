import Foundation

struct BasicURLSearchProvider: CommandPaletteProviding {
    let providerName = "URL/Search"

    func items(for query: String, context: CommandPaletteContext) -> [CommandPaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return [CommandPaletteItem(
                id: "search-empty",
                title: "Type a URL or search query",
                subtitle: "Press Return after entering a destination",
                kind: .search,
                rank: CommandPaletteRanking.rank(for: .search),
                representedURL: nil,
                action: .noop("Enter a query")
            )]
        }

        if case .url(let url) = URLParser().parse(trimmed) {
            return [CommandPaletteItem(
                id: "url-\(url.absoluteString)",
                title: "Open \(url.absoluteString)",
                subtitle: "Open in a new Safari tab",
                kind: .url,
                rank: CommandPaletteRanking.rank(for: .url),
                representedURL: url,
                action: .openURL(url)
            )]
        }

        return [CommandPaletteItem(
            id: "search-\(trimmed)",
            title: "Search for “\(trimmed)”",
            subtitle: "Search the web",
            kind: .search,
            rank: CommandPaletteRanking.rank(for: .search),
            representedURL: nil,
            action: .search(trimmed)
        )]
    }

}

@MainActor
struct SafariTabCommandProvider: CommandPaletteProviding {
    let providerName = "Safari Tabs"

    func items(for query: String, context: CommandPaletteContext) -> [CommandPaletteItem] {
        context.safariTabs.compactMap { tab in
                let title = tab.title ?? tab.url?.absoluteString ?? "Untitled Safari Tab"
                let subtitle = [tab.url?.absoluteString, tab.isActive ? "Active" : nil]
                    .compactMap { $0 }
                    .joined(separator: " • ")
                guard query.isEmpty
                        || title.localizedCaseInsensitiveContains(query)
                        || subtitle.localizedCaseInsensitiveContains(query) else { return nil }
                return CommandPaletteItem(
                    id: "safari-tab-\(tab.windowId)-\(tab.tabIndex)",
                    title: title,
                    subtitle: subtitle.isEmpty ? "Safari tab" : subtitle,
                    kind: .safariTab,
                    rank: CommandPaletteRanking.rank(for: .safariTab),
                    representedURL: tab.url,
                    action: .switchToSafariTab(windowId: tab.windowId, tabIndex: tab.tabIndex)
                )
        }
    }
}

struct RecentURLCommandProvider: CommandPaletteProviding {
    let providerName = "Recents"

    func items(for query: String, context: CommandPaletteContext) -> [CommandPaletteItem] {
        context.recentURLs.prefix(10).compactMap { url in
            let text = url.absoluteString
            guard query.isEmpty || text.localizedCaseInsensitiveContains(query) else { return nil }
            return CommandPaletteItem(
                id: "recent-\(text)",
                title: text,
                subtitle: "Recent Arklike URL",
                kind: .historyOrRecent,
                rank: CommandPaletteRanking.rank(for: .historyOrRecent),
                representedURL: url,
                action: .openURL(url)
            )
        }
    }
}

struct SearchShortcutCommandProvider: CommandPaletteProviding {
    let providerName = "Search Shortcuts"

    private let shortcuts: [(keyword: String, name: String, template: String)] = [
        ("g", "Google", "https://www.google.com/search?q=%@"),
        ("ddg", "DuckDuckGo", "https://duckduckgo.com/?q=%@"),
        ("gh", "GitHub", "https://github.com/search?q=%@")
    ]

    func items(for query: String, context: CommandPaletteContext) -> [CommandPaletteItem] {
        let parts = query.split(separator: " ", maxSplits: 1).map(String.init)
        guard let keyword = parts.first?.trimmingCharacters(in: CharacterSet(charactersIn: ":")),
              let shortcut = shortcuts.first(where: { $0.keyword == keyword || query.hasPrefix($0.keyword + ":") }) else {
            return shortcuts
                .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.keyword.localizedCaseInsensitiveContains(query) }
                .map { shortcut in
                    CommandPaletteItem(
                        id: "site-shortcut-\(shortcut.keyword)",
                        title: "\(shortcut.keyword): Search \(shortcut.name)",
                        subtitle: "Type \(shortcut.keyword): your query",
                        kind: .siteShortcut,
                        rank: CommandPaletteRanking.rank(for: .siteShortcut),
                        representedURL: nil,
                        action: .noop("Enter a query for \(shortcut.name)")
                    )
                }
        }

        let searchText: String
        if query.hasPrefix(shortcut.keyword + ":") {
            searchText = String(query.dropFirst(shortcut.keyword.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            searchText = parts.dropFirst().first ?? ""
        }
        guard !searchText.isEmpty,
              let url = SearchEngineService.searchURL(for: searchText, template: shortcut.template) else { return [] }

        return [CommandPaletteItem(
            id: "site-shortcut-run-\(shortcut.keyword)-\(searchText)",
            title: "Search \(shortcut.name) for “\(searchText)”",
            subtitle: url.absoluteString,
            kind: .siteShortcut,
            rank: CommandPaletteRanking.rank(for: .siteShortcut),
            representedURL: url,
            action: .openURL(url)
        )]
    }
}

struct ProfileCommandProvider: CommandPaletteProviding {
    let providerName = "Profiles"

    func items(for query: String, context: CommandPaletteContext) -> [CommandPaletteItem] {
        guard query.localizedCaseInsensitiveContains("profile") || query.hasPrefix("p") else { return [] }
        return (1...9).map { number in
            CommandPaletteItem(
                id: "profile-\(number)",
                title: "Open Safari Profile \(number)",
                subtitle: "Profile mappings are configured in step 10",
                kind: .profile,
                rank: CommandPaletteRanking.rank(for: .profile),
                representedURL: nil,
                action: .openProfile(number)
            )
        }
    }
}

struct TrafficRuleCommandProvider: CommandPaletteProviding {
    let providerName = "Traffic Control"

    func items(for query: String, context: CommandPaletteContext) -> [CommandPaletteItem] {
        guard query.localizedCaseInsensitiveContains("traffic") || query.localizedCaseInsensitiveContains("rule") else { return [] }
        return [CommandPaletteItem(
            id: "traffic-control-placeholder",
            title: "Traffic Control Rules",
            subtitle: "Rule listing and matching are implemented in step 13",
            kind: .trafficRule,
            rank: CommandPaletteRanking.rank(for: .trafficRule),
            representedURL: nil,
            action: .openSettings(.trafficControl)
        )]
    }
}

struct SettingsCommandProvider: CommandPaletteProviding {
    let providerName = "Settings"

    func items(for query: String, context: CommandPaletteContext) -> [CommandPaletteItem] {
        guard query.isEmpty
                || "settings".localizedCaseInsensitiveContains(query)
                || query.localizedCaseInsensitiveContains("settings")
                || query.localizedCaseInsensitiveContains("preferences") else { return [] }

        return [CommandPaletteItem(
            id: "settings",
            title: "Settings",
            subtitle: "Open Arklike settings",
            kind: .settings,
            rank: CommandPaletteRanking.rank(for: .settings),
            representedURL: nil,
            action: .openSettings(.general)
        )]
    }
}
