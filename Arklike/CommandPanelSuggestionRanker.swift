import Foundation

struct CommandPanelFuzzyMatch {
    let score: Double
    let ranges: [Range<String.Index>]
}

@MainActor
struct CommandPanelSuggestionRanker {
    func rank(
        _ suggestions: [CommandPanelSuggestion],
        query: String,
        activeScope: CommandPanelSearchScope?,
        usageStore: CommandPanelUsageStore
    ) -> [CommandPanelSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryProfile = CommandPanelQueryProfile(query: trimmed)
        return suggestions.compactMap { suggestion in
            if let activeScope, activeScope != .all, suggestion.scope != activeScope, suggestion.kind != .scope, suggestion.kind != .action, suggestion.kind != .permission {
                return nil
            }

            var ranked = suggestion
            ranked.usageScore = usageStore.score(for: suggestion.id, query: trimmed)
            if let record = usageStore.usageRecord(for: suggestion.id) {
                ranked.lastUsedAt = record.lastUsedAt
            }

            if trimmed.isEmpty {
                ranked.fuzzyScore = 0
                ranked.titleMatchRanges = []
                ranked.subtitleMatchRanges = []
                return ranked
            }

            let titleMatch = Self.fuzzyMatch(query: trimmed, candidate: suggestion.title)
            let subtitleMatch = Self.fuzzyMatch(query: trimmed, candidate: suggestion.subtitle)
            let urlMatch = suggestion.representedURL.map { Self.fuzzyMatch(query: trimmed, candidate: $0.absoluteString) }
            let urlBonus = suggestion.representedURL?.host?.localizedCaseInsensitiveContains(trimmed) == true ? 80.0 : 0.0
            let bestScore = max(titleMatch.score + 70, subtitleMatch.score, (urlMatch?.score ?? 0) + urlBonus)
            if bestScore <= 0, !alwaysShow(suggestion) { return nil }
            ranked.fuzzyScore = bestScore
            ranked.titleMatchRanges = titleMatch.ranges
            ranked.subtitleMatchRanges = subtitleMatch.ranges
            ranked.matchRanges = titleMatch.ranges
            return ranked
        }
        .sorted { lhs, rhs in
            let lhsBucket = terminalSortBucket(lhs, activeScope: activeScope, queryProfile: queryProfile)
            let rhsBucket = terminalSortBucket(rhs, activeScope: activeScope, queryProfile: queryProfile)
            if lhsBucket != rhsBucket { return lhsBucket < rhsBucket }

            let lhsTotal = totalScore(lhs, queryProfile: queryProfile)
            let rhsTotal = totalScore(rhs, queryProfile: queryProfile)
            if lhsTotal != rhsTotal { return lhsTotal > rhsTotal }
            if lhs.basePriority != rhs.basePriority { return lhs.basePriority < rhs.basePriority }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func terminalSortBucket(
        _ suggestion: CommandPanelSuggestion,
        activeScope: CommandPanelSearchScope?,
        queryProfile: CommandPanelQueryProfile
    ) -> Int {
        guard activeScope == nil || activeScope == .all else { return 0 }
        guard queryProfile.shouldDeemphasizeCommandRows else { return 0 }
        switch suggestion.kind {
        case .profile:
            return 1
        case .settings:
            return 2
        default:
            return 0
        }
    }

    private func totalScore(_ suggestion: CommandPanelSuggestion, queryProfile: CommandPanelQueryProfile) -> Double {
        if queryProfile.isEmpty {
            return emptyQueryScore(suggestion)
        }

        return suggestion.fuzzyScore
            + baseUsefulnessScore(suggestion)
            + intentScore(suggestion, queryProfile: queryProfile)
            + knownDestinationMatchBoost(suggestion, queryProfile: queryProfile)
            + suggestion.usageScore
            + freshnessScore(suggestion)
            - frictionPenalty(suggestion, queryProfile: queryProfile)
    }

    private func emptyQueryScore(_ suggestion: CommandPanelSuggestion) -> Double {
        var score: Double
        switch suggestion.kind {
        case .pasteAndGo:
            score = 4_000
        case .safariTab:
            score = 1_100
        case .historyOrRecent:
            score = 950
        case .bookmark:
            score = 800
        case .searchHistory:
            score = 720
        case .siteShortcut:
            score = 650
        case .profile:
            score = 450
        case .trafficRule:
            score = 430
        case .settings:
            score = 350
        case .permission:
            score = 120
        case .search:
            score = 0
        case .url, .webSuggestion, .exactCommand, .scope, .action:
            score = 250
        }

        if suggestion.basePriority <= 2 || suggestion.subtitle.localizedCaseInsensitiveContains("Frequently used") {
            score += 600
        }
        if suggestion.kind == .safariTab, suggestion.subtitle.localizedCaseInsensitiveContains("Active") {
            score += 220
        }

        score += suggestion.usageScore
        score += freshnessScore(suggestion)
        score -= frictionPenalty(suggestion, queryProfile: .empty)
        score -= Double(max(suggestion.basePriority, 0)) * 0.25
        return score
    }

    private func baseUsefulnessScore(_ suggestion: CommandPanelSuggestion) -> Double {
        switch suggestion.kind {
        case .pasteAndGo:
            return 520
        case .url:
            return 260
        case .safariTab:
            return 240
        case .bookmark:
            return 220
        case .historyOrRecent:
            return 190
        case .searchHistory:
            return 170
        case .webSuggestion:
            return 150
        case .siteShortcut:
            return suggestion.representedURL == nil ? 120 : 260
        case .profile, .trafficRule, .settings:
            return 120
        case .search:
            return 80
        case .permission:
            return -80
        case .exactCommand, .scope, .action:
            return 160
        }
    }

    private func intentScore(_ suggestion: CommandPanelSuggestion, queryProfile: CommandPanelQueryProfile) -> Double {
        if let parsedURL = queryProfile.parsedURL {
            return urlIntentScore(suggestion, parsedURL: parsedURL)
        }
        if queryProfile.shortcutKeyword != nil {
            switch suggestion.kind {
            case .siteShortcut:
                return suggestion.representedURL == nil ? 420 : 1_200
            case .search:
                return -250
            case .webSuggestion, .searchHistory:
                return -150
            default:
                return 0
            }
        }

        var score = 0.0
        if queryProfile.wantsSettings {
            score += suggestion.kind == .settings ? 950 : 0
            if suggestion.kind == .search { score -= 160 }
        }
        if queryProfile.wantsProfile {
            score += suggestion.kind == .profile ? 950 : 0
            if suggestion.kind == .search { score -= 140 }
        }
        if queryProfile.wantsTraffic {
            score += suggestion.kind == .trafficRule ? 950 : 0
            if suggestion.kind == .search { score -= 140 }
        }
        if queryProfile.wantsBookmarks {
            score += suggestion.kind == .bookmark ? 700 : 0
            if suggestion.kind == .search { score -= 100 }
        }
        if queryProfile.wantsTabs {
            score += suggestion.kind == .safariTab ? 700 : 0
            if suggestion.kind == .search { score -= 100 }
        }

        if score != 0 { return score }

        switch suggestion.kind {
        case .searchHistory:
            return 180
        case .webSuggestion:
            return 160
        case .search:
            return queryProfile.containsWhitespace ? 120 : 40
        case .safariTab, .bookmark, .historyOrRecent, .url:
            return 110
        case .siteShortcut:
            return 70
        default:
            return 0
        }
    }

    private func urlIntentScore(_ suggestion: CommandPanelSuggestion, parsedURL: URL) -> Double {
        let relationship = urlRelationship(suggestion.representedURL, parsedURL)
        switch suggestion.kind {
        case .safariTab:
            return relationship.exact ? 1_250 : relationship.sameHost ? 700 : 0
        case .bookmark, .historyOrRecent:
            return relationship.exact ? 1_120 : relationship.sameHost ? 640 : 0
        case .trafficRule:
            return relationship.exact ? 1_050 : relationship.sameHost ? 420 : 0
        case .url:
            return relationship.exact ? 760 : relationship.sameHost ? 560 : 0
        case .pasteAndGo:
            return relationship.exact ? 720 : relationship.sameHost ? 500 : 0
        case .search, .webSuggestion, .searchHistory:
            return -350
        case .settings, .profile:
            return -200
        default:
            return 0
        }
    }

    private func knownDestinationMatchBoost(_ suggestion: CommandPanelSuggestion, queryProfile: CommandPanelQueryProfile) -> Double {
        switch suggestion.kind {
        case .safariTab, .bookmark, .historyOrRecent, .url, .pasteAndGo:
            break
        default:
            return 0
        }

        let query = queryProfile.trimmed.lowercased()
        guard !query.isEmpty else { return 0 }
        let title = suggestion.title.lowercased()
        let subtitle = suggestion.subtitle.lowercased()
        let urlText = suggestion.representedURL?.absoluteString.lowercased() ?? ""
        if title == query {
            return 450
        }
        if let representedURL = suggestion.representedURL,
           CommandPanelRecentStore.normalized(representedURL) == query {
            return 450
        }
        if title.hasPrefix(query) || urlText.hasPrefix(query) {
            return 300
        }
        if title.contains(query) || subtitle.contains(query) || urlText.contains(query) {
            return 130
        }
        return 0
    }

    private func freshnessScore(_ suggestion: CommandPanelSuggestion) -> Double {
        guard let lastUsedAt = suggestion.lastUsedAt else { return 0 }
        let age = max(0, Date().timeIntervalSince(lastUsedAt))
        return max(0, 45 - age / 14_400)
    }

    private func frictionPenalty(_ suggestion: CommandPanelSuggestion, queryProfile: CommandPanelQueryProfile) -> Double {
        var penalty = 0.0
        if suggestion.kind == .permission {
            penalty += queryProfile.isEmpty ? 80 : 40
        }
        if suggestion.id.hasPrefix("placeholder-") {
            penalty += 600
        }
        if case .noop = suggestion.primaryAction {
            penalty += queryProfile.isEmpty ? 260 : 150
        }
        return penalty
    }

    private func alwaysShow(_ suggestion: CommandPanelSuggestion) -> Bool {
        switch suggestion.kind {
        case .search, .url, .pasteAndGo, .permission:
            true
        default:
            false
        }
    }

    private func urlRelationship(_ candidate: URL?, _ queryURL: URL) -> (exact: Bool, sameHost: Bool) {
        guard let candidate else { return (false, false) }
        let exact = CommandPanelRecentStore.normalized(candidate) == CommandPanelRecentStore.normalized(queryURL)
        let sameHost = candidate.host?.caseInsensitiveCompare(queryURL.host ?? "") == .orderedSame
        return (exact, sameHost)
    }

    static func fuzzyScore(query: String, candidate: String) -> Double {
        fuzzyMatch(query: query, candidate: candidate).score
    }

    static func fuzzyMatch(query: String, candidate: String) -> CommandPanelFuzzyMatch {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty, !c.isEmpty else { return CommandPanelFuzzyMatch(score: 0, ranges: []) }

        if c == q { return CommandPanelFuzzyMatch(score: 700, ranges: [candidate.startIndex..<candidate.endIndex]) }
        if c.hasPrefix(q), let range = candidate.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            return CommandPanelFuzzyMatch(score: 640 - Double(max(0, c.count - q.count)) * 0.05, ranges: [range])
        }
        if let range = candidate.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            let boundaryBonus = isWordBoundary(candidate, range.lowerBound) ? 120.0 : 0
            let offset = Double(candidate.distance(from: candidate.startIndex, to: range.lowerBound))
            return CommandPanelFuzzyMatch(score: 500 + boundaryBonus - offset, ranges: [range])
        }

        let queryTokens = q.split(separator: " ").map(String.init)
        if queryTokens.count > 1 {
            var ranges: [Range<String.Index>] = []
            var score = 0.0
            for token in queryTokens {
                if let range = candidate.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) {
                    ranges.append(range)
                    score += isWordBoundary(candidate, range.lowerBound) ? 140 : 100
                } else if tokenMatch(token, candidate: c) {
                    score += 70
                } else {
                    score -= 80
                }
            }
            if score > 0 { return CommandPanelFuzzyMatch(score: score, ranges: ranges) }
        }

