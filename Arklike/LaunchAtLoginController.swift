import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    static let shared = LaunchAtLoginController()

    @Published private(set) var isEnabled = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    private var refreshTask: Task<Void, Never>?

    private init() {
        refreshAsync()
    }

    func refresh() {
        refreshAsync()
    }

    func refreshAsync() {
        refreshTask?.cancel()
        isRefreshing = true
        refreshTask = Task.detached(priority: .utility) {
            let enabled = PerformanceTimer.measure("launch at login status") {
                SMAppService.mainApp.status == .enabled
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                Self.shared.isEnabled = enabled
                Self.shared.isRefreshing = false
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshAsync()
        } catch {
            refreshAsync()
            errorMessage = error.localizedDescription
        }
    }
}
