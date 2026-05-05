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
            switch match.rule.openBehavior {
            case .newWindow, .reuseProfileWindow:
                _ = SafariProfileManager.shared.openURL(url, in: profile)
            case .newTab:
                _ = SafariProfileManager.shared.openURL(url, in: profile)
            }
        } else {
            Diagnostics.shared.lastRoutingDecision = "No match for \(url.absoluteString); opened directly in Safari"
            Diagnostics.shared.log(Diagnostics.shared.lastRoutingDecision)
            openDirectlyInSafari(url)
        }
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
