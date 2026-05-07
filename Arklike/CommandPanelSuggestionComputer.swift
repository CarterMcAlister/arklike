import Foundation

struct CommandPanelSuggestionComputer: Sendable {
    private let providers: [CommandPanelSuggestionProviding]
    private let ranker = CommandPanelSuggestionRanker()

    init(providers: [CommandPanelSuggestionProviding] = [
        PasteAndGoCommandProvider(),
        FrequentItemsCommandProvider(),
        SearchShortcutCommandProvider(),
        BasicURLSearchProvider(),
        SafariTabCommandProvider(),
        SafariBookmarkProvider(),
        RecentURLCommandProvider(),
        SearchHistoryCommandProvider(),
        WebSuggestionCommandProvider(),
        ProfileCommandProvider(),
        TrafficRuleCommandProvider(),
        SettingsCommandProvider()
    ]) {
        self.providers = providers
    }

    func suggestions(input: CommandPanelSuggestionInput) -> [CommandPanelSuggestion] {
        switch input.mode {
        case .scopePicker:
            return scopeSuggestions(query: input.scopePickerQuery)
        case .actions:
            return actionSuggestions(for: input.actionSourceSuggestion)
        case .search:
            let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let all = providers.flatMap { provider in
                provider.suggestions(for: query, input: input)
            }
            let deduped = deduplicated(all)
            let ranked = PerformanceTimer.measure("command palette ranker") {
                ranker.rank(
                    deduped,
                    query: query,
                    activeScope: input.activeScope,
                    usageRecords: input.usageRecords
                )
            }
            return cappedSearchSuggestions(ranked, query: query, activeScope: input.activeScope)
        }
    }

    private func scopeSuggestions(query: String) -> [CommandPanelSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopes = CommandPanelSearchScope.cyclingOrder.filter { scope in
            trimmed.isEmpty
                || scope.title.localizedCaseInsensitiveContains(trimmed)
                || scope.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
                || CommandPanelSuggestionRanker.fuzzyScore(query: trimmed, candidate: scope.title) > 0
        }
        if scopes.isEmpty {
            return [CommandPanelSuggestion(
                id: "scope-none",
                title: "No matching scopes",
                subtitle: "Try Recents, Live Tabs, or Bookmarks",
                kind: .permission,
                scope: nil,
                iconSystemName: "magnifyingglass",
                representedURL: nil,
                primaryAction: .noop("No matching scopes"),
                basePriority: 999
            )]
        }
        return scopes.map { scope in
            CommandPanelSuggestion(
                id: "scope-\(scope.rawValue)",
                title: scope.title,
                subtitle: "Search \(scope.title.lowercased())",
                kind: .scope,
                scope: scope,
                iconSystemName: scope.iconName,
                representedURL: nil,
                primaryAction: .activateScope(scope),
                basePriority: 0
            )
        }
    }

    private func actionSuggestions(for source: CommandPanelSuggestion?) -> [CommandPanelSuggestion] {
        guard let source else {
            return [CommandPanelSuggestion(
                id: "action-none",
                title: "No actions available",
                subtitle: "Return to search and select a result",
                kind: .permission,
                scope: nil,
                representedURL: nil,
                primaryAction: .noop("No actions"),
                basePriority: 999
            )]
        }
        var actions: [CommandPanelAlternateAction] = []
        actions.append(CommandPanelAlternateAction(
            id: "primary",
            title: primaryActionTitle(for: source),
            subtitle: source.subtitle,
            iconSystemName: source.iconSystemName,
            action: source.primaryAction
        ))
        actions.append(contentsOf: source.alternateActions)
        if let url = source.representedURL, !actions.contains(where: { $0.id == "copy-url" }) {
            actions.append(CommandPanelAlternateAction(
                id: "copy-url",
                title: "Copy URL",
                subtitle: url.absoluteString,
                iconSystemName: "doc.on.doc",
                action: .copyURL(url)
            ))
        }
        if source.kind == .historyOrRecent, let url = source.representedURL, !actions.contains(where: { $0.id == "remove-recent" }) {
            actions.append(CommandPanelAlternateAction(
                id: "remove-recent",
                title: "Remove from suggestions",
                subtitle: "Remove this recent item from Arklike suggestions",
                iconSystemName: "xmark.circle",
                action: .removeRecent(url)
            ))
        }
        if source.kind == .profile, !actions.contains(where: { $0.id == "profile-settings" }) {
            actions.append(CommandPanelAlternateAction(id: "profile-settings", title: "Open Profiles Settings", subtitle: "Manage Safari profiles", iconSystemName: "gearshape", action: .openSettings(.profiles)))
        }
        if source.kind == .trafficRule, !actions.contains(where: { $0.id == "traffic-settings" }) {
            actions.append(CommandPanelAlternateAction(id: "traffic-settings", title: "Open Traffic Control Settings", subtitle: "Edit traffic rules", iconSystemName: "gearshape", action: .openSettings(.trafficControl)))
        }
        return actions.map { action in
            CommandPanelSuggestion(
                id: "action-\(source.id)-\(action.id)",
                title: action.title,
                subtitle: action.subtitle,
                kind: .action,
                scope: nil,
                iconSystemName: action.iconSystemName,
                representedURL: source.representedURL,
                primaryAction: action.action,
                basePriority: 0
            )
        }
    }

