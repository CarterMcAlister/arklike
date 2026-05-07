import Foundation

enum TrafficMatcherType: String, Codable, CaseIterable, Identifiable, Sendable {
    case domain
    case wildcard
    case substring
    case regex
    var id: String { rawValue }
}

struct TrafficRule: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var enabled = true
    var name: String
    var order: Int
    var matcherType: TrafficMatcherType
    var pattern: String
    var targetProfileNumber: Int
}

struct TrafficRuleMatch: Equatable, Sendable {
    let rule: TrafficRule
    let url: URL
}

struct TrafficRuleMatcher {
    func firstMatch(for url: URL, rules: [TrafficRule]) -> TrafficRuleMatch? {
        for rule in rules.filter(\.enabled).sorted(by: { $0.order < $1.order }) {
            if matches(url: url, rule: rule) {
                return TrafficRuleMatch(rule: rule, url: url)
            }
        }
        return nil
    }

    func validate(_ rule: TrafficRule) -> String? {
        guard !rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Pattern is required." }
        if rule.matcherType == .regex {
            do { _ = try NSRegularExpression(pattern: rule.pattern) } catch { return error.localizedDescription }
        }
        return nil
    }

    private func matches(url: URL, rule: TrafficRule) -> Bool {
        let pattern = rule.pattern.lowercased()
        let absolute = url.absoluteString.lowercased()
        let host = (url.host ?? "").lowercased()
        switch rule.matcherType {
        case .domain:
            return host == pattern || host.hasSuffix("." + pattern)
        case .wildcard:
            let regex = "^" + NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*") + "$"
            return absolute.range(of: regex, options: .regularExpression) != nil || host.range(of: regex, options: .regularExpression) != nil
        case .substring:
            return absolute.contains(pattern)
        case .regex:
            return absolute.range(of: rule.pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

@MainActor
final class TrafficRuleStore: ObservableObject {
    static let shared = TrafficRuleStore()
    @Published var rules: [TrafficRule] { didSet { save() } }
    private let key = "trafficRules.v1"
    private let defaults = UserDefaults.standard
    private var isPersistenceEnabled = true

    private init() {
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([TrafficRule].self, from: data) {
            rules = decoded.sorted { $0.order < $1.order }
        } else {
            rules = []
        }
    }

    func upsert(_ rule: TrafficRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule } else { rules.append(rule) }
        rules.sort { $0.order < $1.order }
    }

    func delete(_ rule: TrafficRule) { rules.removeAll { $0.id == rule.id } }

    private func save() {
        guard isPersistenceEnabled else { return }
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: key)
    }
}

#if DEBUG
extension TrafficRuleStore {
    func applyPreviewRules(_ rules: [TrafficRule]) {
        isPersistenceEnabled = false
        self.rules = rules.sorted { $0.order < $1.order }
        isPersistenceEnabled = true
    }
}
#endif
