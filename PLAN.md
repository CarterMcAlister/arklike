# Arklike macOS App Implementation Plan

## Context

The goal is to recreate the Arc workflows missed after moving to Safari:

- `Cmd+T` opens a command-palette style URL/search menu while Safari is frontmost, then opens the selected URL/search in a new Safari tab.
- `Cmd+Shift+C` copies the current Safari tab URL.
- `Cmd+S` toggles Safari’s native sidebar.
- `Ctrl+1`, `Ctrl+2`, etc. switch to numbered Safari profiles.
- Traffic Control routes matching URLs to the selected Safari profile.

Research and static inspection of `/Applications/SupaSidebar.app` indicate the most practical implementation is a **native macOS app first**, not a Safari extension first. SupaSidebar appears to implement browser command-panel/profile-routing features as a menu-bar app with global shortcut handling, Apple Events, Accessibility/AX, and browser automation. It does not appear to ship an embedded Safari Web Extension.

The current repository has no application source yet, so this plan assumes creating a new Swift macOS app project from scratch.

## Approach

Build a Swift/SwiftUI menu-bar macOS app that owns the core experience:

1. A native keyboard shortcut/event layer detects Safari-scoped shortcuts only.
2. A native command palette appears over Safari for `Cmd+T`.
3. A Safari automation adapter mirrors SupaSidebar’s apparent approach: AppleScript for Safari tab/window operations, `System Events` for menu actions, and Accessibility/AX for focused-window discovery and fallbacks.
4. Safari profile support is implemented through user-configured profile names plus menu/AX automation because Safari exposes no stable public profile API.
5. Traffic Control is implemented in the native app as a default-browser URL router for links opened outside Safari.
6. No Safari extension is planned for MVP; the app will stay native-only until the Safari workflows are proven.

This avoids depending on Safari WebExtension keyboard-command limitations and mirrors the proven native-first pattern observed in SupaSidebar.

## Files to modify / create

Because the repo is currently empty, create a new macOS app project with a structure similar to:

- `Arklike.xcodeproj` or `Package.swift` plus Xcode project files
- `Arklike/ArklikeApp.swift`
- `Arklike/AppDelegate.swift`
- `Arklike/Info.plist`
- `Arklike/Arklike.entitlements`
- `Arklike/Models/Profile.swift`
- `Arklike/Models/TrafficRule.swift`
- `Arklike/Models/AppSettings.swift`
- `Arklike/Services/ShortcutManager.swift`
- `Arklike/Services/FrontmostSafariMonitor.swift`
- `Arklike/Services/PermissionsManager.swift`
- `Arklike/Services/ClipboardService.swift`
- `Arklike/Services/URLParser.swift`
- `Arklike/Services/SearchEngineService.swift`
- `Arklike/Services/TrafficRuleMatcher.swift`
- `Arklike/Services/DefaultBrowserRouter.swift`
- `Arklike/Browser/SafariAutomation.swift`
- `Arklike/Browser/SafariProfileManager.swift`
- `Arklike/Browser/SafariSidebarController.swift`
- `Arklike/Browser/SafariHistoryService.swift`
- `Arklike/Browser/SafariAppleScriptTemplates.swift`
- `Arklike/UI/MenuBarController.swift`
- `Arklike/UI/CommandPalette/CommandPaletteWindow.swift`
- `Arklike/UI/CommandPalette/CommandPaletteView.swift`
- `Arklike/UI/Settings/SettingsWindow.swift`
- `Arklike/UI/Settings/ProfilesSettingsView.swift`
- `Arklike/UI/Settings/TrafficControlSettingsView.swift`
- `Arklike/UI/Settings/ShortcutSettingsView.swift`
- `Arklike/UI/Settings/PermissionsSettingsView.swift`
- `ArklikeTests/URLParserTests.swift`
- `ArklikeTests/TrafficRuleMatcherTests.swift`
- `ArklikeTests/SearchEngineServiceTests.swift`

## Reuse / external learnings

- SupaSidebar architecture-level learnings:
  - Use a menu-bar app (`LSUIElement=true`) for Safari-focused browser utilities.
  - Implement `Cmd+T` using native shortcut/event handling scoped to Safari instead of a Safari WebExtension command.
  - Use Apple Events, `System Events`, and Accessibility/AX together: AppleScript for Safari tabs/windows, AX for focused Safari window tracking and fallback URL/title extraction, and menu scripting for profile/sidebar actions.
  - Keep profile discovery/routing native because Safari profiles are not exposed through WebExtension APIs.
  - Provide settings toggles for Safari command-panel behavior, shortcut rebinding, and profile discovery.
