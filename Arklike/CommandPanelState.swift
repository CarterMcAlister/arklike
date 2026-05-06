import Foundation

@MainActor
final class CommandPanelState: ObservableObject {
    @Published var query: String = ""
    @Published var scopePickerQuery: String = ""
    @Published var activeScope: CommandPanelSearchScope?
    @Published var mode: CommandPanelMode = .search
    @Published var suggestions: [CommandPanelSuggestion] = []
    @Published var selectedIndex: Int = 0
    @Published var autocompleteText: String = ""
    @Published var autocompleteAccepted: Bool = false
    @Published var actionSourceSuggestion: CommandPanelSuggestion?

    var effectiveScope: CommandPanelSearchScope {
        activeScope ?? .all
    }

    var currentInputText: String {
        get { mode == .scopePicker ? scopePickerQuery : query }
        set {
            if mode == .scopePicker {
                scopePickerQuery = newValue
            } else {
                query = newValue
                autocompleteAccepted = false
            }
        }
    }

    func resetForOpen() {
        query = ""
        scopePickerQuery = ""
        activeScope = nil
        mode = .search
        suggestions = []
        selectedIndex = 0
        autocompleteText = ""
        autocompleteAccepted = false
        actionSourceSuggestion = nil
    }

    func setSuggestions(_ next: [CommandPanelSuggestion]) {
        suggestions = next
        if suggestions.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = min(max(selectedIndex, 0), suggestions.count - 1)
        }
    }

    func moveSelection(delta: Int) {
        guard !suggestions.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), suggestions.count - 1)
    }

    func select(index: Int) {
        guard suggestions.indices.contains(index) else { return }
        selectedIndex = index
    }

    var selectedSuggestion: CommandPanelSuggestion? {
        guard suggestions.indices.contains(selectedIndex) else { return nil }
        return suggestions[selectedIndex]
    }

    func beginScopePicker() {
        mode = .scopePicker
        scopePickerQuery = ""
        selectedIndex = 0
    }

    func endScopePicker() {
        mode = .search
        scopePickerQuery = ""
        selectedIndex = 0
    }

    func beginActions(for suggestion: CommandPanelSuggestion) {
        actionSourceSuggestion = suggestion
        mode = .actions
        selectedIndex = 0
    }

    func endActions() {
        mode = .search
        actionSourceSuggestion = nil
        selectedIndex = 0
    }

    func cycleScope() {
        let order = CommandPanelSearchScope.cyclingOrder
        if let activeScope, let index = order.firstIndex(of: activeScope) {
            self.activeScope = order[(index + 1) % order.count]
        } else {
            activeScope = .recents
        }
        mode = .search
        selectedIndex = 0
    }

    func clearScope() {
        activeScope = nil
        selectedIndex = 0
    }

    func acceptAutocomplete() {
        guard !autocompleteText.isEmpty else { return }
        query = autocompleteText
        autocompleteAccepted = true
        autocompleteText = ""
    }

    func rejectAutocomplete() {
        autocompleteText = ""
        autocompleteAccepted = false
    }
}
