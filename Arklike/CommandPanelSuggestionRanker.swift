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
            let lhsBucket = terminalSortBucket(lhs, activeScope: activeScope)
            let rhsBucket = terminalSortBucket(rhs, activeScope: activeScope)
            if lhsBucket != rhsBucket { return lhsBucket < rhsBucket }

            let lhsTotal = totalScore(lhs, query: trimmed)
            let rhsTotal = totalScore(rhs, query: trimmed)
            if lhsTotal != rhsTotal { return lhsTotal > rhsTotal }
            if lhs.basePriority != rhs.basePriority { return lhs.basePriority < rhs.basePriority }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func terminalSortBucket(_ suggestion: CommandPanelSuggestion, activeScope: CommandPanelSearchScope?) -> Int {
        guard activeScope == nil || activeScope == .all else { return 0 }
        switch suggestion.kind {
        case .profile:
            return 1
        case .settings:
            return 2
        default:
            return 0
        }
    }

    private func totalScore(_ suggestion: CommandPanelSuggestion, query: String) -> Double {
        Double(1_000 - suggestion.basePriority) + (query.isEmpty ? 0 : suggestion.fuzzyScore) + suggestion.usageScore
    }

    private func alwaysShow(_ suggestion: CommandPanelSuggestion) -> Bool {
        switch suggestion.kind {
        case .search, .url, .pasteAndGo, .permission:
            true
        default:
            false
        }
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