        if acronym(of: c).hasPrefix(q) {
            return CommandPanelFuzzyMatch(score: 460, ranges: acronymRanges(in: candidate))
        }

        let sequential = sequentialMatch(query: q, candidate: candidate)
        let distance = damerauLevenshtein(q, c)
        let typoScore = distance <= max(2, q.count / 3) ? 340 - Double(distance * 35) : 0
        if typoScore > sequential.score { return CommandPanelFuzzyMatch(score: typoScore, ranges: []) }
        return sequential
    }

    private static func tokenMatch(_ token: String, candidate: String) -> Bool {
        candidate.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { part in
            part.hasPrefix(token) || damerauLevenshtein(token, String(part)) <= 1
        }
    }

    private static func sequentialMatch(query: String, candidate: String) -> CommandPanelFuzzyMatch {
        var score = 0.0
        var ranges: [Range<String.Index>] = []
        var searchStart = candidate.startIndex
        var lastMatch: String.Index?
        for char in query {
            guard let index = candidate[searchStart...].firstIndex(where: { String($0).lowercased() == String(char) }) else {
                return CommandPanelFuzzyMatch(score: 0, ranges: [])
            }
            score += 22
            if let lastMatch, candidate.index(after: lastMatch) == index { score += 16 } else { score -= 4 }
            ranges.append(index..<candidate.index(after: index))
            lastMatch = index
            searchStart = candidate.index(after: index)
        }
        return CommandPanelFuzzyMatch(score: max(score, 0), ranges: ranges)
    }

    private static func isWordBoundary(_ text: String, _ index: String.Index) -> Bool {
        if index == text.startIndex { return true }
        let previous = text[text.index(before: index)]
        return !previous.isLetter && !previous.isNumber
    }

    private static func acronym(of text: String) -> String {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap(\.first)
            .map { String($0) }
            .joined()
            .lowercased()
    }

    private static func acronymRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var atBoundary = true
        for index in text.indices {
            let char = text[index]
            if char.isLetter || char.isNumber {
                if atBoundary { ranges.append(index..<text.index(after: index)) }
                atBoundary = false
            } else {
                atBoundary = true
            }
        }
        return ranges
    }

    private static func damerauLevenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var matrix = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, matrix[i - 2][j - 2] + 1)
                }
                matrix[i][j] = value
            }
        }
        return matrix[a.count][b.count]
    }
}

