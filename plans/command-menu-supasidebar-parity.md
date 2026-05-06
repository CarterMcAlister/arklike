# Command Menu SupaSidebar Parity Plan

## Context

Arklike already has a native Safari command menu: `Cmd+T` is intercepted only while Safari is frontmost, an `NSPanel` opens with a SwiftUI search UI, providers return URL/search/Safari tab/profile/traffic/settings rows, and actions execute through Safari automation.

The goal is to make that menu feel and behave much more like SupaSidebar’s Command Panel while respecting the narrowed scope from review feedback:

- Keep Arklike’s current fixed centered panel behavior. Do not add draggable/saved-position/window-snap work now.
- Keep Arklike’s current Safari-scoped `Cmd+T` shortcut behavior. Do not add SupaSidebar’s global `Cmd Ctrl K` or optional browser-scoped `Cmd+T` setting now.
- Keep tabs Safari-only. Do not add cross-browser tab support now.
- Omit browser picker / “open in selected browser” flows. Safari is the only target for now.
- Omit searchable/toggleable settings commands for now. Keep the existing settings entry simple.
- Omit AI / Ask AI mode for now.

Within that scope, the target is high feature parity with SupaSidebar’s non-AI, Safari-relevant Command Panel behavior: scoped search, fuzzy suggestions, persisted recents/history, search history, frequent items, inline autocomplete, clipboard Paste and Go, web suggestions, direct web search, Safari live tab switching, and richer result/action semantics.

## SupaSidebar Implementation Details To Recreate

Observed from `/Applications/SupaSidebar.app`, its strings/symbols, model resources, and public docs:

- Command Panel state is manager-driven: internal names include `CommandPanelManager`, `CommandPanelWindow`, `CommandPanelSearchScope`, `SuggestionManager`, `SuggestionRanker`, `CommandPanelUsageTracker`, `SearchQueryHistoryManager`, `ScopePickerContentView`, `SuggestionRow`, and `WebSuggestionRow`.
- The panel is built around ranked suggestions, not fixed provider buckets. It tracks query text, active scope, selected suggestion index, autocomplete text, cached suggestion groups, and usage history.
- Search scopes are first-class:
  - All.
  - Recents.
  - Live Tabs.
  - Safari Bookmarks for Arklike’s Safari-only equivalent of SupaSidebar’s saved-link searching.
  - SupaSidebar Spaces, Folders, and Settings scopes are intentionally omitted from this plan.
- Scope UX details:
  - `Shift Tab` cycles scopes.
  - `/` opens a scope picker.
  - Scope keywords plus `Tab` activate a scope, e.g. `recent`, `tabs`, `bookmark`.
  - `Escape` clears scope or exits sub-modes before closing.
  - `Backspace` clears an active scope when the input is empty.
  - SupaSidebar shows “No matching scopes” when scope search has no matches.
- Suggestion sources SupaSidebar exposes that are relevant to this narrowed plan:
  - Live browser tabs, mapped to Safari live tabs only.
  - Recent links / browsing history, mapped to Safari/Arklike recents.
  - Saved links, mapped to Safari bookmarks rather than an Arklike saved-link model.
  - Website search shortcuts.
  - Web search suggestions.
  - Search query history.
  - Frequent items on empty query.
- Keyboard/action details to mirror:
  - `Up` / `Down`: move through results.
  - `Return`: open selected result.
  - `Cmd Return`: search the web directly with the current query.
  - `Shift Tab`: cycle search scope.
  - `Right Arrow`: accept inline autocomplete.
  - `Backspace`: reject autocomplete, or clear scope/shortcut when empty.
  - `Escape`: close panel, clear scope, or return from sub-mode.
  - `Opt Return` opens an actions panel in SupaSidebar; in this Safari-only plan it should show local actions only, not browser selection.
- Result behavior details:
  - Live tab results switch to already-open tabs.
  - Recent items are retained locally for 30 days and can be removed from suggestions.
  - Search history suggestions appear as the user types.
  - Empty query prioritizes frequently used items.
  - Clipboard awareness adds a Paste and Go row when the clipboard contains a URL.
  - Web suggestions are optional, cached, debounced, and controlled by a preference.
  - Website search shortcuts use short keywords: SupaSidebar copy says “Type a keyword + space to search specific websites (like Arc).”

