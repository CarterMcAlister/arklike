# Command Palette Off-Main Refactor Spec

## Objective

Refactor Arklike's command palette so opening the palette and typing into it never blocks on non-UI work.

The palette must show, become key, and focus the text input before any expensive work runs. Suggestion generation, ranking, fuzzy matching, and cache rebuilding must run off the main actor using immutable snapshots. Clipboard reading must be deferred until after the palette is interactive. Synchronous AppleScript window enumeration must be removed from the `FrontmostSafariMonitor.refresh(...)` hot path.

## Success Criteria

- Opening the command palette displays the panel immediately.
- Text entry is responsive immediately after the palette opens.
- No suggestion provider, ranker, fuzzy matcher, usage scoring, or empty-query cache rebuild runs on `MainActor`.
- No pasteboard read runs before the palette is visible and input focus has been requested.
- Stale or cancelled suggestion computations never overwrite newer query results.
- UI mutations remain on `MainActor`.
- Existing command palette behavior remains intact:
  - Maximum visible search suggestions remains `CommandPanelSuggestionLimits.visible`.
  - Verbatim search remains first for normal typed search queries.
  - Web suggestions and search history remain immediately after verbatim search when applicable.
  - URL queries continue prioritizing URL/open behavior.
  - Scope picker and action mode continue working.
- Existing tests pass.

## Non-Goals

- Do not rewrite the command palette UI.
- Do not move AppKit panel/window/focus code off main.
- Do not move `NSEvent` monitor installation, CG event tap installation, Carbon hotkey registration, or AX observer run-loop registration off main.
- Do not change release/versioning behavior.
- Do not change Homebrew cask behavior.

## Files To Add

- `Arklike/CommandPanelSuggestionInput.swift`
- `Arklike/CommandPanelSuggestionComputer.swift`
- `Arklike/PerformanceTimer.swift`
- `Arklike/SafariWindowIDResolver.swift`

Add each new Swift file to `Arklike.xcodeproj/project.pbxproj` under the `Arklike` target.

## Files To Modify

- `Arklike/CommandPaletteController.swift`
- `Arklike/CommandPanelSuggestionRanker.swift`
- `Arklike/CommandPaletteProviders.swift`
- `Arklike/CommandPanelStores.swift`
- `Arklike/CommandPaletteModels.swift`
- `Arklike/FrontmostSafariMonitor.swift`
- `Arklike.xcodeproj/project.pbxproj`
- Tests under `ArklikeTests` as needed.

## Phase 1: Add Performance Timing Utility

Create `Arklike/PerformanceTimer.swift`:

```swift
import Foundation
import os

enum PerformanceTimer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.arklike.app",
        category: "Performance"
    )

    static func measure<T>(_ label: String, operation: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        let result = try operation()
        logIfSlow(label: label, start: start)
        return result
    }

    static func measureAsync<T>(_ label: String, operation: () async throws -> T) async rethrows -> T {
        let start = ContinuousClock.now
        let result = try await operation()
        logIfSlow(label: label, start: start)
        return result
    }

    private static func logIfSlow(label: String, start: ContinuousClock.Instant) {
        let duration = start.duration(to: .now)
        let milliseconds = Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        if milliseconds >= 25 {
            logger.info("\(label, privacy: .public) took \(milliseconds, privacy: .public)ms")
        }
    }
}
```

Use `PerformanceTimer.measure` around:

- `CommandPaletteController.show()` body.
- Clipboard read in `clipboardURLForPanelOpen()`.
- Suggestion compute in the background task.
- Ranker sorting/scoring.
- `FrontmostSafariMonitor.refresh(...)`.
- AppleScript window ID resolution.

Do not log through `Diagnostics.shared` from hot paths.

## Phase 2: Add Sendable Conformance To Value Models

Update value types used by off-main suggestion computation to conform to `Sendable`.

Required types:

- `CommandPanelMode`
- `CommandPanelSearchScope`
- `CommandPanelSuggestionKind`
- `CommandPanelAction`
- `CommandPanelAlternateAction`
- `CommandPanelSuggestion`
- `CommandPanelRecentItem`
- `CommandPanelUsageRecord`
- `SafariBookmark`
- `SafariTabSnapshot`
- `SafariWindowSnapshot`
- `SafariAutomationError`
- `Profile`
- `TrafficRule`
- `TrafficMatcherType`

