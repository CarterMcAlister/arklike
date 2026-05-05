import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var controller: CommandPaletteController
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search, enter URL, switch tabs, profiles, rules…", text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($inputFocused)
                    .onSubmit { controller.performSelected() }
            }
            .padding(16)

            Divider()

            if controller.items.isEmpty {
                ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Try a URL, search query, profile, tab, or settings command."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, item in
                                CommandPaletteRow(item: item, isSelected: index == controller.selectedIndex)
                                    .id(item.id)
                                    .onTapGesture { controller.perform(item) }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: controller.selectedIndex) { _, newValue in
                        guard controller.items.indices.contains(newValue) else { return }
                        proxy.scrollTo(controller.items[newValue].id, anchor: .center)
                    }
                }
            }

            Divider()
            HStack {
                Text("↑↓ Navigate")
                Text("Return Open")
                Text("Esc Close")
                Spacer()
                Text("Safari-scoped")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 720, height: 420)
        .background(.regularMaterial)
        .onAppear { inputFocused = true }
        .onExitCommand { controller.dismiss() }
        .onMoveCommand { direction in
            switch direction {
            case .up: controller.moveSelection(delta: -1)
            case .down: controller.moveSelection(delta: 1)
            default: break
            }
        }
    }
}

private struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .frame(width: 22)
                .foregroundStyle(isSelected ? .white : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(item.subtitle)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            Spacer()
            Text(item.kind.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background((isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12)), in: Capsule())
                .foregroundStyle(isSelected ? .white : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch item.kind {
        case .exactCommand: "command"
        case .siteShortcut: "magnifyingglass.circle"
        case .url: "globe"
        case .safariTab: "safari"
        case .profile: "person.crop.circle"
        case .trafficRule: "arrow.triangle.branch"
        case .historyOrRecent: "clock"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}
