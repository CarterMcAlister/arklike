# Fix Settings And Command Palette Freezes

## Goal

Opening Settings, opening the command palette, typing in the command palette, and dismissing either UI must never wait on Safari automation, Accessibility calls, AppleScript, pasteboard reads, file I/O, permission probes, or heavy suggestion work.

The UI may show stale cached data, loading rows, or unavailable states, but it must remain interactive.

## Summary Of Root Causes

The app already moved part of command-palette suggestion computation off the main actor, but several independent freeze vectors remain. The biggest problem is that UI entry points and keyboard/event-tap callbacks still synchronously perform work that can block the main actor.

### 1. Settings Open Triggers Blocking Main-Actor Refreshes

`SettingsWindowController.show()` constructs and shows `SettingsView` synchronously (`Arklike/SettingsWindowController.swift:16`). `SettingsView.onAppear` immediately runs:

- `permissions.refresh()`
- `launchAtLogin.refresh()`
- `safariMonitor.start()`
- `safariMonitor.refresh(reason: "settings appear")`

at `Arklike/SettingsView.swift:75`.

`PermissionsManager.refresh()` calls `makeSnapshot()` on the main actor (`Arklike/PermissionsManager.swift:49`). That snapshot probes:

- default browser via `NSWorkspace.shared.urlForApplication(toOpen:)` (`Arklike/PermissionsManager.swift:110`)
- Accessibility trust via `AXIsProcessTrusted()` (`Arklike/PermissionsManager.swift:103`)
- Apple Events permission via `AEDeterminePermissionToAutomateTarget(...)` (`Arklike/PermissionsManager.swift:135`)

`FrontmostSafariMonitor.refresh()` also runs on the main actor (`Arklike/FrontmostSafariMonitor.swift:118`) and performs several synchronous AX reads:

- focused Safari window (`Arklike/FrontmostSafariMonitor.swift:280`)
- title / window number (`Arklike/FrontmostSafariMonitor.swift:289`)
- position and size (`Arklike/FrontmostSafariMonitor.swift:363`)

Any of those APIs can stall if Safari, System Events, TCC, or Accessibility is slow.

### 2. Settings Activation Duplicates The Same Blocking Work

Opening Settings activates the app (`Arklike/SettingsWindowController.swift:33`). `applicationDidBecomeActive` then calls both `PermissionsManager.shared.refresh()` and `FrontmostSafariMonitor.shared.refresh(...)` synchronously (`Arklike/AppDelegate.swift:34`) before/around `SettingsView.onAppear`, doubling the blocking work during the exact open path.

### 3. Profiles Settings Runs AppleScript On The Main Actor

`ProfilesSettingsView` refreshes Safari profiles on appear when the store is empty (`Arklike/ProfilesSettingsView.swift:47`) and its refresh button calls the same sync path (`Arklike/ProfilesSettingsView.swift:12`).

That calls `ProfileStore.refreshFromSafari()` (`Arklike/Profiles.swift:46`), which calls `SafariProfileManager.discoverProfileNames()` (`Arklike/SafariProfileManager.swift:43`). The profile discovery script:

- activates Safari (`Arklike/SafariProfileManager.swift:45`)
- scrapes the Safari File menu through System Events (`Arklike/SafariProfileManager.swift:46`)
- executes via `NSAppleScript.executeAndReturnError` synchronously (`Arklike/SafariProfileManager.swift:158`)

This can freeze Settings and can also steal focus from the settings window.

### 4. Background Profile Refresh Is Not Actually Off-Main

`ProfileStore.startPeriodicRefresh()` is started at launch (`Arklike/AppDelegate.swift:19`). Its delayed refresh path returns to `MainActor` and calls `refreshFromSafari()` (`Arklike/Profiles.swift:100`, `Arklike/Profiles.swift:115`). This means periodic profile discovery can block the main actor while the command palette or Settings is opening.

### 5. Shortcut And Event Tap Callbacks Do Too Much Synchronously

The global event tap and Carbon hotkey callbacks use `MainActor.assumeIsolated` (`Arklike/ShortcutManager.swift:244`, `Arklike/ShortcutManager.swift:250`). Inside that callback path:

