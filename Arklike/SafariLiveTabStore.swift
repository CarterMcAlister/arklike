import Combine
import Foundation

@MainActor
final class SafariLiveTabStore: ObservableObject {
    static let shared = SafariLiveTabStore()

    @Published private(set) var tabs: [SafariTabSnapshot] = []
    @Published private(set) var lastError: SafariAutomationError?

    private var refreshTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?
    private var safariSnapshotCancellable: AnyCancellable?
    private var lastRefreshAt: Date?

    private init() {}

    func reset() {
        refreshTask?.cancel()
        refreshTask = nil
        tabs = []
        lastError = nil
        lastRefreshAt = nil
    }

    func refresh() {
        refreshTask?.cancel()
        lastRefreshAt = Date()
        refreshTask = Task.detached(priority: .utility) { [weak self] in
            let result = SafariTabSnapshotLoader.listWindowsAndTabs()
            guard !Task.isCancelled else { return }
            await self?.applyRefreshResult(result)
        }
    }

    private func applyRefreshResult(_ result: Result<[SafariWindowSnapshot], SafariAutomationError>) {
        switch result {
        case .success(let windows):
            tabs = windows.flatMap(\.tabs)
            lastError = nil
        case .failure(let error):
            tabs = []
            lastError = error
        }
    }

    func refreshIfStale(maxAge: TimeInterval = 5) {
        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < maxAge { return }
        refreshIfSafariCanUseCommandPalette()
    }

    func startPeriodicRefresh(interval: TimeInterval = 5) {
        guard periodicRefreshTask == nil else { return }

        safariSnapshotCancellable = FrontmostSafariMonitor.shared.$snapshot.sink { [weak self] snapshot in
            guard snapshot.canOpenCommandPalette else { return }
            Task { @MainActor in
                self?.refreshIfStale(maxAge: 1)
            }
        }

        scheduleRefreshIfSafariCanUseCommandPalette(after: 0.2)

        periodicRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let nanoseconds = UInt64(max(interval, 1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.refreshIfSafariCanUseCommandPalette()
                }
            }
        }
    }

    func stopPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        refreshTask?.cancel()
        periodicRefreshTask = nil
        refreshTask = nil
        safariSnapshotCancellable = nil
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

    private func scheduleRefreshIfSafariCanUseCommandPalette(after delay: TimeInterval) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.refreshIfSafariCanUseCommandPalette() }
        }
    }

    private func refreshIfSafariCanUseCommandPalette() {
        guard FrontmostSafariMonitor.shared.snapshot.canOpenCommandPalette else { return }
        refresh()
    }

    func matchingTab(for url: URL) -> SafariTabSnapshot? {
        let normalized = CommandPanelRecentStore.normalized(url)
        return tabs.first { tab in
            guard let tabURL = tab.url else { return false }
            return CommandPanelRecentStore.normalized(tabURL) == normalized
        }
    }
}

#if DEBUG
extension SafariLiveTabStore {
    func applyPreviewTabs(_ tabs: [SafariTabSnapshot], error: SafariAutomationError? = nil) {
        refreshTask?.cancel()
        periodicRefreshTask?.cancel()
        refreshTask = nil
        periodicRefreshTask = nil
        safariSnapshotCancellable = nil
        self.tabs = tabs
        self.lastError = error
        lastRefreshAt = Date()
    }
}
#endif