Only mark pure value types as `Sendable`. Do not mark controllers, stores, or ObservableObjects as `Sendable`.

## Phase 3: Add Immutable Suggestion Input Snapshot

Create `Arklike/CommandPanelSuggestionInput.swift`:

```swift
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
    let profiles: [Profile]
    let trafficRules: [TrafficRule]
    let usageRecords: [String: CommandPanelUsageRecord]
    let searchHistoryQueries: [String]
}
```

Add snapshot accessors to stores in `CommandPanelStores.swift`:

```swift
var recordsSnapshot: [String: CommandPanelUsageRecord] { records }
var queriesSnapshot: [String] { queries }
```

These accessors remain main-actor isolated because the stores remain main-actor isolated.

Add this method to `CommandPaletteController`:

```swift
@MainActor
private func makeSuggestionInput() -> CommandPanelSuggestionInput {
    CommandPanelSuggestionInput(
        mode: state.mode,
        query: state.query,
        activeScope: state.activeScope,
        scopePickerQuery: state.scopePickerQuery,
        actionSourceSuggestion: state.actionSourceSuggestion,
        recentItems: recentStore.items,
        safariTabs: liveTabStore.tabs,
        safariTabError: liveTabStore.lastError,
        clipboardURL: clipboardURL,
        webSuggestions: webSuggestions,
        bookmarks: bookmarkStore.bookmarks,
        bookmarkError: bookmarkStore.lastError,
        profiles: ProfileStore.shared.profiles,
        trafficRules: TrafficRuleStore.shared.rules,
        usageRecords: CommandPanelUsageStore.shared.recordsSnapshot,
        searchHistoryQueries: CommandPanelSearchHistoryStore.shared.queriesSnapshot
    )
}
```

The snapshot must contain only value data. Do not include `CommandPanelState`, stores, controllers, managers, services, or ObservableObjects.

## Phase 4: Make The Ranker Pure And Non-Main

Remove `@MainActor` from `CommandPanelSuggestionRanker`.

Change the ranking API to accept usage records directly:

```swift
func rank(
    _ suggestions: [CommandPanelSuggestion],
    query: String,
    activeScope: CommandPanelSearchScope?,
    usageRecords: [String: CommandPanelUsageRecord]
) -> [CommandPanelSuggestion]
```

Remove all references to `CommandPanelUsageStore` from the ranker.

Add a pure usage-score helper:

```swift
private static func usageScore(
    for id: String,
    query: String,
    records: [String: CommandPanelUsageRecord]
) -> Double {
    guard let record = records[id] else { return 0 }
    let countScore = min(Double(record.count) * 8, 80)
    let age = max(0, Date().timeIntervalSince(record.lastUsedAt))
    let recencyScore = max(0, 30 - age / 86_400)
    let queryScore = !query.isEmpty && record.lastQuery.localizedCaseInsensitiveContains(query) ? 15 : 0
    return countScore + recencyScore + Double(queryScore)
}
```

Keep `fuzzyScore(query:candidate:)` pure and callable from tests.

Wrap ranking work in `PerformanceTimer.measure("command palette ranker")`.

## Phase 5: Add Pure Suggestion Computer

Create `Arklike/CommandPanelSuggestionComputer.swift`.

This type replaces main-actor `CommandPanelSuggestionManager.suggestions(...)` for suggestion computation. It must not be `@MainActor` and must not read singleton stores.

Required shape:

```swift
import Foundation

struct CommandPanelSuggestionComputer {
    private let ranker = CommandPanelSuggestionRanker()

    func suggestions(input: CommandPanelSuggestionInput) -> [CommandPanelSuggestion] {
        switch input.mode {
        case .scopePicker:
            return scopeSuggestions(query: input.scopePickerQuery)
        case .actions:
            return actionSuggestions(for: input.actionSourceSuggestion)
        case .search:
            let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let all = searchSuggestions(query: query, input: input)
            let deduped = deduplicated(all)
            let ranked = ranker.rank(
                deduped,
                query: query,
                activeScope: input.activeScope,
                usageRecords: input.usageRecords
            )
            return cappedSearchSuggestions(ranked, query: query, activeScope: input.activeScope)
        }
    }
}
```

