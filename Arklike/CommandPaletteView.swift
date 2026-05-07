import SwiftUI

struct CommandPaletteView: View {
    let controller: CommandPaletteController
    @ObservedObject private var state: CommandPanelState
    @FocusState private var inputFocused: Bool

    init(controller: CommandPaletteController) {
        self.controller = controller
        self.state = controller.state
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if state.suggestions.isEmpty {
                ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text(emptyDescription))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(state.suggestions.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    controller.select(index: index)
                                    controller.perform(item)
                                } label: {
                                    CommandPaletteRow(item: item, isSelected: index == state.selectedIndex)
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: state.selectionScrollRequestID) { _, _ in
                        guard state.suggestions.indices.contains(state.selectedIndex) else { return }
                        proxy.scrollTo(state.suggestions[state.selectedIndex].id, anchor: .center)
                    }
                }
            }

            Divider()
            footer
        }
        .padding(.top, 12)
        .frame(width: 720, height: 392)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { focusInput() }
        .onChange(of: state.inputFocusRequestID) { _, _ in focusInput() }
        .onExitCommand { controller.dismiss() }
        .onMoveCommand { direction in
            switch direction {
            case .up: controller.moveSelection(delta: -1)
            case .down: controller.moveSelection(delta: 1)
            default: break
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: headerIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                ZStack(alignment: .leading) {
                    TextField(placeholder, text: Binding(
                        get: { state.currentInputText },
                        set: { controller.updateInputText($0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($inputFocused)
                    .onSubmit { controller.performSelected() }
                    .simultaneousGesture(TapGesture().onEnded { focusInput() })

                    if state.mode == .search, !state.autocompleteText.isEmpty, !state.query.isEmpty {
                        HStack(spacing: 0) {
                            Text(state.query)
                                .font(.title3)
                                .foregroundStyle(.clear)
                            Text(autocompleteSuffix)
                                .font(.title3)
                                .foregroundStyle(.secondary.opacity(0.55))
                            Spacer()
                        }
                        .allowsHitTesting(false)
                    }
                }
                if let activeScope = state.activeScope {
                    HStack(spacing: 4) {
                        Image(systemName: activeScope.iconName)
                        Text(activeScope.title)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 0)
            .padding(.bottom, 8)

            if state.mode == .scopePicker {
                Text("Select a scope to search in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 42)
                    .padding(.bottom, 3)
            } else if state.mode == .actions {
                Text("Actions for selected item")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 42)
                    .padding(.bottom, 3)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if state.mode == .scopePicker {
                Text("↩ select")
                Text("↑↓ navigate")
                Text("⎋ back")
            } else if state.mode == .actions {
                Text("↩ run action")
                Text("↑↓ navigate")
                Text("⎋ back")
            } else {
                Text("↩ open")
                Text("⌘↩ search web")
                Text("⌥↩ actions")
                Text("⇧⇥ scope")
                Text("/ scopes")
                Text("⎋ close")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var headerIcon: String {
        switch state.mode {
        case .search: "magnifyingglass"
        case .scopePicker: "line.3.horizontal.decrease.circle"
        case .actions: "bolt"
        }
    }

    private var placeholder: String {
        switch state.mode {
        case .search:
            if let activeScope = state.activeScope { return "Searching \(activeScope.title.lowercased())" }
            return "Search, enter URL, switch Safari tabs, or open bookmarks…"
        case .scopePicker:
            return "Search scopes…"
        case .actions:
            return "Choose an action…"
        }
    }

    private var emptyDescription: String {
        switch state.mode {
        case .scopePicker: "No matching scopes"
        case .actions: "No actions are available for this result."
        case .search: "Try a URL, search query, Safari tab, recent item, or bookmark."
        }
    }

    private var autocompleteSuffix: String {
        guard state.autocompleteText.localizedCaseInsensitiveContains(state.query), state.autocompleteText.count > state.query.count else {
            return "  → \(state.autocompleteText)"
        }
        let index = state.autocompleteText.index(state.autocompleteText.startIndex, offsetBy: state.query.count)
        return String(state.autocompleteText[index...])
    }

    private func focusInput() {
        inputFocused = true
        DispatchQueue.main.async {
            inputFocused = true
        }
    }
}

#if DEBUG
#Preview("Command Palette — Search") {
    CommandPaletteView(controller: .preview(mode: .search))
}

#Preview("Command Palette — Scopes") {
    CommandPaletteView(controller: .preview(mode: .scopePicker))
}

#Preview("Command Palette — Actions") {
    CommandPaletteView(controller: .preview(mode: .actions))
}
#endif

private struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconSystemName)
                .frame(width: 22)
                .foregroundStyle(isSelected ? .white : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                highlightedText(item.title, ranges: item.titleMatchRanges, base: isSelected ? .white : .primary)
                    .lineLimit(1)
                highlightedText(item.subtitle, ranges: item.subtitleMatchRanges, base: isSelected ? .white.opacity(0.8) : .secondary)
                    .font(.caption)
                    .lineLimit(1)
            }
            Spacer()
            if item.kind == .scope, let scope = item.scope {
                Text(scope.title)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background((isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12)), in: Capsule())
                    .foregroundStyle(isSelected ? .white : .secondary)
            } else {
                Text(label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background((isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12)), in: Capsule())
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func highlightedText(_ text: String, ranges: [Range<String.Index>], base: Color) -> Text {
        var attributed = AttributedString(text)
        attributed.foregroundColor = base

        for range in ranges {
            guard range.lowerBound >= text.startIndex,
                  range.upperBound <= text.endIndex,
                  let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].foregroundColor = isSelected ? .white : .accentColor
            attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }

        return Text(attributed)
    }

    private var label: String {
        switch item.kind {
        case .historyOrRecent: "recent"
        case .searchHistory: "history"
        case .webSuggestion: "suggest"
        case .pasteAndGo: "paste"
        case .safariTab: "tab"
        case .siteShortcut: "shortcut"
        default: item.kind.rawValue
        }
    }
}
