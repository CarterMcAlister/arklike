import AppKit
import Foundation

@MainActor
final class DefaultBrowserRouter {
    static let shared = DefaultBrowserRouter()

    private var internallyOpeningURLs = Set<URL>()

    private init() {}

    func routeIncomingURL(_ url: URL) {
        guard !internallyOpeningURLs.contains(url) else { return }
        let matcher = TrafficRuleMatcher()
        if let match = matcher.firstMatch(for: url, rules: TrafficRuleStore.shared.rules),
           let profile = ProfileStore.shared.profile(number: match.rule.targetProfileNumber) {
            Diagnostics.shared.lastRoutingDecision = "Matched \(match.rule.name) for \(url.absoluteString) → profile \(match.rule.targetProfileNumber)"
            Diagnostics.shared.log(Diagnostics.shared.lastRoutingDecision)
            Task { @MainActor in
                _ = await SafariProfileManager.shared.openURLAsync(url, in: profile)
            }
        } else {
            if scheduleOpenInLastActiveSafariWindow(url) {
                return
            }
            Diagnostics.shared.lastRoutingDecision = "No match for \(url.absoluteString); opened directly in Safari"
            Diagnostics.shared.log(Diagnostics.shared.lastRoutingDecision)
            openDirectlyInSafari(url)
        }
    }

    private func scheduleOpenInLastActiveSafariWindow(_ url: URL) -> Bool {
        guard let lastActiveWindow = FrontmostSafariMonitor.shared.lastActiveWindowForSafariAction() else {
            return false
        }
        Task.detached(priority: .userInitiated) {
            let result = SafariAutomation.shared.openURLInNewTab(url, preferredWindowId: lastActiveWindow.safariWindowId)
            await MainActor.run {
                switch result {
                case .success:
                    let windowDescription = lastActiveWindow.safariWindowId.map { "window \($0)" } ?? "the last active Safari window"
                    Diagnostics.shared.lastRoutingDecision = "No match for \(url.absoluteString); opened in \(windowDescription)"
                    Diagnostics.shared.log(Diagnostics.shared.lastRoutingDecision)
                case .failure(let error):
                    Diagnostics.shared.log("Could not open unmatched URL in last active Safari window: \(error.localizedDescription)")
                    self.openDirectlyInSafari(url)
                }
            }
        }
        return true
    }

    func openDirectlyInSafari(_ url: URL) {
        internallyOpeningURLs.insert(url)
        defer { internallyOpeningURLs.remove(url) }
        let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: FrontmostSafariMonitor.safariBundleIdentifier)
        if let safariURL {
            NSWorkspace.shared.open([url], withApplicationAt: safariURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