## Current Arklike Implementation To Build On

- `Arklike/ShortcutManager.swift` and `Arklike/FrontmostSafariMonitor.swift` already provide Safari-scoped shortcut interception. Keep this behavior unchanged.
- `Arklike/CommandPaletteController.swift` currently owns too much: panel lifecycle, query state, provider aggregation, ranking, Safari tab refresh, event monitors, focus restoration, and execution.
- `Arklike/CommandPaletteView.swift` renders the fixed panel, input, rows, and footer hints.
- `Arklike/CommandPaletteModels.swift` has item kinds/actions/provider protocol/rank buckets.
- `Arklike/CommandPaletteProviders.swift` has the seed providers to convert into SupaSidebar-like suggestion providers.
- `Arklike/SafariAutomation.swift` already lists Safari windows/tabs, activates tabs, opens URLs, and gets current tab URLs.
- `Arklike/Profiles.swift` and `Arklike/TrafficControl.swift` can feed profile/rule suggestions if those remain useful, but this plan focuses on command-panel mechanics first.

## Approach

Refactor the command menu from a simple ranked list into a SupaSidebar-style suggestion pipeline while keeping the existing window and shortcut behavior intact.

Recommended architecture:

1. Introduce a richer `CommandPanelState` model for query, scope, selected index, suggestions, autocomplete, and local sub-mode.
2. Replace fixed rank buckets with a `SuggestionManager` + `SuggestionRanker` pipeline.
3. Convert existing providers into scoped suggestion providers.
4. Add persisted usage/search-history/recent-item stores.
5. Add SupaSidebar-like keyboard semantics and inline autocomplete.
6. Add Safari-only live tab cache and switching behavior.
7. Add local actions panel without browser selection.
8. Add Safari bookmark search as the Safari-only equivalent of SupaSidebar saved-link search.

## Files To Modify

- `Arklike/CommandPaletteController.swift`
- `Arklike/CommandPaletteModels.swift`
- `Arklike/CommandPaletteProviders.swift`
- `Arklike/CommandPaletteView.swift`
- `Arklike/SafariAutomation.swift`
- `Arklike/AppSettings.swift`
- `Arklike/SettingsView.swift`
- `Arklike/SearchEngineService.swift`
- `Arklike/URLParser.swift`
- `Arklike.xcodeproj/project.pbxproj`

Likely new files:

- `Arklike/CommandPanelState.swift`
- `Arklike/CommandPanelSuggestion.swift`
- `Arklike/CommandPanelSearchScope.swift`
- `Arklike/CommandPanelSuggestionManager.swift`
- `Arklike/CommandPanelSuggestionRanker.swift`
- `Arklike/CommandPanelUsageStore.swift`
- `Arklike/CommandPanelSearchHistoryStore.swift`
- `Arklike/CommandPanelRecentStore.swift`
- `Arklike/CommandPanelWebSuggestionService.swift`
- `Arklike/CommandPanelScopePickerView.swift`
- `Arklike/CommandPanelActionsView.swift`
- `Arklike/SafariLiveTabStore.swift`
- `Arklike/SafariBookmarkProvider.swift`

## Reuse

- Reuse `URLParser` for URL/search classification.
- Reuse `SearchEngineService` for direct web search and search shortcut URLs.
- Reuse `SafariAutomation.listWindowsAndTabs()` and `activateTab(windowId:tabIndex:)` for Safari Live Tabs.
- Reuse `FrontmostSafariMonitor.shared.activeWindowForSafariAction()` to target the active Safari window.
- Reuse `ProfileStore` only for profile suggestions if retained after the core parity work.
- Reuse `TrafficRuleStore` only for optional URL/rule preview suggestions; do not let it block command panel parity.

## Steps

### 1. Split Controller State From Window Lifecycle

