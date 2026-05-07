import Foundation

struct CommandPanelSuggestionInput: Sendable {
    let mode: CommandPanelMode
    let query: String
    let activeScope: CommandPanelSearchScope?
    let scopePickerQuery: String
    let actionSourceSuggestion: CommandPanelSuggestion?

    let recentItems: [CommandPanelRecentItem]
    let safariTabs: [SafariTabSnapshot]
    let safariTabError: SafariAutomationError?
    let clipboardURL: URL?
    let webSuggestions: [String]
    let bookmarks: [SafariBookmark]
    let bookmarkError: String?
    let isUsingStaleBookmarkCache: Bool
    let profiles: [Profile]
    let trafficRules: [TrafficRule]
    let usageRecords: [String: CommandPanelUsageRecord]
    let searchHistoryQueries: [String]
    let webSearchSuggestionsEnabled: Bool
    let switchToExistingSafariTabInsteadOfOpeningDuplicate: Bool
}
