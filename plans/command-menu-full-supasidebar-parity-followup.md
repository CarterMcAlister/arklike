# Command Menu Full SupaSidebar Parity Follow-Up Plan

## Goal

Close the remaining gaps in Arklike’s command menu implementation so the Safari-focused command menu reaches practical 1:1 behavior with SupaSidebar’s non-AI, command-panel experience.

This plan focuses on the limited or incomplete pieces from the last implementation:

- Safari bookmarks are best-effort direct plist reads only and need a robust automatic refresh/permission flow.
- Frequent items are only an implicit usage boost, not a dedicated empty-query section/provider.
- Fuzzy matching is a lightweight local scorer, not robust SupaSidebar-grade matching.
- Match highlighting is modeled but not rendered.
- Profile command rows are still shallow.
- Traffic Control command rows are shallow.
- Settings command scope was intentionally omitted but is needed for 1:1 SupaSidebar command-panel behavior.

Still out of scope unless explicitly requested later:

- Cross-browser support.
- Browser picker / open in another browser.
- AI / Ask AI.
- Draggable panel positioning.
- SupaSidebar Spaces/Folders as standalone workspace concepts.

## Current Baseline

Implemented already:

- `CommandPanelState` for query, mode, scope, suggestions, selection, and autocomplete.
- `CommandPanelSuggestionManager` and scoped providers.
- `CommandPanelSuggestionRanker` with basic fuzzy and usage scoring.
- Persistent recents and search history.
- Clipboard Paste and Go.
- Optional Google Suggest web suggestions.
- Inline autocomplete.
- Safari-only Live Tabs and duplicate-tab switching.
- Local `Opt+Return` actions mode.
- Safari bookmark provider with best-effort `~/Library/Safari/Bookmarks.plist` reading.
- Web suggestions and duplicate-tab settings toggles.

## Implementation Phases

### 1. Replace Best-Effort Safari Bookmark Reads With Robust Automatic Bookmark Indexing

SupaSidebar’s saved-link search is automatic and stays current. Arklike should automatically read Safari bookmarks from Safari’s local bookmark store, explain/request the needed macOS permissions, cache the parsed index, and refresh when Safari bookmarks change. No manual export/import flow should be required.

- [x] Add `SafariBookmarkIndexService`.
- [x] Read Safari bookmarks automatically from `~/Library/Safari/Bookmarks.plist`.
- [x] Treat Full Disk Access / protected file access as an acceptable requirement for 1:1 parity.
- [x] Add permission UX:
  - detect when `Bookmarks.plist` exists but cannot be read.
  - show a clear command-panel disabled row explaining that Full Disk Access is needed for Safari bookmarks.
  - add Settings copy explaining why bookmark access is needed.
  - add a button to open Privacy & Security settings where the user can grant Full Disk Access.
- [x] Parse Safari bookmark plist recursively:
  - bookmark title.
  - URL.
  - Safari folder/path hierarchy.
  - stable id derived from URL + path + title.
- [x] Persist a local cached bookmark index:
  - allows command menu to keep using last-known bookmarks if a later refresh temporarily fails.
  - stores source file modification date and parsedAt.
- [x] Refresh automatically:
  - on app launch.
  - when command panel opens.
  - when `Bookmarks.plist` modification date changes.
  - optionally via a lightweight file watcher for Safari bookmark changes.
- [x] De-duplicate bookmarks by normalized URL + folder path.
- [x] Add Settings action: Refresh Safari Bookmarks.
- [x] Update command-panel bookmark rows to show:
  - title.
  - URL/domain.
  - folder path when available.
  - stale-cache warning only if current refresh failed but cached bookmarks exist.

Acceptance criteria:

- User does not need to export/import bookmarks manually.
- With required permissions granted, Safari bookmark changes appear after refresh/file-change detection.
- Bookmarks survive app restart through the local cache.
- If permission is missing, the panel explains exactly what to grant.
- If refresh fails but cache exists, bookmarks remain searchable with a non-blocking warning.

### 2. Add A Dedicated Frequent Items Provider

