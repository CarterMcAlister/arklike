import XCTest
@testable import Arklike

final class CommandPanelPerformanceTests: XCTestCase {
    private let computer = CommandPanelSuggestionComputer()

    func testLargeSyntheticDatasetsStayWithinSuggestionBudget() {
        let input = CommandPanelSuggestionInput(
            mode: .search,
            query: "developer docs",
            activeScope: nil,
            scopePickerQuery: "",
            actionSourceSuggestion: nil,
            recentItems: Self.recents(count: 1_000),
            safariTabs: Self.tabs(count: 1_000),
            safariTabError: nil,
            clipboardURL: nil,
            webSuggestions: ["developer docs swift", "developer documentation"],
            bookmarks: Self.bookmarks(count: 10_000),
            bookmarkError: nil,
            isUsingStaleBookmarkCache: false,
            profiles: Self.profiles(),
            trafficRules: Self.rules(count: 250),
            usageRecords: Self.usageRecords(count: 1_000),
            searchHistoryQueries: (0..<1_000).map { "developer query \($0)" },
            webSearchSuggestionsEnabled: true,
            switchToExistingSafariTabInsteadOfOpeningDuplicate: true,
            searchShortcuts: SearchShortcut.defaults
        )

        let start = ContinuousClock.now
        let suggestions = computer.suggestions(input: input)
        let elapsed = start.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000

        XCTAssertLessThanOrEqual(suggestions.count, CommandPanelSuggestionLimits.visible)
        XCTAssertLessThan(milliseconds, 1_000, "Large command-panel suggestion compute should stay comfortably below one second.")
    }

    func testUnavailableSafariStateProducesRowsWithoutAutomation() {
        let input = CommandPanelSuggestionInput(
            mode: .search,
            query: "tabs",
            activeScope: .liveTabs,
            scopePickerQuery: "",
            actionSourceSuggestion: nil,
            recentItems: [],
            safariTabs: [],
            safariTabError: .permissionDenied,
            clipboardURL: nil,
            webSuggestions: [],
            bookmarks: [],
            bookmarkError: "Bookmarks unavailable",
            isUsingStaleBookmarkCache: false,
            profiles: [],
            trafficRules: [],
            usageRecords: [:],
            searchHistoryQueries: [],
            webSearchSuggestionsEnabled: false,
            switchToExistingSafariTabInsteadOfOpeningDuplicate: false,
            searchShortcuts: []
        )

        let suggestions = computer.suggestions(input: input)

        XCTAssertTrue(suggestions.contains { $0.kind == .permission })
    }

    private static func bookmarks(count: Int) -> [SafariBookmark] {
        (0..<count).map { index in
            SafariBookmark(
                id: "bookmark-\(index)",
                title: "Developer Bookmark \(index)",
                url: URL(string: "https://developer\(index % 50).example.com/docs/\(index)")!,
                path: "Folder \(index % 20)"
            )
        }
    }

    private static func tabs(count: Int) -> [SafariTabSnapshot] {
        (0..<count).map { index in
            SafariTabSnapshot(
                windowId: index / 20,
                windowTitle: "Window \(index / 20)",
                tabIndex: index % 20 + 1,
                title: "Developer Tab \(index)",
                url: URL(string: "https://tabs.example.com/\(index)"),
                isActive: index == 0
            )
        }
    }

    private static func recents(count: Int) -> [CommandPanelRecentItem] {
        (0..<count).map { index in
            CommandPanelRecentItem(
                url: URL(string: "https://recent.example.com/\(index)")!,
                title: "Recent Developer \(index)",
                source: "test",
                lastAccessedAt: Date().addingTimeInterval(Double(-index)),
                openCount: index % 10 + 1,
                safariWindowId: nil,
                safariProfileHint: nil
            )
        }
    }

    private static func profiles() -> [Profile] {
        (1...9).map { index in
            Profile(displayName: "Profile \(index)", assignedNumber: index, safariMenuTitle: "Profile \(index)")
        }
    }

    private static func rules(count: Int) -> [TrafficRule] {
        (0..<count).map { index in
            TrafficRule(name: "Rule \(index)", order: index, matcherType: .domain, pattern: "example\(index).com", targetProfileNumber: index % 9 + 1)
        }
    }

    private static func usageRecords(count: Int) -> [String: CommandPanelUsageRecord] {
        Dictionary(uniqueKeysWithValues: (0..<count).map { index in
            (
                "recent-https://recent.example.com/\(index)",
                CommandPanelUsageRecord(
                    id: "recent-https://recent.example.com/\(index)",
                    kind: CommandPanelSuggestionKind.historyOrRecent.rawValue,
                    count: index % 20 + 1,
                    lastUsedAt: Date().addingTimeInterval(Double(-index)),
                    lastQuery: "developer"
                )
            )
        })
    }
}
