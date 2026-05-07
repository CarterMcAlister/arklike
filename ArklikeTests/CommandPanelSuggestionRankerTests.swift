import XCTest
@testable import Arklike

@MainActor
final class CommandPanelSuggestionRankerTests: XCTestCase {
    private let ranker = CommandPanelSuggestionRanker()

    func testURLQueryPrioritizesExistingTabAndKnownDestinationOverOpenURLAndSearch() {
        let url = URL(string: "https://example.com")!
        let suggestions = [
            suggestion(id: "ranker-test-search-url", title: "Search for “example.com”", kind: .search, representedURL: nil, action: .search("example.com"), basePriority: 80),
            suggestion(id: "ranker-test-open-url", title: "Open https://example.com", kind: .url, representedURL: url, action: .openURL(url), basePriority: 10),
            suggestion(id: "ranker-test-traffic-url", title: "Matching rule: Example", kind: .trafficRule, representedURL: url, action: .openSettings(.trafficControl), basePriority: 1),
            suggestion(id: "ranker-test-bookmark-url", title: "Example", kind: .bookmark, representedURL: url, action: .openURL(url), basePriority: 30),
            suggestion(id: "ranker-test-tab-url", title: "Example", subtitle: "https://example.com • Window 1", kind: .safariTab, representedURL: url, action: .switchToSafariTab(windowId: 1, tabIndex: 0), basePriority: 20)
        ]

        let ranked = ranker.rank(suggestions, query: "example.com", activeScope: nil, usageStore: .shared)

        XCTAssertEqual(ranked.first?.kind, .safariTab)
        XCTAssertLessThan(index(of: .bookmark, in: ranked), index(of: .url, in: ranked))
        XCTAssertLessThan(index(of: .trafficRule, in: ranked), index(of: .url, in: ranked))
        XCTAssertLessThan(index(of: .url, in: ranked), index(of: .search, in: ranked))
    }

    func testKnownDestinationBeatsGenericSearchFallback() {
        let url = URL(string: "https://developer.example.com/docs")!
        let suggestions = [
            suggestion(id: "ranker-test-search-docs", title: "Search for “docs”", kind: .search, representedURL: nil, action: .search("docs"), basePriority: 80),
            suggestion(id: "ranker-test-bookmark-docs", title: "Docs", subtitle: "https://developer.example.com/docs", kind: .bookmark, representedURL: url, action: .openURL(url), basePriority: 30)
        ]

        let ranked = ranker.rank(suggestions, query: "docs", activeScope: nil, usageStore: .shared)

        XCTAssertEqual(ranked.first?.kind, .bookmark)
    }

    func testExplicitSettingsQueryLetsSettingsOutrankGenericMatches() {
        let url = URL(string: "https://example.com/settings")!
        let suggestions = [
            suggestion(id: "ranker-test-bookmark-settings", title: "Settings docs", subtitle: url.absoluteString, kind: .bookmark, representedURL: url, action: .openURL(url), basePriority: 30),
            suggestion(id: "ranker-test-open-settings", title: "Open Settings", subtitle: "Return to run this command", kind: .settings, representedURL: nil, action: .openSettings(.general), basePriority: 90)
        ]

        let ranked = ranker.rank(suggestions, query: "settings", activeScope: nil, usageStore: .shared)

        XCTAssertEqual(ranked.first?.kind, .settings)
    }

    func testEmptyQueryPromotesActionableItemsAndDemotesPlaceholder() {
        let url = URL(string: "https://example.com")!
        let suggestions = [
            suggestion(id: "ranker-test-placeholder", title: "Start typing to search or paste a link", kind: .search, representedURL: nil, action: .noop("Enter a query"), basePriority: 990),
            suggestion(id: "ranker-test-tab-empty", title: "Example Tab", subtitle: "https://example.com • Active • Window 1", kind: .safariTab, representedURL: url, action: .switchToSafariTab(windowId: 1, tabIndex: 0), basePriority: 20),
            suggestion(id: "ranker-test-frequent-empty", title: "Frequent Example", subtitle: "Frequently used • https://example.com", kind: .bookmark, representedURL: url, action: .openURL(url), basePriority: 2),
            suggestion(id: "ranker-test-paste-empty", title: "Paste and Go", subtitle: url.absoluteString, kind: .pasteAndGo, representedURL: url, action: .openURL(url), basePriority: -100)
        ]

        let ranked = ranker.rank(suggestions, query: "", activeScope: nil, usageStore: .shared)

        XCTAssertEqual(ranked.first?.kind, .pasteAndGo)
        XCTAssertEqual(ranked.last?.id, "ranker-test-placeholder")
    }

    private func suggestion(
        id: String,
        title: String,
        subtitle: String = "",
        kind: CommandPanelSuggestionKind,
        representedURL: URL?,
        action: CommandPaletteAction,
        basePriority: Int
    ) -> CommandPanelSuggestion {
        CommandPanelSuggestion(
            id: id,
            title: title,
            subtitle: subtitle,
            kind: kind,
            scope: .all,
            representedURL: representedURL,
            primaryAction: action,
            basePriority: basePriority
        )
    }

    private func index(of kind: CommandPanelSuggestionKind, in suggestions: [CommandPanelSuggestion]) -> Int {
        suggestions.firstIndex { $0.kind == kind } ?? Int.max
    }
}
