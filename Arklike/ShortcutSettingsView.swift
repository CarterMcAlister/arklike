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