- macOS APIs/utilities to use:
  - `NSStatusItem` for menu-bar UI.
  - `NSPanel` or borderless floating `NSWindow` for command palette.
  - `NSPasteboard` for copying URLs.
  - `NSWorkspace` for frontmost Safari detection and URL events.
  - `AXIsProcessTrustedWithOptions` and Accessibility APIs for permission checks, active Safari window tracking, and UI fallback automation.
  - AppleScript via `NSAppleScript` or `OSAKit` for Safari tab/window/profile automation.
  - Carbon hotkeys as the shortcut backend, with a SwiftUI rebinding UI stored in app settings.

## Implementation steps

### 1. Create the native macOS app shell

- [ ] Create a Swift macOS app target named `Arklike`.
- [ ] Configure it as a menu-bar app using `LSUIElement=true`.
- [ ] Add a simple `NSStatusItem` menu with:
  - Open Command Palette
  - Settings
  - Check Permissions
  - Quit
- [ ] Add app entitlements/usage descriptions for:
  - Apple Events automation
  - Accessibility onboarding text
- [ ] Decide whether the app will be sandboxed for distribution. If sandboxed, add the Apple Events entitlement and test Safari automation carefully.

### 2. Build permissions onboarding

- [ ] Implement `PermissionsManager` to check:
  - Accessibility permission
  - Apple Events permission to control Safari
  - whether app is default browser, once Traffic Control is enabled
- [ ] Add a settings/onboarding screen explaining why each permission is needed.
- [ ] Provide buttons to open the relevant macOS Settings panes.
- [ ] Make the app degrade gracefully when permissions are missing:
  - Command palette can open without Automation.
  - Opening Safari tabs/profile switching requires Automation and/or Accessibility.

### 3. Implement Safari-only frontmost/window detection

- [ ] Implement `FrontmostSafariMonitor` using `NSWorkspace.shared.frontmostApplication` and activation notifications.
- [ ] Support only Safari for simplicity: `com.apple.Safari`.
- [ ] Track the active Safari window, not just the app, because users may have multiple Safari windows across different profiles/spaces.
- [ ] Use AX focused-window notifications where available (`AXFocusedWindowChanged`) and fall back to Safari AppleScript window enumeration.
- [ ] Store the current Safari window id/title/profile hints so command-palette actions, copy URL, sidebar toggle, and profile switching target the correct window whenever possible.
- [ ] Add settings for enabling/disabling Safari shortcut overrides.
- [ ] Ensure shortcut handling only overrides behavior when Safari is frontmost and the relevant shortcut is enabled.

### 4. Implement Carbon-backed shortcut handling and rebinding

- [ ] Implement `ShortcutManager` using Carbon hotkeys as the shortcut backend.
- [ ] Ship these default shortcuts:
  - `Cmd+T` → command palette
  - `Cmd+Shift+C` → copy current URL
  - `Cmd+S` → toggle Safari native sidebar
  - `Ctrl+1` ... `Ctrl+9` → switch/open assigned Safari profile
- [ ] Add `ShortcutSettingsView` so the user can rebind every shortcut while preserving these defaults.
- [ ] Persist rebinding choices in app settings.
- [ ] Detect shortcut conflicts inside the app and warn before saving duplicate bindings.
- [ ] Scope execution to Safari: if Safari is not frontmost, do not perform the action.
- [ ] For `Cmd+T` and `Cmd+S`, capture and consume the event so Safari does not also create a normal tab or save the page.

### 5. Build the native command palette with SupaSidebar-style parity

- [ ] Implement a floating `NSPanel`/`NSWindow` centered near the top of the active Safari window/screen.
- [ ] Build a SwiftUI `CommandPaletteView` with:
  - focused text input
  - URL/search preview
  - keyboard navigation
  - Escape to dismiss
  - Return to open
- [ ] Mirror the non-sidebar, non-AI command-palette capabilities observed in SupaSidebar strings/resources:
  - open URL or search query
  - list and switch to currently open Safari tabs
  - list recent URLs opened/routed by Arklike
  - search Safari history where permissions allow, with clear fallback to Arklike-owned recents
  - list configured search engines and custom site-search shortcuts
  - list Safari profiles and open/switch to one
  - list Traffic Control rules and show which rule would match the typed URL
  - open Arklike settings directly to relevant tabs such as Shortcuts, Profiles, Command Palette, and Traffic Control