- `isActionEnabled` can synchronously call `FrontmostSafariMonitor.refresh(...)` (`Arklike/ShortcutManager.swift:129`)
- matching actions call the app handler synchronously (`Arklike/ShortcutManager.swift:117`)
- command palette opening then runs `CommandPaletteController.show()` immediately (`Arklike/AppDelegate.swift:92`)

An event-tap callback must return quickly. Doing UI creation, refresh checks, or automation from this callback risks visible hangs and tap timeouts.

### 6. Command Palette Show Still Performs Main-Actor Work In The Hot Path

`CommandPaletteController.show()` is main-actor isolated and does many state mutations, panel creation, positioning, monitor installation, and event tap installation before returning (`Arklike/CommandPaletteController.swift:60`). The most concerning synchronous operation is installing a second session event tap on every palette open (`Arklike/CommandPaletteController.swift:552`).

The palette should show first, then any optional event monitoring should be installed asynchronously or preinstalled.

### 7. Command Palette Snapshotting Copies Potentially Large Stores On The Main Actor

Suggestion computation itself is detached (`Arklike/CommandPaletteController.swift:278`), but the input snapshot is built first on the main actor (`Arklike/CommandPaletteController.swift:275`). `makeSuggestionInput()` copies full arrays/dictionaries:

- recents
- live tabs
- bookmarks
- profiles
- traffic rules
- usage records
- search history
- search shortcuts

at `Arklike/CommandPaletteController.swift:316`.

For large Safari bookmark indexes or usage/search histories, the copy can block typing even though the later ranking happens off-main.

### 8. Deferred Clipboard Read Can Still Freeze While The Palette Is Visible

Clipboard reading was deferred until after the panel opens, but it still runs on the main actor after 350 ms (`Arklike/CommandPaletteController.swift:296`). `NSPasteboard.general.string(forType:)` is performed synchronously at `Arklike/CommandPaletteController.swift:305`.

If the pasteboard owner is slow, input can freeze after the palette is already visible.

### 9. Command Palette Actions Run Blocking Safari Automation On The Main Actor

Selecting rows performs synchronous automation before dismissing/updating UI:

- activate tab/window (`Arklike/CommandPaletteController.swift:140`)
- switch profile (`Arklike/CommandPaletteController.swift:149`)
- open URL/new tab (`Arklike/CommandPaletteController.swift:226`)
- restore Safari focus on dismiss (`Arklike/CommandPaletteController.swift:444`)

Those call `SafariAutomation` or `SafariProfileManager`, both main-actor-bound and AppleScript/AX-heavy. Even if action execution may reasonably take time, it must not freeze the palette UI.

### 10. Safari Profile Switching Performs Deep AX Tree Traversal On The Main Actor

`SafariProfileManager.switchToExistingWindow` recursively reads Accessibility attributes for every Safari window up to depth 5, with up to 80 children per node (`Arklike/SafariProfileManager.swift:81`, `Arklike/SafariProfileManager.swift:102`). This is potentially huge and synchronous.

### 11. Bookmark Refresh Mostly Uses Background Loading, But Metadata Checks Still Hit Disk On Main

Bookmark parsing is detached (`Arklike/CommandPanelStores.swift:311`), but `refreshIfNeeded()` calls `modificationDate()` on the main actor (`Arklike/CommandPanelStores.swift:305`), which performs `FileManager.attributesOfItem` synchronously (`Arklike/CommandPanelStores.swift:359`). This can block if the protected Safari path or disk is slow.

### 12. Web Suggestion Service Has Main-Actor Control Flow Per Keystroke

`CommandPanelWebSuggestionService` is `@MainActor` (`Arklike/CommandPanelWebSuggestionService.swift:3`). Every typed query runs cancellation, URL parsing, cache lookup, and sometimes immediate completion on the main actor (`Arklike/CommandPanelWebSuggestionService.swift:12`). This is smaller than the Safari/AX freezes, but it is still unnecessary hot-path main work.

Its failure path also logs through `Diagnostics.shared.log` from async fetch code (`Arklike/CommandPanelWebSuggestionService.swift:61`), which can introduce main-actor hops during network failure bursts.

## Fix Plan

### Phase 0: Add Freeze Instrumentation First