The current usage score boosts existing rows but does not create SupaSidebar-like frequent items on empty query.

- [x] Add `FrequentItemsCommandProvider`.
- [x] Source top items from `CommandPanelUsageStore`.
- [x] Rehydrate frequent entries from available providers by stable id.
- [x] Show frequent items only when:
  - query is empty.
  - mode is search.
  - scope is All or no scope.
- [x] Rank frequent items above generic search shortcut placeholders but below Paste and Go.
- [x] Add row subtitle details:
  - Frequently used.
  - last used date if useful.
- [x] Avoid duplicate rows by stable id when the same suggestion appears from its normal provider.

Acceptance criteria:

- Empty command menu shows frequently used bookmarks/tabs/recents/searches.
- Paste and Go still remains first when clipboard URL exists.
- Frequent rows update after selecting/opening suggestions.

### 3. Upgrade Fuzzy Search To SupaSidebar-Grade Matching

The lightweight scorer should be replaced or significantly improved to better match SupaSidebar examples.

- [x] Add a deterministic fuzzy matcher with structured scoring:
  - exact match.
  - prefix match.
  - word-boundary match.
  - acronym match.
  - ordered subsequence match.
  - typo-tolerant Levenshtein / Damerau-Levenshtein match.
  - token-set match for multi-word queries.
- [x] Return match ranges for title/subtitle/URL.
- [x] Penalize long-distance scattered matches.
- [x] Boost domain/title matches over subtitle-only matches.
- [x] Add provider keywords to suggestions so aliases like `gh`, `yt`, `bookmark`, `tab`, and profile names rank naturally.
- [x] Add tests for examples:
  - `fecebook` finds `Facebook`.
  - `sup doc` finds documentation-like titles.
  - `gh` finds GitHub shortcut/bookmark.
  - URL host fragments rank above incidental subtitle matches.

Acceptance criteria:

- Search feels tolerant of typos and abbreviations.
- Ranking is stable and explainable.
- Match ranges are available for rendering.

### 4. Render Match Highlighting In Rows

The model has `matchRanges`, but the view does not use them.

- [x] Extend `CommandPanelSuggestion` to store separate title/subtitle match ranges, not only one generic range list.
- [x] Add a highlighted text renderer for SwiftUI rows.
- [x] Highlight matching characters/tokens in:
  - title.
  - subtitle where useful.
  - URL/domain segments.
- [x] Keep selected-row contrast readable.
- [x] Avoid expensive attributed-string work on every render by computing highlights in ranking/provider output.

Acceptance criteria:

- Matching text is visibly highlighted in results.
- Highlighting works in selected and unselected rows.
- No measurable lag on typical result counts.

### 5. Complete Safari Profile Suggestions And Actions

Profile rows currently exist but do not perform full profile switching from the command menu.

- [x] Replace placeholder profile rows with actual `ProfileStore.shared.profiles` data.
- [x] Show profile name, assigned shortcut number, and Safari menu title.
- [x] Support query aliases:
  - `profile`.
  - profile name.
  - `p1`, `profile 1`, etc.
- [x] Execute profile rows with `SafariProfileManager.shared.switchToProfile(number:)`.
- [x] Add local actions:
  - Switch to profile.
  - Copy profile name.
  - Open Profiles settings.
- [x] Show disabled/error row when no profiles are configured.
- [x] Optionally auto-refresh profiles if store is empty and permissions allow.

Acceptance criteria:

- Selecting a profile row actually switches/opens the Safari profile.
- Profile rows use real profile names.
- Missing profile configuration is explained in-panel.

### 6. Complete Traffic Control Suggestions And Rule Preview

Traffic Control currently only exposes a settings placeholder.

- [x] Add `TrafficRuleCommandProvider` output for actual `TrafficRuleStore.shared.rules`.
- [x] Show enabled/disabled state, matcher type, pattern, target profile number, and open behavior.
- [x] Search by:
  - rule name.
  - pattern.
  - target profile.
  - words like `traffic`, `route`, `rule`.
