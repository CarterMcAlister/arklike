import Foundation

private extension CommandPanelSuggestion {
    static func urlActions(_ url: URL) -> [CommandPanelAlternateAction] {
        [CommandPanelAlternateAction(id: "copy-url", title: "Copy URL", subtitle: url.absoluteString, iconSystemName: "doc.on.doc", action: .copyURL(url))]
    }
}

struct FrequentItemsCommandProvider: CommandPanelSuggestionProviding {
    let providerName = "Frequent Items"

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              state.mode == .search,
              state.activeScope == nil || state.activeScope == .all else { return [] }
        let records = CommandPanelUsageStore.shared.topRecords(limit: 10)
        var bookmarkByID: [String: SafariBookmark]?
        var tabByID: [String: SafariTabSnapshot]?
        return records.compactMap { record in
            if let recent = context.recentItems.first(where: { "recent-\($0.url.absoluteString)" == record.id }) {
                return CommandPanelSuggestion(
                    id: record.id,
                    title: recent.title ?? recent.url.absoluteString,
                    subtitle: "Frequently used • \(recent.url.absoluteString)",
                    kind: .historyOrRecent,
                    scope: .recents,
                    representedURL: recent.url,
                    primaryAction: .openURL(recent.url),
                    alternateActions: CommandPanelSuggestion.urlActions(recent.url),
                    basePriority: 2,
                    lastUsedAt: record.lastUsedAt
                )
            }
            if record.kind == CommandPanelSuggestionKind.bookmark.rawValue {
                if bookmarkByID == nil {
                    bookmarkByID = Dictionary(context.bookmarks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                }
            }
            if let bookmark = bookmarkByID?[record.id] {
                return CommandPanelSuggestion(
                    id: record.id,
                    title: bookmark.title,
                    subtitle: ["Frequently used", bookmark.url.absoluteString, bookmark.path].compactMap { $0 }.joined(separator: " • "),
                    kind: .bookmark,
                    scope: .bookmarks,
                    representedURL: bookmark.url,
                    primaryAction: .openURL(bookmark.url),
                    alternateActions: CommandPanelSuggestion.urlActions(bookmark.url),
                    basePriority: 2,
                    lastUsedAt: record.lastUsedAt
                )
            }
            if record.kind == CommandPanelSuggestionKind.safariTab.rawValue {
                if tabByID == nil {
                    tabByID = Dictionary(context.safariTabs.map { ("safari-tab-\($0.windowId)-\($0.tabIndex)", $0) }, uniquingKeysWith: { first, _ in first })
                }
            }
            if let tab = tabByID?[record.id] {
                let title = tab.title ?? tab.url?.absoluteString ?? "Untitled Safari Tab"
                return CommandPanelSuggestion(
                    id: record.id,
                    title: title,
                    subtitle: "Frequently used • Safari tab",
                    kind: .safariTab,
                    scope: .liveTabs,
                    representedURL: tab.url,
                    primaryAction: .switchToSafariTab(windowId: tab.windowId, tabIndex: tab.tabIndex),
                    alternateActions: tab.url.map(CommandPanelSuggestion.urlActions) ?? [],
                    basePriority: 2,
                    lastUsedAt: record.lastUsedAt
                )
            }
            return nil
        }
    }
}

struct PasteAndGoCommandProvider: CommandPanelSuggestionProviding {
    let providerName = "Paste and Go"

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard state.mode == .search, state.activeScope == nil || state.activeScope == .all, let url = context.clipboardURL else { return [] }
        let normalizedClipboard = CommandPanelRecentStore.normalized(url)
        let exactQueryURL: URL? = { if case .url(let parsed) = URLParser().parse(query) { return parsed }; return nil }()
        if let exactQueryURL, CommandPanelRecentStore.normalized(exactQueryURL) == normalizedClipboard { return [] }
        return [CommandPanelSuggestion(
            id: "paste-and-go-\(url.absoluteString)",
            title: "Paste and Go",
            subtitle: url.absoluteString,
            kind: .pasteAndGo,
            scope: .all,
            representedURL: url,
            primaryAction: .openURL(url),
            alternateActions: CommandPanelSuggestion.urlActions(url),
            basePriority: -100
        )]
    }
}