Move these pure methods from `CommandPanelSuggestionManager` into `CommandPanelSuggestionComputer`:

- `scopeSuggestions(query:)`
- `actionSuggestions(for:)`
- `deduplicated(_:)`
- `cappedSearchSuggestions(_:query:activeScope:)`
- `isVerbatimSearchSuggestion(_:)`
- `isSearchSuggestion(_:)`
- `primaryActionTitle(for:)`

Preserve exact behavior.

## Phase 6: Refactor Providers To Snapshot-Based Pure Providers

Update provider protocol in `CommandPaletteModels.swift`.

Replace current state/context-based calls with snapshot-based calls:

```swift
protocol CommandPanelSuggestionProviding {
    var providerName: String { get }
    func suggestions(for query: String, input: CommandPanelSuggestionInput) -> [CommandPanelSuggestion]
}
```

Update every provider in `CommandPaletteProviders.swift`.

Provider rules:

- Providers must not be `@MainActor`.
- Providers must not read shared stores or controllers.
- Providers must read all data from `CommandPanelSuggestionInput`.
- Providers may call pure helpers such as `URLParser`, `SearchEngineService.searchURL(for:template:)`, and static normalization helpers.

Required replacements:

- `context.recentItems` -> `input.recentItems`
- `context.safariTabs` -> `input.safariTabs`
- `context.safariTabError` -> `input.safariTabError`
- `context.clipboardURL` -> `input.clipboardURL`
- `context.webSuggestions` -> `input.webSuggestions`
- `context.bookmarks` -> `input.bookmarks`
- `context.bookmarkError` -> `input.bookmarkError`
- `ProfileStore.shared.profiles` -> `input.profiles`
- `TrafficRuleStore.shared.rules` -> `input.trafficRules`
- `CommandPanelSearchHistoryStore.shared.matches(for:)` -> pure filtering over `input.searchHistoryQueries`
- `CommandPanelUsageStore.shared.topRecords(limit:)` -> pure sorting over `input.usageRecords.values`
- `SafariBookmarkStore.shared.isUsingStaleCache` must not be read by providers. If stale cache text is needed, add `isUsingStaleBookmarkCache: Bool` to `CommandPanelSuggestionInput`; otherwise remove the stale subtitle component.

Add pure helpers where needed:

```swift
static func topUsageRecords(
    _ records: [String: CommandPanelUsageRecord],
    limit: Int
) -> [CommandPanelUsageRecord]
```

```swift
static func searchHistoryMatches(
    query: String,
    history: [String],
    limit: Int = 5
) -> [String]
```

`CommandPanelSuggestionComputer.searchSuggestions(query:input:)` must instantiate and call the providers in the same order currently used by `CommandPaletteController`:

1. `PasteAndGoCommandProvider`
2. `FrequentItemsCommandProvider`
3. `SearchShortcutCommandProvider`
4. `BasicURLSearchProvider`
5. `SafariTabCommandProvider`
6. `SafariBookmarkProvider`
7. `RecentURLCommandProvider`
8. `SearchHistoryCommandProvider`
9. `WebSuggestionCommandProvider`
10. `ProfileCommandProvider`
11. `TrafficRuleCommandProvider`
12. `SettingsCommandProvider`

## Phase 7: Refactor CommandPaletteController Refresh Flow

Replace synchronous suggestion refresh with generation-gated async computation.

In `CommandPaletteController`, replace:

```swift
private var refreshTask: Task<Void, Never>?
private var emptyQuerySuggestionCache: [CommandPaletteItem] = []
private var isEmptyQuerySuggestionCacheValid = false
private let suggestionManager: CommandPanelSuggestionManager
```

With:

```swift
private var refreshScheduleTask: Task<Void, Never>?
private var suggestionTask: Task<Void, Never>?
private var clipboardTask: Task<Void, Never>?
private var suggestionGeneration = 0
private let suggestionComputer = CommandPanelSuggestionComputer()
private let suggestionRecorder = CommandPanelSuggestionManager()
```