- [x] If query parses as URL, show the first matching Traffic Control rule as a high-confidence preview row.
- [x] Row actions:
  - Open Traffic Control settings.
  - Copy rule pattern.
  - Test typed URL against this rule.
- [x] Add disabled row if no rules exist.

Acceptance criteria:

- Traffic Control scope-like results are real rules, not placeholders.
- Typed URLs can preview which rule would match.
- Rule rows are useful without opening Settings first.

### 7. Add SupaSidebar-Like Settings Scope For Command Menu Commands

This was omitted earlier but is required for closer 1:1 behavior.

- [x] Add `settings` to `CommandPanelSearchScope`.
- [x] Add scope keywords:
  - `settings`.
  - `tools`.
  - `commands`.
  - `actions`.
- [x] Add `SettingsCommandProvider` rows for:
  - Open Settings.
  - Open Shortcuts settings.
  - Open Profiles settings.
  - Open Traffic Control settings.
  - Toggle web suggestions.
  - Toggle duplicate Safari tab switching.
  - Clear recents.
  - Clear search history.
  - Refresh Safari Bookmarks.
- [x] Add action types for setting toggles and maintenance commands.
- [x] Make Settings scope browseable with an empty query.
- [x] Add row subtitles in SupaSidebar style:
  - Return to toggle this setting.
  - Return to run this command.

Acceptance criteria:

- Settings scope exists and is keyboard reachable via `Shift Tab`, `/`, and keyword+Tab.
- Boolean settings toggle from the command panel.
- Maintenance commands run from the command panel.

### 8. Improve Actions Mode To Match SupaSidebar’s Local Action Semantics

Actions mode exists but should become richer and more consistent.

- [x] Standardize action ordering:
  - Primary action.
  - Copy URL.
  - Remove from recents/search suggestions where applicable.
  - Relevant settings/details action.
- [x] Add action availability by kind:
  - URL/search result.
  - Safari tab.
  - Recent.
  - Bookmark.
  - Profile.
  - Traffic rule.
  - Settings command.
- [x] Add visual hint row/title showing the source item.
- [x] Ensure Escape returns to search without clearing query/scope.
- [x] Ensure action execution updates usage only where appropriate.

Acceptance criteria:

- `Opt+Return` always shows meaningful local actions for selected rows.
- Actions mode does not pollute search history.
- No browser picker or non-Safari actions appear.

### 9. Add Focused Tests For Command Panel Logic

The current project test command typechecks but does not exercise command-panel logic.

- [x] Add lightweight unit-testable pure helpers where possible:
  - fuzzy matcher.
  - scope matching.
  - recent cleanup.
  - bookmark HTML parser.
    - traffic-rule preview provider.
- [x] Add tests under `ArklikeTests`.
- [x] If XCTest project setup is too heavy, add script-level Swift test harnesses consistent with current repo tooling.
- [x] Keep UI behavior covered by manual checklist.

Acceptance criteria:

- Core rank/scope/bookmark/parser behavior has automated coverage.
- `mise run test` remains fast and green.

## Verification Plan

Run after implementation:

```sh
plutil -lint Arklike.xcodeproj/project.pbxproj
mise run test
mise run build
```

Manual verification:

- Open command menu with Safari frontmost via existing `Cmd+T`.
- Grant Full Disk Access, refresh Safari bookmarks automatically, and search them immediately.
- Empty query shows Paste and Go first if available, then frequent items.
- Fuzzy search typo/abbreviation examples work.
- Match highlights render in rows.
- Profile command row switches actual Safari profile.
- Traffic rule rows show real rules and URL match preview.
- Settings scope toggles command-menu settings and runs maintenance commands.
- `Opt+Return` action mode works for URL, tab, recent, bookmark, profile, rule, and settings rows.

## Done Criteria

This follow-up is complete when:

- Bookmarks are reliable via automatic Safari bookmark indexing, permission guidance, refresh detection, and local cache fallback.
- Empty-query frequent items are a first-class result source.
- Fuzzy matching and row highlighting feel comparable to SupaSidebar.
- Profile and Traffic Control rows perform real useful actions.
- Settings scope exists with toggle/run commands.
- Tests/build pass.