struct BasicURLSearchProvider: CommandPanelSuggestionProviding {
    let providerName = "URL/Search"

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard state.activeScope == nil || state.activeScope == .all else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return [CommandPanelSuggestion(id: "placeholder-search-empty", title: "Start typing to search or paste a link", subtitle: "Search, enter a URL, switch Safari tabs, open bookmarks, or type / for scopes", kind: .search, scope: .all, representedURL: nil, primaryAction: .noop("Enter a query"), basePriority: 990)]
        }
        if case .url(let url) = URLParser().parse(trimmed) {
            return [CommandPanelSuggestion(id: "url-\(url.absoluteString)", title: "Open \(url.absoluteString)", subtitle: "Open in a new Safari tab", kind: .url, scope: .all, representedURL: url, primaryAction: .openURL(url), alternateActions: CommandPanelSuggestion.urlActions(url), basePriority: CommandPaletteRanking.rank(for: .url))]
        }
        return [CommandPanelSuggestion(id: "search-\(trimmed)", title: "Search for “\(trimmed)”", subtitle: "Search the web", kind: .search, scope: .all, representedURL: nil, primaryAction: .search(trimmed), basePriority: CommandPaletteRanking.rank(for: .search))]
    }
}

@MainActor
struct SafariTabCommandProvider: CommandPanelSuggestionProviding {
    let providerName = "Safari Tabs"

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard state.activeScope == nil || state.activeScope == .all || state.activeScope == .liveTabs else { return [] }
        if let error = context.safariTabError, context.safariTabs.isEmpty {
            return [CommandPanelSuggestion(id: "safari-tabs-permission", title: "Safari tabs unavailable", subtitle: error.localizedDescription, kind: .permission, scope: .liveTabs, representedURL: nil, primaryAction: .noop(error.localizedDescription), basePriority: CommandPaletteRanking.rank(for: .permission))]
        }
        if context.safariTabs.isEmpty, state.activeScope == .liveTabs {
            return [CommandPanelSuggestion(id: "safari-tabs-empty", title: "No Safari tabs found", subtitle: "Open tabs in Safari to switch to them here", kind: .permission, scope: .liveTabs, representedURL: nil, primaryAction: .noop("No tabs"), basePriority: 900)]
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tabs: [SafariTabSnapshot]
        if trimmed.isEmpty {
            tabs = Array(context.safariTabs.prefix(CommandPanelSuggestionLimits.emptySourceCandidates))
        } else {
            let matches = Array(context.safariTabs.lazy.filter { tab in
                (tab.title ?? "").lowercased().contains(trimmed)
                    || (tab.url?.absoluteString ?? "").lowercased().contains(trimmed)
                    || (tab.windowTitle ?? "").lowercased().contains(trimmed)
            }.prefix(CommandPanelSuggestionLimits.querySourceCandidates))
            tabs = matches.isEmpty
                ? Array(context.safariTabs.prefix(CommandPanelSuggestionLimits.fallbackFuzzyCandidates))
                : matches
        }
        return tabs.map { tab in
            let title = tab.title ?? tab.url?.absoluteString ?? "Untitled Safari Tab"
            let subtitle = [tab.url?.absoluteString, tab.isActive ? "Active" : nil, "Window \(tab.windowId)"].compactMap { $0 }.joined(separator: " • ")
            return CommandPanelSuggestion(id: "safari-tab-\(tab.windowId)-\(tab.tabIndex)", title: title, subtitle: subtitle.isEmpty ? "Safari tab" : subtitle, kind: .safariTab, scope: .liveTabs, representedURL: tab.url, primaryAction: .switchToSafariTab(windowId: tab.windowId, tabIndex: tab.tabIndex), alternateActions: tab.url.map(CommandPanelSuggestion.urlActions) ?? [], basePriority: CommandPaletteRanking.rank(for: .safariTab))
        }
    }
}

