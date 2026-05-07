import XCTest
@testable import Arklike

final class CommandPanelSuggestionComputerTests: XCTestCase {
    private let computer = CommandPanelSuggestionComputer()

    func testEmptyQueryCapsSuggestions() {
        let input = suggestionInput(
            query: "",
            recentItems: (0..<20).map { index in
                CommandPanelRecentItem(
                    url: URL(string: "https://example.com/\(index)")!,
                    title: "Example \(index)",
                    source: "test",
                    lastAccessedAt: Date().addingTimeInterval(Double(-index)),
                    openCount: 1,
                    safariWindowId: nil,
                    safariProfileHint: nil
                )
            }
        )

        let suggestions = computer.suggestions(input: input)

        XCTAssertLessThanOrEqual(suggestions.count, CommandPanelSuggestionLimits.visible)
    }

    func testNormalQueryKeepsVerbatimSearchFirstThenSearchSuggestions() {
        let input = suggestionInput(
            query: "swift",
            webSuggestions: ["swift concurrency"],
            searchHistoryQueries: ["swift testing"]
        )

        let suggestions = computer.suggestions(input: input)

        XCTAssertEqual(suggestions.first?.kind, .search)
        XCTAssertEqual(suggestions.first?.primaryAction, .search("swift"))
        XCTAssertTrue(suggestions.dropFirst().prefix(2).contains { $0.kind == .searchHistory })
        XCTAssertTrue(suggestions.dropFirst().prefix(2).contains { $0.kind == .webSuggestion })
    }

    func testURLQueryPrioritizesURLOpenBehavior() {
        let url = URL(string: "https://example.com")!
        let input = suggestionInput(query: url.absoluteString)

        let suggestions = computer.suggestions(input: input)

        XCTAssertEqual(suggestions.first?.kind, .url)
        XCTAssertEqual(suggestions.first?.representedURL, url)
    }

    func testScopePickerReturnsScopeSuggestions() {
        let input = suggestionInput(mode: .scopePicker, scopePickerQuery: "tab")

        let suggestions = computer.suggestions(input: input)

        XCTAssertTrue(suggestions.contains { $0.kind == .scope && $0.scope == .liveTabs })
    }

    func testActionModeReturnsActionsForSelectedSuggestion() {
        let url = URL(string: "https://example.com")!
        let source = CommandPanelSuggestion(
            id: "test-recent",
            title: "Example",
            subtitle: url.absoluteString,
            kind: .historyOrRecent,
            scope: .recents,
            representedURL: url,
            primaryAction: .openURL(url),
            basePriority: 0
        )
        let input = suggestionInput(mode: .actions, actionSourceSuggestion: source)

        let suggestions = computer.suggestions(input: input)

        XCTAssertTrue(suggestions.contains { $0.kind == .action && $0.primaryAction == .openURL(url) })
        XCTAssertTrue(suggestions.contains { $0.kind == .action && $0.primaryAction == .copyURL(url) })
        XCTAssertTrue(suggestions.contains { $0.kind == .action && $0.primaryAction == .removeRecent(url) })
    }

    func testSearchResultsAreCapped() {
        let input = suggestionInput(
            query: "example",
            bookmarks: (0..<40).map { index in
                SafariBookmark(
                    id: "bookmark-\(index)",
                    title: "Example Bookmark \(index)",
                    url: URL(string: "https://example.com/bookmark/\(index)")!,
                    path: nil
                )
            }
        )

        let suggestions = computer.suggestions(input: input)

        XCTAssertLessThanOrEqual(suggestions.count, CommandPanelSuggestionLimits.visible)
    }

    private func suggestionInput(
        mode: CommandPanelMode = .search,
        query: String = "",
        activeScope: CommandPanelSearchScope? = nil,
        scopePickerQuery: String = "",
        actionSourceSuggestion: CommandPanelSuggestion? = nil,
        recentItems: [CommandPanelRecentItem] = [],
        safariTabs: [SafariTabSnapshot] = [],
        safariTabError: SafariAutomationError? = nil,
        clipboardURL: URL? = nil,
        webSuggestions: [String] = [],
        bookmarks: [SafariBookmark] = [],
        bookmarkError: String? = nil,
        isUsingStaleBookmarkCache: Bool = false,
        profiles: [Profile] = [],
        trafficRules: [TrafficRule] = [],
        usageRecords: [String: CommandPanelUsageRecord] = [:],
        searchHistoryQueries: [String] = [],
        webSearchSuggestionsEnabled: Bool = true,
        switchToExistingSafariTabInsteadOfOpeningDuplicate: Bool = false
    ) -> CommandPanelSuggestionInput {
        CommandPanelSuggestionInput(
            mode: mode,
            query: query,
            activeScope: activeScope,
            scopePickerQuery: scopePickerQuery,
            actionSourceSuggestion: actionSourceSuggestion,
            recentItems: recentItems,
            safariTabs: safariTabs,
            safariTabError: safariTabError,
            clipboardURL: clipboardURL,
            webSuggestions: webSuggestions,
            bookmarks: bookmarks,
            bookmarkError: bookmarkError,
            isUsingStaleBookmarkCache: isUsingStaleBookmarkCache,
            profiles: profiles,
            trafficRules: trafficRules,
            usageRecords: usageRecords,
            searchHistoryQueries: searchHistoryQueries,
            webSearchSuggestionsEnabled: webSearchSuggestionsEnabled,
            switchToExistingSafariTabInsteadOfOpeningDuplicate: switchToExistingSafariTabInsteadOfOpeningDuplicate
        )
    }
}
