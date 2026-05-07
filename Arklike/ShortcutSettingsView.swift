import SwiftUI

struct ShortcutSettingsView: View {
    @StateObject private var shortcutManager = ShortcutManager.shared
    @State private var recordingAction: ShortcutAction?
    @State private var localMonitor: Any?
    @State private var transientMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shortcuts")
                    .font(.headline)
                Spacer()
                Button("Reset All") {
                    shortcutManager.resetAllShortcuts()
                    transientMessage = "Restored default shortcuts."
                }
            }

            Text("Shortcuts are only executed when Safari is frontmost. Cmd+T and Cmd+S are consumed in Safari so Safari does not also open a new tab or save the page.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let conflictMessage = shortcutManager.conflictMessage {
                Text(conflictMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if let transientMessage {
                Text(transientMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("Action").font(.caption).foregroundStyle(.secondary)
                    Text("Shortcut").font(.caption).foregroundStyle(.secondary)
                    Text("Default").font(.caption).foregroundStyle(.secondary)
                    Text("")
                }

                ForEach(ShortcutAction.allCases) { action in
                    GridRow {
                        Text(action.title)
                        Button(recordingAction == action ? "Press shortcut…" : shortcutManager.shortcut(for: action).displayString) {
                            beginRecording(action)
                        }
                        .keyboardShortcut(.defaultAction)
                        Text(action.defaultShortcut.displayString)
                            .foregroundStyle(.secondary)
                        Button("Reset") {
                            shortcutManager.resetShortcut(action)
                            transientMessage = "Reset \(action.title)."
                        }
                    }
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func beginRecording(_ action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        transientMessage = "Press a shortcut for \(action.title), or Escape to cancel."

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                stopRecording()
                return nil
            }

            guard let shortcut = KeyboardShortcut.from(event: event) else {
                transientMessage = "Shortcut must include at least one modifier."
                return nil
            }

            if shortcutManager.updateShortcut(shortcut, for: action) {
                transientMessage = "Updated \(action.title) to \(shortcut.displayString)."
                stopRecording()
            } else {
                transientMessage = shortcutManager.conflictMessage
            }
            return nil
        }
    }

    private func stopRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        recordingAction = nil
    }
}

struct SearchShortcutSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search Shortcuts")
                    .font(.headline)
                Spacer()
                Button("Add") { appSettings.addSearchShortcut() }
                Button("Reset") { appSettings.resetSearchShortcuts() }
            }

            Text("Type a keyword followed by a space or colon in the command palette, such as “gh test”, to search a specific site. URL templates use {query} for the encoded search text.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("On").font(.caption).foregroundStyle(.secondary)
                    Text("Keyword").font(.caption).foregroundStyle(.secondary)
                    Text("Name").font(.caption).foregroundStyle(.secondary)
                    Text("Aliases").font(.caption).foregroundStyle(.secondary)
                    Text("URL Template").font(.caption).foregroundStyle(.secondary)
                    Text("")
                }

                ForEach($appSettings.searchShortcuts) { $shortcut in
                    GridRow {
                        Toggle("", isOn: $shortcut.isEnabled)
                            .labelsHidden()
                        TextField("gh", text: $shortcut.keyword)
                            .frame(width: 54)
                        TextField("GitHub", text: $shortcut.name)
                            .frame(width: 110)
                        TextField("github", text: $shortcut.aliasesText)
                            .frame(width: 110)
                        TextField("https://example.com/search?q={query}", text: $shortcut.urlTemplate)
                            .frame(minWidth: 230)
                        Button(role: .destructive) {
                            appSettings.deleteSearchShortcut(id: shortcut.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Shortcut Settings") {
    let _ = PreviewFixtures.configureAppState()
    ShortcutSettingsView()
        .padding(20)
        .frame(width: 720)
}

#Preview("Search Shortcut Settings") {
    let _ = PreviewFixtures.configureAppState()
    SearchShortcutSettingsView()
        .padding(20)
        .frame(width: 720)
}
#endif