    private func deduplicated(_ suggestions: [CommandPanelSuggestion]) -> [CommandPanelSuggestion] {
        var seen: Set<String> = []
        var result: [CommandPanelSuggestion] = []
        for suggestion in suggestions {
            guard !seen.contains(suggestion.id) else { continue }
            seen.insert(suggestion.id)
            result.append(suggestion)
        }
        return result
    }

    private func cappedSearchSuggestions(
        _ ranked: [CommandPanelSuggestion],
        query: String,
        activeScope: CommandPanelSearchScope?
    ) -> [CommandPanelSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(ranked.prefix(CommandPanelSuggestionLimits.visible)) }
        guard activeScope == nil || activeScope == .all else { return Array(ranked.prefix(CommandPanelSuggestionLimits.visible)) }
        if case .url = URLParser().parse(trimmed) { return Array(ranked.prefix(CommandPanelSuggestionLimits.visible)) }

        let verbatimSearch = ranked.first(where: isVerbatimSearchSuggestion)
        let searchSuggestions = ranked.filter(isSearchSuggestion)

        var selected = [CommandPanelSuggestion]()
        if let exactShortcut = ranked.first(where: { $0.isExactShortcutMatch }) {
            selected.append(exactShortcut)
        }

        var selectedIDs = Set(selected.map(\.id))
        if let verbatimSearch, !selectedIDs.contains(verbatimSearch.id) {
            selected.append(verbatimSearch)
            selectedIDs.insert(verbatimSearch.id)
        }

        for suggestion in searchSuggestions where !selectedIDs.contains(suggestion.id) {
            guard selected.count < CommandPanelSuggestionLimits.searchSuggestionReserve else { break }
            selected.append(suggestion)
            selectedIDs.insert(suggestion.id)
        }

        guard !selected.isEmpty else { return Array(ranked.prefix(CommandPanelSuggestionLimits.visible)) }

        for suggestion in ranked where !selectedIDs.contains(suggestion.id) {
            guard selected.count < CommandPanelSuggestionLimits.visible else { break }
            selected.append(suggestion)
            selectedIDs.insert(suggestion.id)
        }
        return selected
    }

    private func isVerbatimSearchSuggestion(_ suggestion: CommandPanelSuggestion) -> Bool {
        suggestion.kind == .search
    }

    private func isSearchSuggestion(_ suggestion: CommandPanelSuggestion) -> Bool {
        switch suggestion.kind {
        case .webSuggestion, .searchHistory:
            true
        default:
            false
        }
    }

    private func primaryActionTitle(for source: CommandPanelSuggestion) -> String {
        switch source.kind {
        case .safariTab: "Switch to Tab"
        case .search, .webSuggestion, .searchHistory: "Search the Web"
        case .scope: "Activate Scope"
        case .settings, .trafficRule: "Run Command"
        case .profile: "Switch Profile"
        default: "Open in Safari"
        }
    }
}