- [x] Keep `CommandPaletteController.show()`, `dismiss()`, panel creation, positioning, key monitors, and focus restoration behavior unchanged.
- [x] Move query/scope/selection/autocomplete/suggestions into `CommandPanelState`.
- [x] Add `CommandPanelMode` with only modes needed now:
  - `search`.
  - `scopePicker`.
  - `actions`.
- [x] Do not add `browserSelection` or `aiChat` modes in this iteration.
- [x] Add a `CommandPanelSuggestionManager` that receives state + context and returns ranked suggestions.

Acceptance criteria:

- `Cmd+T` still opens the same centered Safari-scoped panel.
- Existing URL/search/Safari tab actions continue to work after the state refactor.
- The suggestion manager can be unit-tested without creating an `NSPanel`.

### 2. Define SupaSidebar-Like Suggestions

- [x] Replace or wrap `CommandPaletteItem` with `CommandPanelSuggestion`:
  - `id` stable across launches where possible.
  - `title`.
  - `subtitle`.
  - `kind`.
  - `scope`.
  - `iconSystemName`.
  - `representedURL`.
  - `primaryAction`.
  - `alternateActions`.
  - `basePriority`.
  - `fuzzyScore`.
  - `usageScore`.
  - `lastUsedAt`.
  - `matchRanges` for highlighted row text later.
- [x] Keep existing action cases for Safari URL/search/tab/profile/settings, but add local actions:
  - copy URL.
  - remove recent/suggestion.
  - open Safari bookmark.
- [x] Ensure no alternate action references other browsers or non-Safari bookmark data models.

Acceptance criteria:

- Every row is a suggestion with enough metadata for SupaSidebar-like ranking and display.
- Existing provider rows map cleanly into the new suggestion model.

### 3. Add Search Scopes Except Settings, Spaces, And Folders

- [x] Add `CommandPanelSearchScope`:
  - `all`.
  - `recents`.
  - `liveTabs`.
  - `bookmarks`.
- [x] Intentionally do not add SupaSidebar’s Settings, Spaces, or Folders scopes yet.
- [x] Map SupaSidebar’s “Saved” behavior to Safari bookmarks instead of creating Arklike saved links.
- [x] Add scope keywords:
  - Recents: `recent`, `recents`, `history`.
  - Live Tabs: `tab`, `tabs`, `live tabs`.
  - Bookmarks: `bookmark`, `bookmarks`, `favorite`, `favorites`, `saved`.
- [x] Add `/` scope picker with fuzzy filtering and “No matching scopes”.
- [x] Add `Shift Tab` cycling in SupaSidebar order.
- [x] Add `Tab` activation when typed text matches a scope keyword.
- [x] Add `Escape` to clear active scope before dismissing the panel.
- [x] Add `Backspace` to clear active scope when query is empty.

Acceptance criteria:

- Scope pill/label is visible in the panel.
- Providers are filtered by active scope.
- `/`, `Shift Tab`, `Tab`, `Escape`, and `Backspace` scope behavior matches SupaSidebar’s documented behavior.

### 4. Implement Fuzzy Ranking, Frequent Items, And Search History

- [x] Implement `CommandPanelSuggestionRanker` using these inputs:
  - active scope match.
  - provider base priority.
  - fuzzy score over title/subtitle/URL/keywords.
  - exact prefix and acronym boosts.
  - usage count boost.
  - recency boost.
  - selected-query history boost.
- [x] Add fuzzy behavior inspired by SupaSidebar examples:
  - Misspelling tolerance, e.g. `fecebook` can find `Facebook`.
  - Token abbreviation, e.g. `sup doc` can find `SupaSidebar Documentation`-style titles.
  - Short keyword matching for search shortcuts.
- [x] Add `CommandPanelUsageStore` persisted in `UserDefaults` or a small JSON file:
  - suggestion stable id.
  - kind.
  - count.
  - last used date.
  - last query.
- [x] Add `CommandPanelSearchHistoryStore`:
  - stores recent non-empty queries.
  - deduplicates repeated queries.
  - provides matching past-query suggestions.
- [x] Show frequent items on empty query before generic placeholder rows.

Acceptance criteria:

- Empty query shows useful frequent/recent suggestions.
- Query history suggestions appear while typing.
- Selecting a suggestion updates usage history.
- Fuzzy results are meaningfully better than rank/title sorting.

### 5. Persist Recents And Add 30-Day Cleanup

- [x] Replace controller-local `recentURLs` with `CommandPanelRecentStore`.
- [x] Store:
  - URL.
  - title if known.
  - source `safari`.
  - last accessed date.
  - open count.
  - optional Safari window/profile hint.
- [x] Add automatic cleanup for entries older than 30 days.
- [x] Add remove-from-suggestions alternate action for recent rows.
- [x] Update URL/search/open-tab execution to record recents and usage consistently.

Acceptance criteria:

- Recents survive app relaunch.
- Old recents are cleaned up.
- Recent rows can be removed locally.
- Recents scope is useful with empty and non-empty queries.

### 6. Add Clipboard Paste And Go

- [x] On panel open, inspect `NSPasteboard.general` for a valid URL.
- [x] If valid, add a top-ranked `Paste and Go` suggestion.
- [x] Support explicit URLs and bare domains through `URLParser`.
- [x] Avoid showing duplicate Paste and Go if the clipboard URL already appears as the first exact URL result.

Acceptance criteria:

- Clipboard URL appears at the top when the panel opens.
- Return opens the clipboard URL in Safari.
- Non-URL clipboard content is ignored.

### 7. Add Web Suggestions And Direct Web Search

- [x] Add `webSearchSuggestionsEnabled` to `AppSettings` and settings UI.
- [x] Add `defaultSearchEngine` or reuse `SearchEngineService.searchURLTemplate`.
- [x] Implement debounced `CommandPanelWebSuggestionService`:
  - request suggestions only for non-empty search-like queries.
  - cache by query.
  - cancel stale requests when query changes.
  - fail silently with diagnostics, not user-visible crashes.
- [x] Start with Google Suggest because SupaSidebar strings explicitly reference Google suggestions.
- [x] Render web suggestion rows below higher-confidence local results.
- [x] Implement `Cmd Return` to search the web directly with the raw query or accepted autocomplete text.

Acceptance criteria:

- Web suggestions are optional and can be disabled.
- Suggestions update without blocking local results.
- `Cmd Return` performs direct Safari web search regardless of selected row.

### 8. Implement Inline Autocomplete

- [x] Track `autocompleteText` in state.
- [x] Source autocomplete from:
  - best matching URL/domain.
  - search history.
  - search shortcut keywords.
  - web suggestions when enabled.
- [x] Render inline completion in the text field or as a visually attached ghost text.
- [x] `Right Arrow` accepts autocomplete.
- [x] `Backspace` rejects autocomplete before deleting typed content when appropriate.
- [x] Opening a suggestion should use accepted autocomplete only when accepted; otherwise use raw query.

Acceptance criteria:

- Autocomplete is visible but non-destructive.
- Right Arrow and Backspace match SupaSidebar’s behavior.
- Rejected autocomplete does not accidentally run as the query.

### 9. Improve Safari Live Tabs, Safari-Only

- [x] Add `SafariLiveTabStore` to cache current Safari tabs while the panel is visible.
- [x] Refresh tabs:
  - immediately on panel open.
  - after a short debounce.
  - periodically while visible if inexpensive.
  - after tab-switch/open actions.
- [x] Keep the scope Safari-only; do not introduce browser adapters for other browsers in this plan.
- [x] Add permission/error suggestions when Safari automation fails.
- [x] Add duplicate URL behavior:
  - setting: `switchToExistingSafariTabInsteadOfOpeningDuplicate`.
  - when enabled, opening an URL first checks cached Safari tabs for same normalized URL and switches instead of opening a new tab.
- [x] Add Live Tabs scope row behavior:
  - Return switches to the tab.
  - row subtitle shows URL plus active/window context.

Acceptance criteria:

- Live Tabs scope reliably lists Safari tabs.
- Searching by Safari tab title or URL works.
- Return switches to selected Safari tab.
- Duplicate URL setting switches to existing Safari tab when possible.