Keep `CommandPanelSuggestionManager` only for `recordSelection(...)`, or replace it with a smaller recorder. Do not use it for computing suggestions.

Update `show()`:

```swift
func show() {
    PerformanceTimer.measure("command palette show") {
        refreshScheduleTask?.cancel()
        suggestionTask?.cancel()
        clipboardTask?.cancel()
        CommandPanelWebSuggestionService.shared.cancel()

        webSuggestions = []
        clipboardURL = nil
        state.resetForOpen()
        state.setSuggestions([Self.loadingPlaceholderSuggestion])

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel: panel)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            panel.makeKey()
        }

        state.requestInputFocus()

        installKeyMonitor()
        installOutsideClickMonitor()
        installDismissEventTap()
        scheduleRefresh(delay: 0.05)
        scheduleDeferredClipboardRead()
    }
}
```

Add loading placeholder:

```swift
private static let loadingPlaceholderSuggestion = CommandPanelSuggestion(
    id: "placeholder-search-empty",
    title: "Start typing to search or paste a link",
    subtitle: "Suggestions are loading…",
    kind: .search,
    scope: .all,
    representedURL: nil,
    primaryAction: .noop("Enter a query"),
    basePriority: 990
)
```

Update `dismiss(...)` to cancel all tasks:

```swift
refreshScheduleTask?.cancel()
suggestionTask?.cancel()
clipboardTask?.cancel()
```

Replace `refreshItems()` with:

```swift
@MainActor
private func refreshItems() {
    startSuggestionCompute()
}
```

Add:

```swift
@MainActor
private func scheduleRefresh(delay: TimeInterval = 0) {
    refreshScheduleTask?.cancel()
    refreshScheduleTask = Task { [weak self] in
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } else {
            await Task.yield()
        }
        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard let self, self.panel?.isVisible == true else { return }
            self.startSuggestionCompute()
        }
    }
}
```

Add:

```swift
@MainActor
private func startSuggestionCompute() {
    suggestionTask?.cancel()
    suggestionGeneration += 1

    let generation = suggestionGeneration
    let input = makeSuggestionInput()
    let computer = suggestionComputer

    suggestionTask = Task(priority: .userInitiated) { [weak self, input, generation, computer] in
        let suggestions = await Task.detached(priority: .userInitiated) {
            PerformanceTimer.measure("command palette suggestion compute") {
                computer.suggestions(input: input)
            }
        }.value

        await MainActor.run {
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.panel?.isVisible == true else { return }
            guard self.suggestionGeneration == generation else { return }
            self.state.setSuggestions(suggestions)
            self.updateAutocomplete()
        }
    }
}
```

Remove these methods and all call sites:

- `shouldUseEmptyQuerySuggestionCache`
- `emptyQuerySuggestionsForCurrentClipboard()`
- `rebuildEmptyQuerySuggestionCache()`
- `invalidateEmptyQuerySuggestionCache()`
- `commandPanelContext(clipboardURL:webSuggestions:)`

Where cache invalidation is currently called, schedule a refresh if visible and do nothing otherwise.

## Phase 8: Defer Clipboard Read

Remove pasteboard read from `scheduleInitialRefresh()` entirely. Delete `scheduleInitialRefresh()` and replace it with `scheduleRefresh(delay:)` plus `scheduleDeferredClipboardRead()`.

Add:

```swift
@MainActor
private func scheduleDeferredClipboardRead() {
    clipboardTask?.cancel()
    clipboardTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard let self else { return }
            guard self.panel?.isVisible == true else { return }
            guard self.state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.clipboardURL = Self.clipboardURLForPanelOpen()
            self.scheduleRefresh(delay: 0)
        }
    }
}
```

Keep `clipboardURLForPanelOpen()` on main for this refactor. Wrap it in `PerformanceTimer.measure("command palette pasteboard read")`.

Do not read `NSPasteboard` before panel focus.

## Phase 9: Update Store Change Bindings

In `bindCachedStores()`, replace cache invalidation behavior with refresh scheduling.

For each store publisher:

```swift
Task { @MainActor in
    guard let self else { return }
    guard self.panel?.isVisible == true else { return }
    self.scheduleRefresh(delay: 0)
}
```

