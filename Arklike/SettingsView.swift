import SwiftUI

private enum SettingsTab: Hashable {
    case general
    case permissions
    case profiles
    case trafficControl
    case shortcuts
    case searchShortcuts
    case diagnostics

    init(destination: SettingsDestination) {
        switch destination {
        case .general, .commandPalette:
            self = .general
        case .permissions:
            self = .permissions
        case .profiles:
            self = .profiles
        case .trafficControl:
            self = .trafficControl
        case .shortcuts:
            self = .shortcuts
        case .searchShortcuts:
            self = .searchShortcuts
        case .diagnostics:
            self = .diagnostics
        }
    }
}

struct SettingsView: View {
    @StateObject private var permissions = PermissionsManager.shared
    @StateObject private var appSettings = AppSettings.shared
    @StateObject private var launchAtLogin = LaunchAtLoginController.shared
    @StateObject private var safariMonitor = FrontmostSafariMonitor.shared
    @StateObject private var bookmarkStore = SafariBookmarkStore.shared
    @State private var selectedTab: SettingsTab

    init(initialDestination: SettingsDestination = .general) {
        _selectedTab = State(initialValue: SettingsTab(destination: initialDestination))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)

            profilesTab
                .tabItem { Label("Profiles", systemImage: "person.crop.circle") }
                .tag(SettingsTab.profiles)

            trafficControlTab
                .tabItem { Label("Traffic Control", systemImage: "arrow.triangle.branch") }
                .tag(SettingsTab.trafficControl)

            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            searchShortcutsTab
                .tabItem { Label("Search Shortcuts", systemImage: "magnifyingglass.circle") }
                .tag(SettingsTab.searchShortcuts)