struct RecentURLCommandProvider: CommandPanelSuggestionProviding {
    let providerName = "Recents"

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard state.activeScope == nil || state.activeScope == .all || state.activeScope == .recents else { return [] }
        if context.recentItems.isEmpty, state.activeScope == .recents {
            return [CommandPanelSuggestion(id: "recents-empty", title: "No recent items yet", subtitle: "Open URLs or searches from Arklike to see them here", kind: .permission, scope: .recents, representedURL: nil, primaryAction: .noop("No recents"), basePriority: 900)]
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let recentItems: [CommandPanelRecentItem]
        if trimmed.isEmpty {
            recentItems = Array(context.recentItems.prefix(CommandPanelSuggestionLimits.emptySourceCandidates))
        } else {
            let matches = Array(context.recentItems.lazy.filter { item in
                (item.title ?? "").lowercased().contains(trimmed)
                    || item.url.absoluteString.lowercased().contains(trimmed)
                    || (item.safariProfileHint ?? "").lowercased().contains(trimmed)
            }.prefix(CommandPanelSuggestionLimits.querySourceCandidates))
            recentItems = matches.isEmpty
                ? Array(context.recentItems.prefix(CommandPanelSuggestionLimits.fallbackFuzzyCandidates))
                : matches
        }
        return recentItems.map { item in
            let title = item.title?.isEmpty == false ? item.title! : item.url.absoluteString
            return CommandPanelSuggestion(id: "recent-\(item.url.absoluteString)", title: title, subtitle: [item.url.absoluteString, "Recent", item.openCount > 1 ? "\(item.openCount)x" : nil].compactMap { $0 }.joined(separator: " • "), kind: .historyOrRecent, scope: .recents, representedURL: item.url, primaryAction: .openURL(item.url), alternateActions: [CommandPanelAlternateAction(id: "copy-url", title: "Copy URL", subtitle: item.url.absoluteString, iconSystemName: "doc.on.doc", action: .copyURL(item.url)), CommandPanelAlternateAction(id: "remove-recent", title: "Remove from suggestions", subtitle: "Remove this recent item", iconSystemName: "xmark.circle", action: .removeRecent(item.url))], basePriority: CommandPaletteRanking.rank(for: .historyOrRecent), lastUsedAt: item.lastAccessedAt)
        }
    }
}

struct SearchHistoryCommandProvider: CommandPanelSuggestionProviding {
    let providerName = "Search History"
    private let store = CommandPanelSearchHistoryStore.shared

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard state.activeScope == nil || state.activeScope == .all else { return [] }
        return store.matches(for: query).map { past in
            CommandPanelSuggestion(id: "search-history-\(past)", title: past, subtitle: "Previous search", kind: .searchHistory, scope: .all, representedURL: nil, primaryAction: .search(past), basePriority: CommandPaletteRanking.rank(for: .searchHistory))
        }
    }
}

struct WebSuggestionCommandProvider: CommandPanelSuggestionProviding {
    let providerName = "Web Suggestions"

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard state.activeScope == nil || state.activeScope == .all else { return [] }
        return context.webSuggestions.map { suggestion in
            CommandPanelSuggestion(id: "web-suggestion-\(suggestion)", title: suggestion, subtitle: "Search suggestion", kind: .webSuggestion, scope: .all, representedURL: nil, primaryAction: .search(suggestion), basePriority: CommandPaletteRanking.rank(for: .webSuggestion))
        }
    }
}