For `FrontmostSafariMonitor.shared.$snapshot`, preserve dismiss behavior when Safari is no longer frontmost, then schedule refresh if still visible.

Do not rebuild suggestions synchronously from any publisher callback.

## Phase 10: Keep Recording Selection On Main

`recordSelection(...)` remains main-actor because it mutates usage/search history stores.

Update call site in `perform(_:)`:

```swift
suggestionRecorder.recordSelection(item, query: state.query)
```

Remove suggestion computation responsibilities from `CommandPanelSuggestionManager`. The manager may either:

1. Be reduced to only `recordSelection(...)`, or
2. Be replaced with a new `CommandPanelSuggestionRecorder`.

If keeping the existing class, remove `@MainActor` only if it no longer touches main-actor stores. Otherwise keep `@MainActor` and use it only for recording.

## Phase 11: Remove Synchronous AppleScript From FrontmostSafariMonitor Refresh

`FrontmostSafariMonitor.refresh(...)` must not execute `NSAppleScript` synchronously.

Create `Arklike/SafariWindowIDResolver.swift`:

```swift
import Foundation

struct SafariWindowIDResolver {
    struct WindowSummary: Sendable {
        let id: Int
        let title: String?
    }

    static func resolve(title: String?) -> Int? {
        let windows = PerformanceTimer.measure("safari window id appleScript resolution") {
            enumeratedWindows()
        }
        guard !windows.isEmpty else { return nil }
        if let title, !title.isEmpty,
           let matched = windows.first(where: { $0.title == title }) {
            return matched.id
        }
        return windows.first?.id
    }

    private static func enumeratedWindows() -> [WindowSummary] {
        let script = """
        tell application "Safari"
            if (count of windows) is 0 then return ""
            set outputLines to {}
            repeat with safariWindow in windows
                set windowIdText to (id of safariWindow) as text
                set windowName to ""
                try
                    set windowName to name of safariWindow
                end try
                set end of outputLines to windowIdText & tab & windowName
            end repeat
            set AppleScript's text item delimiters to linefeed
            set outputText to outputLines as text
            set AppleScript's text item delimiters to ""
            return outputText
        end tell
        """

        var error: NSDictionary?
        guard let compiled = NSAppleScript(source: script) else { return [] }
        let descriptor = compiled.executeAndReturnError(&error)
        guard error == nil, let output = descriptor.stringValue, !output.isEmpty else { return [] }
        return output.components(separatedBy: .newlines).compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard let idText = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let id = Int(idText) else { return nil }
            let title = parts.dropFirst().joined(separator: "\t").nilIfEmpty
            return WindowSummary(id: id, title: title)
        }
    }
}
```

Move the existing `nilIfEmpty` string helper to a shared file if needed, or duplicate it privately in this file.

Modify `FrontmostSafariMonitor`:

- Add:

```swift
private var windowIDResolutionTask: Task<Void, Never>?
```

- In `stopAXObserver()`, cancel `windowIDResolutionTask`.
- In `accessibilityFocusedWindowContext(pid:)`, remove calls to:
  - `appleScriptWindowIdMatching(title:axWindowNumber:)`
  - `appleScriptEnumeratedWindows()`
- Set `safariWindowId` to `nil` in the immediate AX context.
- After publishing a Safari-frontmost snapshot with an active window title, call:

```swift
scheduleWindowIDResolution(pid: safariPID, title: activeWindow?.title)
```

Add:

```swift
private func scheduleWindowIDResolution(pid: pid_t, title: String?) {
    windowIDResolutionTask?.cancel()
    windowIDResolutionTask = Task { [weak self] in
        let resolvedID = await Task.detached(priority: .utility) {
            SafariWindowIDResolver.resolve(title: title)
        }.value

        await MainActor.run {
            guard let self else { return }
            guard self.snapshot.safariProcessIdentifier == pid else { return }
            guard let activeWindow = self.snapshot.activeWindow else { return }
            guard activeWindow.safariWindowId != resolvedID else { return }

            let updatedWindow = SafariWindowContext(
                processIdentifier: activeWindow.processIdentifier,
                safariWindowId: resolvedID,
                accessibilityWindowNumber: activeWindow.accessibilityWindowNumber,
                title: activeWindow.title,
                profileHint: activeWindow.profileHint,
                center: activeWindow.center,
                source: activeWindow.source,
                observedAt: activeWindow.observedAt
            )

            self.publish(
                isSafariFrontmost: true,
                frontmostBundleIdentifier: self.snapshot.frontmostBundleIdentifier,
                safariProcessIdentifier: pid,
                activeWindow: updatedWindow
            )
        }
    }
}
```