            diagnosticsTab
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .tag(SettingsTab.diagnostics)
        }
        .frame(width: 760, height: 780)
        .onAppear {
#if DEBUG
            guard !PreviewFixtures.isRunningForPreviews else { return }
#endif
            permissions.refreshAsync()
            launchAtLogin.refreshAsync()
            safariMonitor.start()
            safariMonitor.scheduleRefresh(reason: "settings appear")
        }
        .onReceive(NotificationCenter.default.publisher(for: .arklikeSettingsDestinationRequested)) { notification in
            guard let destination = notification.object as? SettingsDestination else { return }
            selectedTab = SettingsTab(destination: destination)
        }
    }

    private var generalTab: some View {
        settingsPage {
            sectionHeader(
                title: "General",
                description: "Enable or disable Arklike’s Safari integration and tune command-palette behavior."
            )

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch Arklike at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(.switch)

                if let errorMessage = launchAtLogin.errorMessage {
                    Text("Could not update login item: \(errorMessage)")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Enable Arklike features in Safari", isOn: $appSettings.safariShortcutOverridesEnabled)
                    .toggleStyle(.switch)
                Text("Launch at login starts Arklike in the background after you sign in. When Safari integration is off, Arklike leaves Safari shortcuts alone and does not run Safari-scoped shortcut actions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsCard()

            shortcutFeatureTogglesSection

            VStack(alignment: .leading, spacing: 10) {
                Text("Command Palette")
                    .font(.headline)
                Toggle("Show Google web suggestions", isOn: $appSettings.webSearchSuggestionsEnabled)
                Toggle("Switch to existing Safari tabs instead of opening duplicates", isOn: $appSettings.switchToExistingSafariTabInsteadOfOpeningDuplicate)
                Text("These options control command-palette results and how Arklike opens matching Safari tabs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .settingsCard()
        }
    }

    private var permissionsTab: some View {
        settingsPage {
            sectionHeader(
                title: "Permissions",
                description: "Request and review the macOS permissions Arklike uses for Safari automation, bookmark search, and external-link routing."
            )

            permissionRows

            HStack {
                Button("Refresh Permission Status") {
                    permissions.refreshAsync()
                    bookmarkStore.refreshIfNeeded(force: false)
                }
                Spacer()
            }
        }
    }

    private var profilesTab: some View {
        settingsPage {
            sectionHeader(
                title: "Profiles",
                description: "Review detected Safari profiles and their assigned keyboard numbers."
            )

            ProfilesSettingsView()
                .settingsCard()
        }
    }

    private var trafficControlTab: some View {
        settingsPage {
            sectionHeader(
                title: "Traffic Control",
                description: "Configure profile-aware routing for external links opened through Arklike."
            )

            TrafficControlSettingsView()
                .settingsCard()
        }
    }

    private var shortcutsTab: some View {
        settingsPage {
            sectionHeader(
                title: "Shortcuts",
                description: "Rebind Arklike’s Safari shortcut key combinations."
            )

            ShortcutSettingsView()
                .settingsCard()
        }
    }

    private var searchShortcutsTab: some View {
        settingsPage {
            sectionHeader(
                title: "Search Shortcuts",
                description: "Configure command-palette shortcuts like “gh test” for site-specific searches."
            )

            SearchShortcutSettingsView()
                .settingsCard()
        }
    }

    private var diagnosticsTab: some View {
        settingsPage {
            sectionHeader(
                title: "Diagnostics",
                description: "Troubleshooting details for Safari focus tracking, permissions, and recent Arklike activity."
            )

            safariMonitorSection

            DiagnosticsView()
                .settingsCard()
        }
    }

    private var permissionRows: some View {
        Group {
            PermissionRow(
                title: "Accessibility",
                status: permissions.snapshot.accessibility,
                detail: "Needed to intercept Safari shortcuts, track the active Safari window, and automate Safari menu actions for profile switching and the native sidebar toggle.",
                primaryButtonTitle: "Request Permission",
                secondaryButtonTitle: "Open Accessibility Settings",
                primaryAction: { permissions.requestAccessibilityPermission() },
                secondaryAction: { permissions.openAccessibilitySettings() }
            )

            PermissionRow(
                title: "Apple Events for Safari",
                status: permissions.snapshot.appleEventsSafari,
                detail: "Needed to read the current Safari tab URL and open or activate Safari tabs/windows. The command palette can still open without this, but Safari tab/profile actions cannot run.",
                primaryButtonTitle: "Request Permission",
                secondaryButtonTitle: "Open Automation Settings",
                primaryAction: { permissions.requestAppleEventsPermissionForSafari() },
                secondaryAction: { permissions.openAutomationSettings() }
            )

            PermissionRow(
                title: "Default Browser",
                status: permissions.snapshot.defaultBrowser,
                detail: defaultBrowserDetail,
                primaryButtonTitle: "Make Arklike Default",
                secondaryButtonTitle: "Open Default Browser Settings",
                primaryAction: { permissions.setAsDefaultBrowser() },
                secondaryAction: { permissions.openDefaultBrowserSettings() }
            )

            PermissionRow(
                title: "Full Disk Access for Safari Bookmarks",
                status: bookmarkStore.lastError == nil ? .granted : .denied,
                detail: "Needed to read Safari’s local bookmark index automatically for command-menu bookmark search. After granting access, click Refresh Safari Bookmarks or reopen Arklike.",
                primaryButtonTitle: "Refresh Safari Bookmarks",
                secondaryButtonTitle: "Open Full Disk Access Settings",
                primaryAction: { bookmarkStore.reload(force: true) },
                secondaryAction: { permissions.openFullDiskAccessSettings() }
            )
        }
    }

    private var shortcutFeatureTogglesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shortcut Actions")
                .font(.headline)
            Toggle("Enable Cmd+T command palette", isOn: $appSettings.commandPaletteShortcutEnabled)
                .disabled(!appSettings.safariShortcutOverridesEnabled)
            Toggle("Enable Cmd+Shift+C copy URL", isOn: $appSettings.copyURLShortcutEnabled)
                .disabled(!appSettings.safariShortcutOverridesEnabled)
            Toggle("Enable Cmd+S sidebar toggle", isOn: $appSettings.sidebarShortcutEnabled)
                .disabled(!appSettings.safariShortcutOverridesEnabled)
            Toggle("Enable Ctrl+number profile shortcuts", isOn: $appSettings.profileShortcutsEnabled)
                .disabled(!appSettings.safariShortcutOverridesEnabled)
            Text("These flags authorize Arklike to act only when Safari is frontmost. Rebind the actual key combinations below.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .settingsCard()
    }

    private func settingsPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func sectionHeader(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
                .bold()
            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var safariMonitorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Safari window")
                .font(.headline)
            LabeledContent("Safari frontmost", value: safariMonitor.snapshot.isSafariFrontmost ? "Yes" : "No")
            LabeledContent("Frontmost bundle", value: safariMonitor.snapshot.frontmostBundleIdentifier ?? "Unknown")
            if let window = safariMonitor.snapshot.activeWindow {
                LabeledContent("Safari window id", value: window.safariWindowId.map(String.init) ?? "Unknown")
                LabeledContent("AX window number", value: window.accessibilityWindowNumber.map(String.init) ?? "Unknown")
                LabeledContent("Title", value: window.title ?? "Unknown")
                LabeledContent("Profile hint", value: window.profileHint ?? "Unknown")
                LabeledContent("Source", value: window.source.rawValue)
            } else {
                Text("No active Safari window is currently tracked.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var defaultBrowserDetail: String {
        if permissions.snapshot.defaultBrowser == .granted {
            return "Arklike is currently the default browser for external links, so Traffic Control can route links opened from other apps."
        }

        if let bundleIdentifier = permissions.snapshot.defaultBrowserBundleIdentifier {
            return "Traffic Control will eventually need Arklike to be the default browser for external links. Current default handler: \(bundleIdentifier)."
        }

        return "Traffic Control will eventually need Arklike to be the default browser for external links. The current default handler could not be determined."
    }
}

private extension View {
    func settingsCard() -> some View {
        padding(14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

#if DEBUG
@MainActor
enum PreviewFixtures {
    static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    static func configureAppState() {
        PermissionsManager.shared.applyPreviewSnapshot(permissionSnapshot)
        FrontmostSafariMonitor.shared.applyPreviewSnapshot(safariSnapshot)
        ProfileStore.shared.applyPreviewProfiles(profiles, message: "Preview data: mapped Ctrl+1... to Personal, Work, and Research.")
        TrafficRuleStore.shared.applyPreviewRules(trafficRules)
        SafariLiveTabStore.shared.applyPreviewTabs(safariTabs)
        SafariBookmarkStore.shared.applyPreviewBookmarks(bookmarks)
        CommandPanelRecentStore.shared.applyPreviewItems(recentItems)
        CommandPanelSearchHistoryStore.shared.applyPreviewQueries(["swift concurrency", "xcode previews", "safari profiles"])
        Diagnostics.shared.applyPreviewEvents([
            "Preview: command palette refreshed sample suggestions.",
            "Preview: matched github.com to Work profile.",
            "Preview: Safari permissions are mocked for canvas rendering."
        ], lastRoutingDecision: "github.com → Work profile")
    }

    static func settingsView(destination: SettingsDestination = .general) -> some View {
        configureAppState()
        return SettingsView(initialDestination: destination)
    }

    static var permissionSnapshot: PermissionSnapshot {
        PermissionSnapshot(
            accessibility: .granted,
            appleEventsSafari: .granted,
            defaultBrowser: .denied,
            defaultBrowserBundleIdentifier: "com.apple.Safari"
        )
    }

    static var safariSnapshot: FrontmostSafariSnapshot {
        FrontmostSafariSnapshot(
            isSafariFrontmost: true,
            frontmostBundleIdentifier: FrontmostSafariMonitor.safariBundleIdentifier,
            safariProcessIdentifier: 1234,
            activeWindow: SafariWindowContext(
                processIdentifier: 1234,
                safariWindowId: 42,
                accessibilityWindowNumber: 9001,
                title: "Arklike README — Safari [Work]",
                profileHint: "Work",
                center: CGPoint(x: 640, y: 420),
                source: .accessibilityFocusedWindow,
                observedAt: Date()
            ),
            lastActiveSafariWindow: SafariWindowContext(
                processIdentifier: 1234,
                safariWindowId: 42,
                accessibilityWindowNumber: 9001,
                title: "Arklike README — Safari [Work]",
                profileHint: "Work",
                center: CGPoint(x: 640, y: 420),
                source: .accessibilityFocusedWindow,
                observedAt: Date()
            ),
            shortcutOverridesEnabled: true,
            commandPaletteShortcutEnabled: true,
            copyURLShortcutEnabled: true,
            sidebarShortcutEnabled: true,
            profileShortcutsEnabled: true
        )
    }

    static var profiles: [Profile] {
        [
            Profile(displayName: "Personal", assignedNumber: 1, safariMenuTitle: "Personal", colorName: nil, iconName: "person.crop.circle"),
            Profile(displayName: "Work", assignedNumber: 2, safariMenuTitle: "Work", colorName: nil, iconName: "briefcase"),
            Profile(displayName: "Research", assignedNumber: 3, safariMenuTitle: "Research", colorName: nil, iconName: "book")
        ]
    }

    static var trafficRules: [TrafficRule] {
        [
            TrafficRule(name: "Work Links", order: 1, matcherType: .domain, pattern: "github.com", targetProfileNumber: 2),
            TrafficRule(name: "Docs", order: 2, matcherType: .wildcard, pattern: "*developer.apple.com*", targetProfileNumber: 3),
            TrafficRule(enabled: false, name: "Shopping", order: 3, matcherType: .substring, pattern: "checkout", targetProfileNumber: 1)
        ]
    }

    static var safariTabs: [SafariTabSnapshot] {
        [
            SafariTabSnapshot(windowId: 42, windowTitle: "Work", tabIndex: 1, title: "GitHub", url: URL(string: "https://github.com")!, isActive: true),
            SafariTabSnapshot(windowId: 42, windowTitle: "Work", tabIndex: 2, title: "Apple Developer Documentation", url: URL(string: "https://developer.apple.com/documentation")!, isActive: false),
            SafariTabSnapshot(windowId: 43, windowTitle: "Personal", tabIndex: 1, title: "Swift Forums", url: URL(string: "https://forums.swift.org")!, isActive: false)
        ]
    }

    static var bookmarks: [SafariBookmark] {
        [
            SafariBookmark(id: "bookmark-apple-docs", title: "Apple Developer Documentation", url: URL(string: "https://developer.apple.com/documentation")!, path: "Favorites/Developer"),
            SafariBookmark(id: "bookmark-swift", title: "Swift.org", url: URL(string: "https://swift.org")!, path: "Favorites/Developer")
        ]
    }

    static var recentItems: [CommandPanelRecentItem] {
        [
            CommandPanelRecentItem(url: URL(string: "https://github.com")!, title: "GitHub", source: "preview", lastAccessedAt: Date(), openCount: 8, safariWindowId: 42, safariProfileHint: "Work"),
            CommandPanelRecentItem(url: URL(string: "https://swift.org")!, title: "Swift.org", source: "preview", lastAccessedAt: Date().addingTimeInterval(-3600), openCount: 3, safariWindowId: 43, safariProfileHint: "Research")
        ]
    }

    static var commandPaletteSuggestions: [CommandPaletteItem] {
        let githubTitle = "GitHub"
        return [
            CommandPanelSuggestion(
                id: "preview-tab-github",
                title: githubTitle,
                subtitle: "https://github.com • Active Safari tab • Window 42",
                kind: .safariTab,
                scope: .liveTabs,
                representedURL: URL(string: "https://github.com")!,
                primaryAction: .switchToSafariTab(windowId: 42, tabIndex: 1),
                alternateActions: [CommandPanelAlternateAction(id: "copy-url", title: "Copy URL", subtitle: "https://github.com", iconSystemName: "doc.on.doc", action: .copyText("https://github.com"))],
                basePriority: 1,
                titleMatchRanges: [githubTitle.startIndex..<githubTitle.index(githubTitle.startIndex, offsetBy: 3)]
            ),
            CommandPanelSuggestion(
                id: "preview-bookmark-docs",
                title: "Apple Developer Documentation",
                subtitle: "https://developer.apple.com/documentation • Favorites/Developer",
                kind: .bookmark,
                scope: .bookmarks,
                representedURL: URL(string: "https://developer.apple.com/documentation")!,
                primaryAction: .openURL(URL(string: "https://developer.apple.com/documentation")!),
                basePriority: 2
            ),
            CommandPanelSuggestion(
                id: "preview-rule-work",
                title: "Work Links",
                subtitle: "Enabled • domain: github.com • Work",
                kind: .trafficRule,
                scope: .settings,
                representedURL: nil,
                primaryAction: .openSettings(.trafficControl),
                basePriority: 3
            ),
            CommandPanelSuggestion(
                id: "preview-search",
                title: "Search for “swift concurrency”",
                subtitle: "Search the web",
                kind: .search,
                scope: .all,
                representedURL: nil,
                primaryAction: .search("swift concurrency"),
                basePriority: 4
            )
        ]
    }
}

#Preview("Settings") {
    PreviewFixtures.settingsView()
}

#Preview("Settings — Traffic Control") {
    PreviewFixtures.settingsView(destination: .trafficControl)
}
#endif

private struct PermissionRow: View {
    let title: String
    let status: PermissionState
    let detail: String
    let primaryButtonTitle: String?
    let secondaryButtonTitle: String?
    let primaryAction: (() -> Void)?
    let secondaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(status.label)
                    .font(.caption)
                    .bold()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let primaryButtonTitle, let primaryAction {
                    Button(primaryButtonTitle, action: primaryAction)
                }
                if let secondaryButtonTitle, let secondaryAction {
                    Button(secondaryButtonTitle, action: secondaryAction)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusColor: Color {
        switch status {
        case .granted:
            .green
        case .denied:
            .orange
        case .unknown:
            .secondary
        }
    }
}