struct SearchShortcutCommandProvider: CommandPanelSuggestionProviding {
    let providerName = "Search Shortcuts"
    private let shortcuts: [(keyword: String, aliases: [String], name: String, template: String)] = [("g", ["google"], "Google", "https://www.google.com/search?q=%@"), ("ddg", ["duckduckgo"], "DuckDuckGo", "https://duckduckgo.com/?q=%@"), ("gh", ["github"], "GitHub", "https://github.com/search?q=%@"), ("yt", ["youtube"], "YouTube", "https://www.youtube.com/results?search_query=%@")]

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard state.activeScope == nil || state.activeScope == .all else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let candidate = parts.first?.trimmingCharacters(in: CharacterSet(charactersIn: ":")).lowercased() ?? ""
        let matched = shortcuts.first { $0.keyword == candidate || $0.aliases.contains(candidate) || trimmed.hasPrefix($0.keyword + ":") }
        if let shortcut = matched {
            let searchText = trimmed.hasPrefix(shortcut.keyword + ":") ? String(trimmed.dropFirst(shortcut.keyword.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines) : (parts.dropFirst().first ?? "")
            guard !searchText.isEmpty, let url = SearchEngineService.searchURL(for: searchText, template: shortcut.template) else { return [] }
            return [CommandPanelSuggestion(id: "site-shortcut-run-\(shortcut.keyword)-\(searchText)", title: "Search \(shortcut.name) for “\(searchText)”", subtitle: url.absoluteString, kind: .siteShortcut, scope: .all, representedURL: url, primaryAction: .openURL(url), alternateActions: CommandPanelSuggestion.urlActions(url), basePriority: CommandPaletteRanking.rank(for: .siteShortcut))]
        }
        return shortcuts.map { shortcut in
            CommandPanelSuggestion(id: "site-shortcut-\(shortcut.keyword)", title: "\(shortcut.keyword): Search \(shortcut.name)", subtitle: "Type \(shortcut.keyword) + space to search \(shortcut.name)", kind: .siteShortcut, scope: .all, representedURL: nil, primaryAction: .noop("Enter a query for \(shortcut.name)"), basePriority: CommandPaletteRanking.rank(for: .siteShortcut))
        }
    }
}

struct SafariBookmarkProvider: CommandPanelSuggestionProviding {
    let providerName = "Safari Bookmarks"

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard state.activeScope == nil || state.activeScope == .all || state.activeScope == .bookmarks else { return [] }
        let wantsBookmarks = state.activeScope == .bookmarks || query.localizedCaseInsensitiveContains("bookmark") || query.localizedCaseInsensitiveContains("favorite") || query.localizedCaseInsensitiveContains("saved")
        if context.bookmarks.isEmpty, let error = context.bookmarkError, wantsBookmarks {
            return [CommandPanelSuggestion(id: "bookmarks-unavailable", title: "Safari bookmarks unavailable", subtitle: error, kind: .permission, scope: .bookmarks, representedURL: nil, primaryAction: .openSettings(.permissions), basePriority: CommandPaletteRanking.rank(for: .permission))]
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bookmarks: [SafariBookmark]
        if trimmed.isEmpty {
            bookmarks = Array(context.bookmarks.prefix(CommandPanelSuggestionLimits.emptySourceCandidates))
        } else {
            let matches = Array(context.bookmarks.lazy.filter { bookmark in
                bookmark.title.lowercased().contains(trimmed)
                    || bookmark.url.absoluteString.lowercased().contains(trimmed)
                    || (bookmark.path ?? "").lowercased().contains(trimmed)
            }.prefix(CommandPanelSuggestionLimits.querySourceCandidates))
            bookmarks = matches.isEmpty
                ? Array(context.bookmarks.prefix(CommandPanelSuggestionLimits.fallbackFuzzyCandidates))
                : matches
        }
        return bookmarks.map { bookmark in
            let stale = SafariBookmarkStore.shared.isUsingStaleCache ? "Cached" : nil
            return CommandPanelSuggestion(id: bookmark.id, title: bookmark.title, subtitle: [bookmark.url.absoluteString, bookmark.path, stale].compactMap { $0 }.joined(separator: " • "), kind: .bookmark, scope: .bookmarks, representedURL: bookmark.url, primaryAction: .openURL(bookmark.url), alternateActions: CommandPanelSuggestion.urlActions(bookmark.url), basePriority: CommandPaletteRanking.rank(for: .bookmark))
        }
    }
}