Delete these methods from `FrontmostSafariMonitor`:

- `appleScriptEnumeratedFrontWindowContext(pid:)`
- `appleScriptEnumeratedWindows()`
- `appleScriptWindowIdMatching(title:axWindowNumber:)`
- `runAppleScript(_:)`

`FrontmostSafariMonitor.refresh(...)` must only do `NSWorkspace`, AX observer setup, immediate AX reads, and publishing.

## Phase 12: Optional Persistence Write Offload

Implement this phase only after phases 1-11 are complete and tests pass.

Create a serial persistence actor if profiling shows `UserDefaults` writes still causing spikes:

```swift
import Foundation

actor UserDefaultsPersistence {
    static let shared = UserDefaultsPersistence()

    func setEncoded<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func setStringArray(_ value: [String], forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func removeObject(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
```

For each store `save()`, copy the current value on main and send the copy to the actor. Do not pass mutable store references to the actor.

Apply to:

- `CommandPanelUsageStore.save()`
- `CommandPanelSearchHistoryStore.record(_:)` persistence write
- `CommandPanelRecentStore.save()`
- `SafariBookmarkStore.saveCache(_:)`
- `ProfileStore.save()`
- `TrafficRuleStore.save()`
- `ShortcutManager.persist()`

## Required Tests

Add or update tests in `ArklikeTests`.

### `CommandPanelSuggestionComputerTests`

Test cases:

1. Empty query returns no more than `CommandPanelSuggestionLimits.visible` suggestions.
2. Non-empty normal query puts verbatim `.search` suggestion first.
3. Web suggestions and search history follow the verbatim search suggestion.
4. URL query returns URL/open behavior and does not force verbatim search first.
5. Scope picker mode returns scope suggestions.
6. Action mode returns alternate actions for the selected source suggestion.
7. Search result count is capped at `CommandPanelSuggestionLimits.visible`.

### Existing Tests

Update existing ranker tests to use the new usage-records API instead of `CommandPanelUsageStore`.

## Manual Verification

Run the app and verify:

1. With Safari frontmost, open the command palette and immediately type. Characters appear immediately.
2. Open/close the palette repeatedly. No open takes more than a frame to display.
3. Copy a very large text blob, then open the palette. The panel still opens and accepts typing immediately.
4. With many Safari tabs open, palette typing remains responsive.
5. With web suggestions enabled, rapid typing stays responsive and stale web suggestions do not overwrite current query results.
6. Paste and Go appears after the deferred clipboard read when the query remains empty.
7. Palette dismiss behavior still works on Escape and outside click.
8. Scope picker `/` behavior still works.
9. Action mode still works.
10. Existing Safari tab switching and URL opening behavior still works.

## Validation Commands

Run:

```bash
xcodebuild -project Arklike.xcodeproj -scheme Arklike -destination 'platform=macOS' test
```

Then run a debug build:

```bash
xcodebuild -project Arklike.xcodeproj -scheme Arklike -configuration Debug -destination 'platform=macOS' build
```

Both commands must succeed.

## Implementation Rules

- Keep UI mutations on `MainActor`.
- Do not capture `self` inside `Task.detached`.
- `Task.detached` may capture only immutable value snapshots and pure helper types.
- Every async suggestion result must be generation-gated before applying to UI state.
- Every async suggestion result must check that the panel is still visible before applying.
- Do not add new synchronous work to `show()` before `state.requestInputFocus()`.
- Do not read `NSPasteboard` before the palette is visible and focused.
- Do not execute `NSAppleScript` inside `FrontmostSafariMonitor.refresh(...)`.
- Do not use `Diagnostics.shared.log(...)` from performance-sensitive hot paths.
- Keep changes minimal and focused on command palette responsiveness.
