import Foundation

@MainActor
final class CommandPanelSuggestionManager {
    private let usageStore: CommandPanelUsageStore
    private let searchHistoryStore: CommandPanelSearchHistoryStore

    init(
        usageStore: CommandPanelUsageStore? = nil,
        searchHistoryStore: CommandPanelSearchHistoryStore? = nil
    ) {
        self.usageStore = usageStore ?? .shared
        self.searchHistoryStore = searchHistoryStore ?? .shared
    }

    func recordSelection(_ suggestion: CommandPanelSuggestion, query: String) {
        usageStore.record(suggestion, query: query)
        if case .search(let searchText) = suggestion.primaryAction {
            searchHistoryStore.record(searchText)
        }
    }
}