1. Add a lightweight main-thread stall detector for debug/dev builds:
   - sample the main run loop every 50-100 ms;
   - log a warning if the main actor does not respond within 150-250 ms;
   - include the current named operation where available.
2. Expand `PerformanceTimer` coverage around every UI entry point and sync boundary:
   - settings show/open;
   - settings `onAppear` refresh work;
   - permission snapshot;
   - Safari monitor refresh and individual AX reads;
   - profile discovery;
   - command-palette show;
   - command-palette snapshot creation;
   - pasteboard read;
   - action execution.
3. Add a dev-only diagnostics row showing the last slow operation.

Acceptance criteria:

- Reproducing the freeze names the responsible operation.
- Logs distinguish UI work from background work.

### Phase 1: Make Settings Open Purely UI-First

1. Remove blocking refreshes from `SettingsView.onAppear`.
2. Show Settings immediately with cached snapshots.
3. Start refreshes after the window is visible using async tasks.
4. Split `PermissionsManager.refresh()` into:
   - cached snapshot read for UI;
   - async permission probe;
   - main-actor publish of the result.
5. Remove duplicate refreshes from `applicationDidBecomeActive`; schedule them debounced and async instead.
6. Do not call `FrontmostSafariMonitor.refresh()` directly from Settings open. Use the latest snapshot and let the monitor update independently.

Acceptance criteria:

- Clicking Settings opens a usable window before any permission/Safari probe completes.
- If Safari or TCC is hung, Settings still scrolls/tabs/responds.

### Phase 2: Move Profile Discovery And Profile Switching Off The UI Hot Path

1. Add a non-main `SafariProfileDiscoveryWorker` that runs the AppleScript menu scrape off the main actor.
2. Change `ProfileStore.refreshFromSafari()` into an async/loading-state API:
   - immediately publish `isRefreshing = true`;
   - run discovery off-main;
   - publish profiles/message on main.
3. Stop auto-refreshing profiles synchronously when Settings appears.
4. Change `ProfilesSettingsView` to show cached profiles plus a loading state; the refresh button starts async work and remains responsive.
5. Remove `tell application "Safari" to activate` from discovery if possible. Discovery should not steal focus just to populate Settings.
6. Replace recursive AX tree scanning for profile-window matching with cached/lightweight data where possible; if deep scanning remains necessary, run it off the main actor and add a timeout/budget.

Acceptance criteria:

- Opening Profiles settings never activates Safari or blocks the Settings window.
- Profile refresh can fail/timeout without freezing UI.

### Phase 3: Keep Event Tap Callbacks Constant-Time

1. Change Carbon/event-tap handlers to do only cheap matching and enqueue work.
2. Never call `FrontmostSafariMonitor.refresh()` from `isActionEnabled` inside the event-tap callback.
3. Never call `CommandPaletteController.show()` directly from the event-tap callback. Dispatch it asynchronously to the main actor after returning from the callback.
4. For stale frontmost-state checks, use the direct `NSWorkspace.frontmostApplication` check only; schedule monitor reconciliation later.
5. Add timeout/tap-disabled diagnostics if the event tap is disabled by the system.

Acceptance criteria:

- Key interception returns immediately even if Safari/Accessibility is slow.
- Command palette opening cannot disable the event tap.

### Phase 4: Make Command Palette Open Render Before Optional Work

1. Split `show()` into two stages:
   - stage A: reset minimal UI state, create/show panel, request focus;
   - stage B: install optional monitors, snapshot data, refresh suggestions, read clipboard.
2. Remove command-palette-specific session event tap from the open hot path. Prefer the existing local/global monitors; if a CG event tap is still required, preinstall it at launch or install after the panel is visible.
3. Batch `CommandPanelState.resetForOpen()` mutations to avoid repeated SwiftUI invalidations.
4. Do not run any store snapshot/copy before the panel is visible and focused.

Acceptance criteria:

- `Cmd+T` displays and focuses the input immediately.
- Any slow monitor setup or data loading happens after the user can type.

### Phase 5: Move Snapshot Construction Out Of The Main-Typing Path