- [ ] Explicitly exclude SupaSidebar sidebar/workspace/link-management features and AI/chat actions from the parity target.
- [ ] Rank results in this order: exact command/site shortcut, valid URL, open Safari tab, profile, Traffic Control rule/test result, history/recent, generic web search.
- [ ] Keep command palette data providers modular so tab/history/profile/rule providers can fail independently without breaking URL/search opening.

### 6. Implement URL/search parsing

- [ ] Implement `URLParser`:
  - Accept full `http://` and `https://` URLs.
  - Treat bare domains like `example.com` as `https://example.com`.
  - Treat localhost/IP URLs correctly.
  - Treat everything else as a search query.
- [ ] Implement `SearchEngineService` with configurable search URL template, defaulting to the user’s preferred engine or a simple configured default.
- [ ] Add unit tests for domains, URLs, localhost, spaces, special characters, and search queries.

### 7. Implement Safari automation mirroring SupaSidebar’s apparent strategy

- [ ] Implement `SafariAutomation` methods:
  - `getActiveTabURL() -> URL?`
  - `listWindowsAndTabs() -> [SafariWindowSnapshot]`
  - `activateWindow(windowId:)`
  - `activateTab(windowId:tabIndex:)`
  - `openURLInNewTab(_ url: URL, preferredWindowId: Int?)`
  - `openURLInNewWindow(_ url: URL)`
  - `activateSafari()`
- [ ] Follow the SupaSidebar-style multi-strategy approach:
  1. Use Safari AppleScript for canonical windows/tabs/current tab URL, including Safari window ids and tab indices.
  2. Use `System Events`/AX to raise the intended Safari window (`AXRaise`) and perform menu actions when Safari AppleScript cannot express the action, especially profile/sidebar operations.
  3. Use AX focused-window observation/cache to know which Safari window the user was actually using before the command palette opened.
  4. Fall back to AppleScript enumeration if AX URL/title extraction or notifications are unavailable.
- [ ] Design snapshots to handle multiple Safari windows and avoid accidentally opening/searching in the wrong window.
- [ ] Return structured errors so UI can explain missing permissions or unsupported states.

### 8. Implement `Cmd+Shift+C` copy URL

- [ ] On shortcut, call `SafariAutomation.getActiveTabURL()` for the active Safari window/tab.
- [ ] Write the URL string to `NSPasteboard`.
- [ ] Show lightweight confirmation in the menu-bar app or command palette HUD.
- [ ] If Safari is not frontmost or no URL is available, show a non-intrusive error.

### 9. Implement `Cmd+S` Safari native sidebar toggle

- [ ] Implement `SafariSidebarController`.
- [ ] On shortcut, ensure Safari is frontmost and identify the active Safari window.
- [ ] Toggle Safari’s native sidebar using `System Events`/AX menu automation against Safari’s View/sidebar menu item.
- [ ] Fall back to sending Safari’s native sidebar keyboard equivalent if menu lookup fails.
- [ ] Consume the original `Cmd+S` event so Safari does not save the page.
- [ ] Include this shortcut in `ShortcutSettingsView` so users can rebind it.

### 10. Implement Safari profile model and settings

- [ ] Create `Profile` model:
  - id
  - display name
  - assigned number `1...9`
  - optional Safari menu title
  - optional color/icon metadata
- [ ] Add `ProfilesSettingsView` where users can manually enter Safari profile names and assign numbers.
- [ ] Add a “Discover Profiles” action that attempts to inspect Safari’s `File` menu via Accessibility/System Events to find `New [Profile] Window` entries.
- [ ] Store mappings locally using `UserDefaults`, SwiftData, SQLite, or JSON. Use a simple durable store first.
- [ ] Treat manual configuration as the source of truth because automatic profile discovery may be brittle.

### 11. Implement profile switching/opening

- [ ] Implement `SafariProfileManager` methods:
  - `switchToProfile(number: Int)`
  - `openNewWindow(profile: Profile)`
  - `openURL(_ url: URL, in profile: Profile)`
- [ ] Strategy for `Ctrl+number`:
  1. Check whether Safari has an existing window for the target profile, if discoverable.
  2. If found, raise/activate it.
  3. If not found, invoke Safari menu item `File > New [Profile] Window` via `System Events`/AX.
- [ ] Because Safari does not expose a stable public profile API, keep this code isolated behind `SafariProfileManager` and log failures clearly.
- [ ] Add settings guidance: profile names must exactly match Safari menu names if automatic discovery fails.

### 12. Register app as default browser for Traffic Control

- [ ] Add URL handling for `http` and `https` in `Info.plist`.
- [ ] Implement `DefaultBrowserRouter` to receive URLs opened by macOS.
- [ ] Add settings button to make Arklike the default browser.
- [ ] On incoming URL:
  - normalize URL
  - evaluate Traffic Control rules
  - choose target profile/default behavior
  - route to Safari
