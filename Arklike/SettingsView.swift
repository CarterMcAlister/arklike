import SwiftUI

struct SettingsView: View {
    @StateObject private var permissions = PermissionsManager.shared
    @StateObject private var appSettings = AppSettings.shared
    @StateObject private var safariMonitor = FrontmostSafariMonitor.shared

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            header

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

            Divider()

            safariShortcutOverridesSection

            ShortcutSettingsView()
                .padding(14)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            Divider()

            safariMonitorSection

            ProfilesSettingsView()
                .padding(14)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            TrafficControlSettingsView()
                .padding(14)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            Divider()

            DiagnosticsView()
                .padding(14)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text("Graceful degradation")
                    .font(.headline)
                Text("• The command palette UI can open without Apple Events permission.")
                Text("• Opening Safari tabs and copying the current URL require Apple Events permission.")
                Text("• Profile switching, menu automation, and the Safari sidebar toggle require Apple Events plus Accessibility permission.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button("Refresh") {
                    permissions.refresh()
                    safariMonitor.refresh(reason: "settings refresh")
                }
                Spacer()
            }
        }
        .padding(24)
        }
        .frame(width: 720, height: 760)
        .onAppear {
            permissions.refresh()
            safariMonitor.start()
            safariMonitor.refresh(reason: "settings appear")
        }
    }

    private var safariShortcutOverridesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Safari shortcut overrides")
                .font(.headline)
            Toggle("Enable Safari shortcut overrides", isOn: $appSettings.safariShortcutOverridesEnabled)
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
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Arklike Settings")
                .font(.title2)
                .bold()
            Text("Arklike needs a small set of macOS permissions to reproduce Safari-focused Arc workflows. Grant only what you need; unavailable features will explain what permission is missing.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            Text("Running app: \(Bundle.main.bundleURL.path)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
