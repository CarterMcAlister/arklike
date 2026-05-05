SupaSidebar Safari Integration Recon (Architecture-Level, Non-Source)

Scope: Static inspection of `/Applications/SupaSidebar.app` bundle metadata/resources/strings only. No proprietary source code reproduced.

1) What files/components exist

- Main app bundle
  - `Contents/MacOS/supasidebar` (universal binary)
  - `Contents/Info.plist` (`CFBundleIdentifier=com.supasidebar`, `LSUIElement=true` menu-bar style app)
  - `Contents/Resources/*` includes localizations, Core Data model, config plists, bundled 3rd-party resources.
- Frameworks
  - `Contents/Frameworks/Sparkle.framework` (direct-update mechanism)
  - No app-specific helper framework indicating Safari extension runtime.
- Extensions / web extension artifacts
  - No `PlugIns/*.appex`
  - No Safari Web Extension `manifest.json`
  - No Safari extension bundle identifiers/manifests found in app bundle.
- Entitlements / permissions evidence
  - App entitlements include:
    - `com.apple.security.automation.apple-events = true`
    - `com.apple.security.temporary-exception.apple-events` with many browser bundle IDs including `com.apple.Safari`
    - audio/keychain/read-only user-selected file access
  - `Info.plist` usage strings include Apple Events and Accessibility purpose text.
- URL scheme / IPC clues
  - Custom URL scheme declared: `supasidebar://` via `CFBundleURLSchemes`.
- Login/menu-bar clues
  - `LSUIElement=true` + binary strings reference `NSStatusItem` and menu bar actions.
  - No embedded LoginItems/Helpers directory found.
- Shortcut subsystem clues
  - Bundled `KeyboardShortcuts_KeyboardShortcuts.bundle` (strong signal of KeyboardShortcuts-style hotkey UI/recording).
  - Binary links `Carbon.framework` and contains hotkey-related strings.

2) How Cmd+T likely works in Safari

Most likely mechanism is NOT a Safari Web Extension command. Evidence points to native macOS interception + automation:

- No Safari extension package/manifest present, so not manifest `commands`-based Safari Web Extension wiring.
- Binary/localized strings indicate a feature like “Use Cmd+T in browsers” and browser-scoped command-panel behavior.
- Strings reference a setting key consistent with Cmd+T browser hijack behavior and text indicating:
  - only hijack when a browser is frontmost,
  - let other apps keep normal Cmd+T behavior.
- Entitlements and strings show heavy Apple Events + Accessibility (`AX*`) + `System Events` menu interactions, consistent with:
  - detecting frontmost browser,
  - handling keyboard shortcut routing conditionally,
  - activating/switching/opening tabs via AppleScript/AX when needed.

Likely flow (inference):
- Global key handling/event tap/hotkey listener sees Cmd+T.
- If active app is in supported browser set (including Safari), SupaSidebar opens its command panel instead of new tab.
- For actual tab operations, it uses Apple Events / AppleScript and AX fallback logic rather than Safari extension APIs.

3) Which desired features appear supported, and by what mechanism

- Safari tab visibility/control: Yes (likely)
  - Mechanism: Apple Events (Safari scripting) + AX observers/AX element reads/fallbacks.
- Browser profile discovery/routing (including Safari profiles): Yes
  - Mechanism: `System Events` menu scraping + browser automation; localized settings mention profile discovery and menu scraping.
- Cmd+T command panel in browsers: Yes (strong evidence)
  - Mechanism: app-level keyboard interception/shortcut strategy scoped to frontmost browser, not web-extension command manifest.
- Live tabs across browsers: Yes
  - Mechanism: native automation/integration with multiple browser bundle IDs; strings mention cross-browser live tabs and tab sync.
- Safari Web Extension command menu: No evidence
  - Mechanism absent in bundle (no appex/manifest).
- Native messaging host/App Groups for extension bridge: No evidence in inspected bundle
  - No app-group entitlement seen; no native messaging manifests found.
- Menu bar app behavior: Yes
  - Mechanism: `LSUIElement` + status item/menu actions.

4) Actionable learnings for your implementation plan

- If your goal is Safari Cmd+T remap to a native command panel, you can implement without Safari Web Extension by:
  - frontmost-app-aware key interception strategy,
  - browser whitelist/feature toggle (“only in browsers”),
  - fallback to normal behavior outside target apps.
- Plan for permissions explicitly:
  - Accessibility (AX observation/tab switching fallbacks),
  - Automation (Apple Events to Safari and other browsers).
- Include robust multi-strategy tab operations:
  - prefer native scripting where possible,
  - fallback to AX/window/tab heuristics when browser scripting is limited.
- Expose clear settings UX:
  - “Use Cmd+T in browsers” toggle,
  - per-browser/profile controls,
  - profile discovery refresh and optional deeper menu scraping.
- Keep architecture modular:
  - shortcut manager,
  - frontmost app detector,
  - browser automation adapters (Safari/Chromium/Firefox variants),
  - profile manager,
  - command panel manager.

5) Caveats / uncertainties

- This is static bundle forensics only; behavior in runtime may differ by OS/browser version.
- Strings/symbols can include stale or debug paths and do not guarantee all paths are active.
- Absence of Safari extension artifacts in this bundle strongly suggests non-extension approach, but cannot rule out external companion components installed separately.
- Exact low-level key capture API (event tap vs hotkey lib internals) cannot be proven conclusively from this inspection alone.