### 10. Add Local Actions Panel Without Browser Picker

- [x] Implement `actions` mode opened by `Opt Return`.
- [x] Include only Safari/local actions:
  - Open in Safari / open selected.
  - Copy URL.
  - Remove from recents/suggestions when applicable.
  - Open Safari bookmark rows.
  - Reveal file in Finder only for file URLs if introduced.
  - Do not create, edit, or delete Safari bookmarks from the actions panel.
- [x] `Escape` returns from actions mode to search without clearing query.
- [x] `Return` runs the selected local action.
- [x] Do not include “Open in Chrome/Firefox/Arc/etc.” rows.

Acceptance criteria:

- `Opt Return` opens an actions list instead of executing primary action.
- Actions are context-sensitive.
- No browser picker or multi-browser behavior is introduced.

### 11. Add Safari Bookmarks As The Saved-Item Equivalent

SupaSidebar’s Command Panel searches saved links. For Arklike’s Safari-only scope, implement this through Safari bookmarks instead of adding Arklike saved links, command folders, or command spaces.

- [x] Add `SafariBookmarkProvider` for the `bookmarks` scope.
- [x] Discover Safari bookmarks using the safest available local approach:
  - Prefer reading Safari bookmark data only if macOS permissions and file access allow it.
  - Fall back to a clear disabled/permission row if bookmarks cannot be read.
  - Do not require bookmark support for URL/search/live-tab functionality.
- [x] Normalize bookmark suggestions:
  - title.
  - URL.
  - optional folder/path text from Safari bookmark hierarchy when available.
  - stable id derived from URL/title/path.
  - scope = `bookmarks`.
  - primary action = open URL in Safari.
- [x] Include bookmarks in All scope and Bookmarks scope.
- [x] Rank bookmarks using the same fuzzy/usage system as recents and live tabs.
- [x] Add local bookmark actions only where safe:
  - open in Safari.
  - copy URL.
  - remove from command-panel suggestions only if this is a local suppression list, not destructive Safari bookmark deletion.

Acceptance criteria:

- Bookmarks scope searches Safari bookmarks, not Arklike saved links.
- No command folder or command space model is added.
- Safari bookmark rows open in Safari with Return.
- If Safari bookmarks are inaccessible, the panel shows an explanatory disabled row and the rest of the panel still works.

## Verification

Automated tests:

- Scope keyword parsing and activation.
- Scope cycling order.
- Scope picker filtering and no-match state.
- Fuzzy ranking with typo and abbreviation cases.
- Usage boost ordering.
- Query history persistence/deduplication.
- Recents persistence and 30-day cleanup.
- Clipboard URL parsing.
- Web suggestion caching/cancellation with mocked service.
- Duplicate Safari tab matching by normalized URL.
- Safari bookmark parsing/provider behavior with mocked bookmark data.

Manual tests:

- With Safari frontmost, `Cmd+T` opens the existing fixed centered panel.
- Outside Safari, `Cmd+T` is not hijacked by Arklike.
- `Up`/`Down` navigate; `Return` opens; `Escape` closes/clears scope as appropriate.
- `/` opens scope picker.
- `Shift Tab` cycles scopes.
- Typing a scope keyword then `Tab` activates that scope.
- `Right Arrow` accepts autocomplete; `Backspace` rejects autocomplete.
- Clipboard URL creates Paste and Go.
- `Cmd Return` searches the web directly.
- Live Tabs scope lists Safari tabs and Return switches to one.
- Bookmarks scope lists Safari bookmarks when accessible and opens them in Safari.
- `Opt Return` opens local actions only, with no browser picker.
- Missing Accessibility or Apple Events permissions produce useful disabled/error suggestions.

## Non-Goals For This Plan

- No draggable panel, saved position, or magnetic snap changes.
- No global `Cmd Ctrl K` shortcut.
- No optional SupaSidebar-style `Cmd+T` hijack setting beyond Arklike’s current Safari-scoped behavior.
- No cross-browser live tabs.
- No browser picker or “open in another browser”.
- No searchable/toggleable settings commands.
- No AI chat / Ask AI mode.