- [ ] Prevent routing loops by ensuring internal opens go directly to Safari, not through the default browser handler again.

### 13. Implement Traffic Control rules

- [ ] Create `TrafficRule` model:
  - enabled
  - name
  - priority/order
  - matcher type: domain, wildcard, substring, regex
  - pattern
  - target profile id/number
  - open behavior: new tab, new window, reuse existing profile window if possible
- [ ] Implement `TrafficRuleMatcher`:
  - first enabled matching rule wins
  - deterministic ordering
  - validation for invalid regex/wildcards
- [ ] Build `TrafficControlSettingsView`:
  - list rules
  - add/edit/delete/reorder
  - test URL against rules
- [ ] Add unit tests for matcher behavior.

### 14. Logging, diagnostics, and resilience

- [ ] Add structured logging around:
  - shortcut capture
  - permission checks
  - Safari AppleScript failures
  - AX/menu discovery failures
  - Traffic Control matches
- [ ] Add a diagnostics panel that reports:
  - Accessibility enabled/disabled
  - Automation authorized/denied
  - default browser status
  - discovered profiles
  - last routing decision
- [ ] Include a “Copy Diagnostics” button for debugging.

### 15. Packaging/distribution

- [ ] Decide distribution route:
  - local developer build first
  - Developer ID notarized app for direct distribution
  - App Store only if sandbox/automation constraints are acceptable
- [ ] If direct distribution, optionally add Sparkle-style updates later.
- [ ] Add first-run onboarding for permissions and Safari profile setup.

## Verification

### Unit tests

- [ ] `URLParserTests` cover URL/search detection.
- [ ] `SearchEngineServiceTests` cover search URL generation and encoding.
- [ ] `TrafficRuleMatcherTests` cover domain/wildcard/regex ordering and invalid patterns.

### Manual Safari tests

- [ ] With Safari frontmost, pressing `Cmd+T` opens Arklike command palette instead of Safari’s normal new tab.
- [ ] With another app frontmost, `Cmd+T` behaves normally for that app.
- [ ] With multiple Safari windows open, `Cmd+T` opens/searches in the window that was active before the palette appeared.
- [ ] Entering `example.com` opens `https://example.com` in a new Safari tab.
- [ ] Entering `hello world` opens a search results tab.
- [ ] `Cmd+Shift+C` copies active Safari URL exactly.
- [ ] `Cmd+S` toggles Safari’s native sidebar and does not trigger Save Page.
- [ ] `Ctrl+1` opens/switches to profile 1.
- [ ] `Ctrl+2` opens/switches to profile 2.
- [ ] Traffic Control external link from Mail/Slack/Terminal routes to the expected Safari profile.
- [ ] Invalid or unmatched URLs fall back to default Safari behavior.

### Permission/failure tests

- [ ] Accessibility denied: app explains that shortcut interception/profile switching may not work.
- [ ] Apple Events denied: app explains Safari automation cannot run and offers remediation.
- [ ] Safari closed: opening URL launches Safari and routes as best as possible.
- [ ] Profile name missing/changed: app surfaces a clear error and points to profile settings.

## Risks and mitigations

- **`Cmd+T` / `Cmd+S` interception risk:** Safari owns these shortcuts for new tab/save page.
  - Mitigation: use the Carbon-backed shortcut layer and consume matching events only when Safari is frontmost; include diagnostics if a user-level conflict prevents capture.
- **Safari profile API risk:** Safari has no stable public API for opening URLs in a specific profile.
  - Mitigation: isolate AX/menu scripting behind `SafariProfileManager`; support manual profile names; surface failures clearly.
- **Permissions friction:** Accessibility and Apple Events permissions are intrusive.
  - Mitigation: explain value clearly during onboarding and degrade gracefully.
- **Traffic Control coverage:** Native default-browser routing covers links opened from outside Safari, but not every navigation initiated inside Safari.
  - Mitigation: treat external-link routing as MVP scope and document that in-Safari click interception is intentionally out of scope for now.
- **OS/Safari UI changes:** Menu scripting can break across Safari/macOS releases.
  - Mitigation: diagnostics, logs, isolated adapter, and user-editable profile mappings.

## Non-goals for MVP

- Cross-browser support beyond Safari.
- Safari Web Extension support.
- Full Arc sidebar replacement.
- SupaSidebar sidebar/workspace/link-management features.
- SupaSidebar AI/chat features.
- Syncing settings across machines.
- App Store release constraints until the local/native approach is proven.