struct ProfileCommandProvider: CommandPanelSuggestionProviding {
    let providerName = "Profiles"

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard state.activeScope == nil || state.activeScope == .all else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let profiles = ProfileStore.shared.profiles
        if profiles.isEmpty, trimmed.contains("profile") || trimmed.hasPrefix("p") {
            return [CommandPanelSuggestion(id: "profiles-empty", title: "No Safari profiles configured", subtitle: "Refresh profiles in Settings to discover Safari profiles", kind: .permission, scope: .all, representedURL: nil, primaryAction: .openSettings(.profiles), basePriority: CommandPaletteRanking.rank(for: .permission))]
        }
        return profiles.compactMap { profile in
            let aliases = ["profile", profile.displayName.lowercased(), "p\(profile.assignedNumber)", "profile \(profile.assignedNumber)"]
            guard trimmed.isEmpty || aliases.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) || trimmed.localizedCaseInsensitiveContains($0) }) || CommandPanelSuggestionRanker.fuzzyScore(query: trimmed, candidate: profile.displayName) > 0 else { return nil }
            return CommandPanelSuggestion(id: "profile-\(profile.assignedNumber)", title: profile.displayName, subtitle: "Safari Profile • Ctrl+\(profile.assignedNumber) • File > New \(profile.effectiveMenuName) Window", kind: .profile, scope: .all, representedURL: nil, primaryAction: .openProfile(profile.assignedNumber), alternateActions: [CommandPanelAlternateAction(id: "copy-profile", title: "Copy Profile Name", subtitle: profile.displayName, iconSystemName: "doc.on.doc", action: .copyText(profile.displayName)), CommandPanelAlternateAction(id: "profile-settings", title: "Open Profiles Settings", subtitle: "Manage profile mappings", iconSystemName: "gearshape", action: .openSettings(.profiles))], basePriority: CommandPaletteRanking.rank(for: .profile))
        }
    }
}

struct TrafficRuleCommandProvider: CommandPanelSuggestionProviding {
    let providerName = "Traffic Control"

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard state.activeScope == nil || state.activeScope == .all else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let rules = TrafficRuleStore.shared.rules
        var results: [CommandPanelSuggestion] = []
        if case .url(let url) = URLParser().parse(trimmed), let match = TrafficRuleMatcher().firstMatch(for: url, rules: rules) {
            let rule = match.rule
            results.append(ruleSuggestion(rule, titlePrefix: "Matching rule: ", representedURL: url, basePriority: 1))
        }
        if rules.isEmpty, trimmed.localizedCaseInsensitiveContains("traffic") || trimmed.localizedCaseInsensitiveContains("rule") || trimmed.localizedCaseInsensitiveContains("route") {
            return [CommandPanelSuggestion(id: "traffic-empty", title: "No Traffic Control rules", subtitle: "Open Traffic Control settings to add routing rules", kind: .permission, scope: .all, representedURL: nil, primaryAction: .openSettings(.trafficControl), basePriority: CommandPaletteRanking.rank(for: .permission))]
        }
        results.append(contentsOf: rules.compactMap { rule in
            let text = [rule.name, rule.pattern, "profile \(rule.targetProfileNumber)", rule.matcherType.rawValue, "traffic", "rule", "route"].joined(separator: " ")
            guard trimmed.isEmpty || text.localizedCaseInsensitiveContains(trimmed) || CommandPanelSuggestionRanker.fuzzyScore(query: trimmed, candidate: text) > 0 else { return nil }
            return ruleSuggestion(rule)
        })
        return results
    }

    private func ruleSuggestion(_ rule: TrafficRule, titlePrefix: String = "", representedURL: URL? = nil, basePriority: Int? = nil) -> CommandPanelSuggestion {
        let enabled = rule.enabled ? "Enabled" : "Disabled"
        let subtitle = "\(enabled) • \(rule.matcherType.rawValue): \(rule.pattern) • Profile \(rule.targetProfileNumber) • \(rule.openBehavior.rawValue)"
        return CommandPanelSuggestion(id: "traffic-rule-\(rule.id.uuidString)-\(titlePrefix.isEmpty ? "row" : "match")", title: "\(titlePrefix)\(rule.name)", subtitle: subtitle, kind: .trafficRule, scope: .all, representedURL: representedURL, primaryAction: .openSettings(.trafficControl), alternateActions: [CommandPanelAlternateAction(id: "copy-pattern", title: "Copy Rule Pattern", subtitle: rule.pattern, iconSystemName: "doc.on.doc", action: .copyText(rule.pattern)), CommandPanelAlternateAction(id: "traffic-settings", title: "Open Traffic Control Settings", subtitle: "Edit routing rules", iconSystemName: "gearshape", action: .openSettings(.trafficControl))], basePriority: basePriority ?? CommandPaletteRanking.rank(for: .trafficRule))
    }
}