private struct CommandPanelQueryProfile {
    static let empty = CommandPanelQueryProfile(query: "")

    let trimmed: String
    let parsedURL: URL?
    let shortcutKeyword: String?
    let wantsSettings: Bool
    let wantsProfile: Bool
    let wantsTraffic: Bool
    let wantsBookmarks: Bool
    let wantsTabs: Bool
    let containsWhitespace: Bool

    var isEmpty: Bool { trimmed.isEmpty }

    var shouldDeemphasizeCommandRows: Bool {
        isEmpty || (!wantsSettings && !wantsProfile && !wantsTraffic && !wantsBookmarks && !wantsTabs && parsedURL == nil && shortcutKeyword == nil)
    }

    init(query: String) {
        trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        containsWhitespace = trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        if case .url(let url) = URLParser().parse(trimmed) {
            parsedURL = url
        } else {
            parsedURL = nil
        }

        let lowercased = trimmed.lowercased()
        shortcutKeyword = Self.shortcutKeyword(in: lowercased)
        wantsSettings = Self.containsAny(lowercased, ["setting", "settings", "preference", "preferences", "pref", "config", "toggle", "clear", "refresh", "shortcut", "permission", "permissions"])
        wantsProfile = Self.containsAny(lowercased, ["profile", "profiles", "prof"]) || lowercased.range(of: #"^p\d+$"#, options: .regularExpression) != nil
        wantsTraffic = Self.containsAny(lowercased, ["traffic", "rule", "rules", "route", "routing"])
        wantsBookmarks = Self.containsAny(lowercased, ["bookmark", "bookmarks", "favorite", "favorites", "saved"])
        wantsTabs = Self.containsAny(lowercased, ["tab", "tabs", "safari"])
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func shortcutKeyword(in query: String) -> String? {
        let shortcuts = ["g", "google", "ddg", "duckduckgo", "gh", "github", "yt", "youtube"]
        let parts = query.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first?.trimmingCharacters(in: CharacterSet(charactersIn: ":")), shortcuts.contains(first) else {
            return nil
        }
        if parts.count > 1 || query.hasPrefix(first + ":") || query == first {
            return first
        }
        return nil
    }
}