1. Maintain immutable background-ready snapshots inside each store:
   - bookmarks snapshot;
   - tabs snapshot;
   - recents snapshot;
   - usage/search-history snapshots;
   - profiles/rules/settings snapshots.
2. Update these snapshots when stores change, not on every keystroke.
3. On each query, pass references to the latest immutable snapshot plus the small query/mode state.
4. Cap or pre-index large sources:
   - precompute lowercase bookmark/tab/recent searchable fields;
   - precompute stable IDs;
   - keep top-N/frequent indexes ready.
5. Make `makeSuggestionInput()` cheap and measurable; target under 2 ms.

Acceptance criteria:

- Typing does not copy full bookmark/history arrays on the main actor.
- Large bookmark libraries do not cause keypress hitches.

### Phase 6: Make Clipboard And Web Suggestions Non-Blocking

1. Move pasteboard URL detection to a cancellable background operation if safe; otherwise skip/defer it when the user starts typing.
2. Add a short timeout/budget for pasteboard reads; failure means no Paste and Go row.
3. Make `CommandPanelWebSuggestionService` non-main except for publishing results.
4. Keep URL parsing/cache lookup out of the main typing path where possible.
5. Rate-limit diagnostics logging from web suggestion failures.

Acceptance criteria:

- Slow pasteboard owners cannot freeze command-palette input.
- Network failures cannot cause repeated main-actor logging stalls.

### Phase 7: Make Actions Async And UI-First

1. For command-palette row execution:
   - record selection;
   - dismiss or show an executing state immediately;
   - run Safari automation/profile switching asynchronously;
   - show HUD/error result when done.
2. Move AppleScript execution helpers out of `@MainActor` types where possible.
3. Add cancellation/timeout boundaries around AppleScript and AX actions.
4. Avoid `restoreSafariFocus()` doing synchronous AppleScript during dismiss. Restore focus asynchronously, or skip if unavailable.

Acceptance criteria:

- Pressing Return may launch automation, but the UI does not beachball.
- Dismiss remains instant even if Safari is unresponsive.

### Phase 8: Clean Up Bookmark And Permission I/O

1. Move bookmark modification-date checks off-main.
2. Convert `SafariBookmarkStore.refreshIfNeeded()` to async/background metadata checks.
3. Convert permission probing to background worker calls with cached UI state.
4. Ensure all TCC/prompting actions happen only from explicit button clicks, never on open.

Acceptance criteria:

- Protected file access and permission status checks cannot block opening Settings or typing.

### Phase 9: Add Regression Tests And Manual Stress Scenarios

1. Unit-test suggestion computer/ranker with large synthetic datasets.
2. Add performance tests for:
   - snapshot creation;
   - empty query;
   - typed query;
   - settings scope query.
3. Add debug stress fixtures:
   - 10k bookmarks;
   - 1k tabs;
   - 1k recents;
   - denied Accessibility/Apple Events;
   - Safari not running;
   - Safari hung/unresponsive.
4. Manual validation:
   - open Settings while Safari is busy;
   - open command palette while profile refresh is in progress;
   - type rapidly during pasteboard/web suggestion refresh;
   - switch Settings tabs during permission refresh;
   - dismiss palette while Safari is unavailable.

Acceptance criteria:

- No main-thread stall over the chosen threshold during open/type/dismiss paths.
- All slow dependencies degrade to stale/loading/error UI.

## Recommended Implementation Order

1. Event tap decoupling and Settings UI-first open.
2. Async profile discovery, because this is the largest Settings-specific blocker.
3. Command palette UI-first `show()` split and removal/deferment of the per-open CG event tap.
4. Snapshot cache/pre-index work for typing responsiveness.
5. Async clipboard/actions/permission/bookmark metadata cleanup.
6. Stress tests and stall detector gates.

## Definition Of Done

- Settings opens immediately and remains interactive with Safari closed, Safari hung, permissions denied, or Full Disk Access missing.
- Command palette opens and focuses immediately from `Cmd+T`.
- Typing in the command palette never waits on AppleScript, AX, pasteboard, network, file I/O, or full-store copies.
- Event tap callbacks never perform UI creation, AppleScript, AX reads, or monitor refreshes synchronously.
- Any slow external dependency produces cached, loading, or error UI instead of freezing the app.