struct SettingsCommandProvider: CommandPanelSuggestionProviding {
    let providerName = "Settings"

    func suggestions(for query: String, state: CommandPanelState, context: CommandPanelContext) -> [CommandPanelSuggestion] {
        guard state.activeScope == nil || state.activeScope == .all || state.activeScope == .settings else { return [] }
        let rows: [CommandPanelSuggestion] = [
            settingsRow("settings-general", "Open Settings", "Return to run this command", .openSettings(.general), "gearshape"),
            settingsRow("settings-permissions", "Open Permissions Settings", "Return to run this command", .openSettings(.permissions), "lock.shield"),
            settingsRow("settings-shortcuts", "Open Shortcuts Settings", "Return to run this command", .openSettings(.shortcuts), "keyboard"),
            settingsRow("settings-profiles", "Open Profiles Settings", "Return to run this command", .openSettings(.profiles), "person.crop.circle"),
            settingsRow("settings-traffic", "Open Traffic Control Settings", "Return to run this command", .openSettings(.trafficControl), "arrow.triangle.branch"),
            settingsRow("settings-diagnostics", "Open Diagnostics Settings", "Return to run this command", .openSettings(.diagnostics), "stethoscope"),
            settingsRow("settings-web-suggestions", "Toggle Web Suggestions", AppSettings.shared.webSearchSuggestionsEnabled ? "On • Return to toggle this setting" : "Off • Return to toggle this setting", .toggleWebSuggestions, "sparkles"),
            settingsRow("settings-duplicate-tabs", "Toggle Existing Tab Switching", AppSettings.shared.switchToExistingSafariTabInsteadOfOpeningDuplicate ? "On • Return to toggle this setting" : "Off • Return to toggle this setting", .toggleDuplicateTabSwitching, "rectangle.on.rectangle"),
            settingsRow("settings-clear-recents", "Clear Recents", "Return to run this command", .clearRecents, "trash"),
            settingsRow("settings-clear-history", "Clear Search History", "Return to run this command", .clearSearchHistory, "clock.arrow.circlepath"),
            settingsRow("settings-refresh-bookmarks", "Refresh Safari Bookmarks", "Return to run this command", .refreshSafariBookmarks, "book")
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }
        return rows.filter { $0.title.localizedCaseInsensitiveContains(trimmed) || $0.subtitle.localizedCaseInsensitiveContains(trimmed) || CommandPanelSuggestionRanker.fuzzyScore(query: trimmed, candidate: $0.title) > 0 }
    }

    private func settingsRow(_ id: String, _ title: String, _ subtitle: String, _ action: CommandPaletteAction, _ icon: String) -> CommandPanelSuggestion {
        CommandPanelSuggestion(id: id, title: title, subtitle: subtitle, kind: .settings, scope: .settings, iconSystemName: icon, representedURL: nil, primaryAction: action, basePriority: CommandPaletteRanking.rank(for: .settings))
    }
}
