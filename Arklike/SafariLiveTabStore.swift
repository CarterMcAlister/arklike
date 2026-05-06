import Foundation

@MainActor
final class SafariLiveTabStore: ObservableObject {
    static let shared = SafariLiveTabStore()

    @Published private(set) var tabs: [SafariTabSnapshot] = []
    @Published private(set) var lastError: SafariAutomationError?

    private var refreshTask: Task<Void, Never>?

    private init() {}

    func reset() {
        refreshTask?.cancel()
        refreshTask = nil
        tabs = []
        lastError = nil
    }

    func refresh() {
        switch SafariAutomation.shared.listWindowsAndTabs() {
        case .success(let windows):
            tabs = windows.flatMap(\.tabs)
            lastError = nil
        case .failure(let error):
            tabs = []
            lastError = error
        }
    }

    func scheduleRefresh(after delay: TimeInterval = 0.12) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.refresh() }
        }
    }

    func matchingTab(for url: URL) -> SafariTabSnapshot? {
        let normalized = CommandPanelRecentStore.normalized(url)
        return tabs.first { tab in
            guard let tabURL = tab.url else { return false }
            return CommandPanelRecentStore.normalized(tabURL) == normalized
        }
    }
}
