import Foundation

struct CommandPanelUsageRecord: Codable, Equatable, Sendable {
    var id: String
    var kind: String
    var count: Int
    var lastUsedAt: Date
    var lastQuery: String
}

@MainActor
final class CommandPanelUsageStore {
    static let shared = CommandPanelUsageStore()

    private let defaults: UserDefaults
    private let key = "commandPanelUsageHistory.v1"
    private(set) var records: [String: CommandPanelUsageRecord]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: CommandPanelUsageRecord].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    func record(_ suggestion: CommandPanelSuggestion, query: String) {
        guard !suggestion.id.hasPrefix("placeholder-") else { return }
        let now = Date()
        var record = records[suggestion.id] ?? CommandPanelUsageRecord(
            id: suggestion.id,
            kind: suggestion.kind.rawValue,
            count: 0,
            lastUsedAt: now,
            lastQuery: ""
        )
        record.count += 1
        record.lastUsedAt = now
        record.lastQuery = query
        records[suggestion.id] = record
        save()
    }

    func score(for id: String, query: String) -> Double {
        guard let record = records[id] else { return 0 }
        let countScore = min(Double(record.count) * 8, 80)
        let age = max(0, Date().timeIntervalSince(record.lastUsedAt))
        let recencyScore = max(0, 30 - age / 86_400)
        let queryScore = !query.isEmpty && record.lastQuery.localizedCaseInsensitiveContains(query) ? 15 : 0
        return countScore + recencyScore + Double(queryScore)
    }

    func usageRecord(for id: String) -> CommandPanelUsageRecord? {
        records[id]
    }

    var recordsSnapshot: [String: CommandPanelUsageRecord] { records }

    func topRecords(limit: Int = 12) -> [CommandPanelUsageRecord] {
        Self.topRecords(in: records, limit: limit)
    }

    nonisolated static func topRecords(in records: [String: CommandPanelUsageRecord], limit: Int = 12) -> [CommandPanelUsageRecord] {
        Array(records.values.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }.prefix(limit))
    }

    func clear() {
        records = [:]
        defaults.removeObject(forKey: key)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class CommandPanelSearchHistoryStore {
    static let shared = CommandPanelSearchHistoryStore()

    private let defaults: UserDefaults
    private let key = "commandPanelSearchQueryHistory.v1"
    private(set) var queries: [String]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        queries = defaults.stringArray(forKey: key) ?? []
    }

    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1 else { return }
        queries.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        queries.insert(trimmed, at: 0)
        queries = Array(queries.prefix(100))
        defaults.set(queries, forKey: key)
    }

    var queriesSnapshot: [String] { queries }

    func matches(for query: String, limit: Int = 5) -> [String] {
        Self.matches(query: query, in: queries, limit: limit)
    }

    nonisolated static func matches(query: String, in queries: [String], limit: Int = 5) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return Array(queries.filter { $0.localizedCaseInsensitiveContains(trimmed) }.prefix(limit))
    }

    func clear() {
        queries = []
        defaults.removeObject(forKey: key)
    }
}

#if DEBUG
extension CommandPanelSearchHistoryStore {
    func applyPreviewQueries(_ queries: [String]) {
        self.queries = queries
    }
}
#endif

struct CommandPanelRecentItem: Identifiable, Codable, Equatable, Sendable {
    var id: String { url.absoluteString }
    let url: URL
    var title: String?
    var source: String
    var lastAccessedAt: Date
    var openCount: Int
    var safariWindowId: Int?
    var safariProfileHint: String?
}

@MainActor
final class CommandPanelRecentStore: ObservableObject {
    static let shared = CommandPanelRecentStore()

    @Published private(set) var items: [CommandPanelRecentItem]

    private let defaults: UserDefaults
    private let key = "commandPanelRecentItems.v1"
    private let retention: TimeInterval = 30 * 24 * 60 * 60

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([CommandPanelRecentItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
        cleanup()
    }

    func record(url: URL, title: String? = nil, windowId: Int? = nil, profileHint: String? = nil) {
        cleanup()
        let now = Date()
        if let index = items.firstIndex(where: { Self.normalized($0.url) == Self.normalized(url) }) {
            var item = items.remove(at: index)
            item.title = title ?? item.title
            item.lastAccessedAt = now
            item.openCount += 1
            item.safariWindowId = windowId ?? item.safariWindowId
            item.safariProfileHint = profileHint ?? item.safariProfileHint
            items.insert(item, at: 0)
        } else {
            items.insert(CommandPanelRecentItem(
                url: url,
                title: title,
                source: "safari",
                lastAccessedAt: now,
                openCount: 1,
                safariWindowId: windowId,
                safariProfileHint: profileHint
            ), at: 0)
        }
        items = Array(items.prefix(250))
        save()
    }

    func remove(url: URL) {
        items.removeAll { Self.normalized($0.url) == Self.normalized(url) }
        save()
    }

    func clear() {
        items = []
        defaults.removeObject(forKey: key)
    }

    func cleanup() {
        let cutoff = Date().addingTimeInterval(-retention)
        let before = items
        items = items.filter { $0.lastAccessedAt >= cutoff }
        if before != items { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }

    nonisolated static func normalized(_ url: URL) -> String {
        var text = url.absoluteString.lowercased()
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

#if DEBUG
extension CommandPanelRecentStore {
    func applyPreviewItems(_ items: [CommandPanelRecentItem]) {
        self.items = items
    }
}
#endif

struct SafariBookmark: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let url: URL
    let path: String?
}

struct SafariBookmarkIndex: Codable, Equatable, Sendable {
    var bookmarks: [SafariBookmark]
    var sourceModificationDate: Date?
    var parsedAt: Date
    var stale: Bool
}

@MainActor
final class SafariBookmarkStore: ObservableObject {
    static let shared = SafariBookmarkStore()

    @Published private(set) var bookmarks: [SafariBookmark] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isUsingStaleCache = false

    private let defaults = UserDefaults.standard
    private let cacheKey = "safariBookmarkIndex.v1"
    private var cachedModificationDate: Date?
    private var periodicRefreshTask: Task<Void, Never>?
    private var deferredRefreshTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?

    private var bookmarkURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Safari")
            .appendingPathComponent("Bookmarks.plist")
    }

    func loadIfNeeded() {
        loadCache()
        refreshIfNeeded(force: false)
    }

    func startPeriodicRefresh(interval: TimeInterval = 60) {
        guard periodicRefreshTask == nil else { return }
        loadCache()
        scheduleRefreshIfNeeded(after: 1)

        periodicRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let nanoseconds = UInt64(max(interval, 10) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.refreshIfNeeded(force: false)
                }
            }
        }
    }

    func stopPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        deferredRefreshTask?.cancel()
        reloadTask?.cancel()
        periodicRefreshTask = nil
        deferredRefreshTask = nil
        reloadTask = nil
    }

    func scheduleRefreshIfNeeded(after delay: TimeInterval) {
        deferredRefreshTask?.cancel()
        deferredRefreshTask = Task { [weak self] in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.refreshIfNeeded(force: false)
            }
        }
    }

    func refreshIfNeeded(force: Bool = false) {
        let currentModificationDate = modificationDate()
        guard force || bookmarks.isEmpty || currentModificationDate != cachedModificationDate else { return }
        reload(force: force)
    }

    func reload(force: Bool = true) {
        reloadTask?.cancel()
        let bookmarkURL = bookmarkURL
        reloadTask = Task.detached(priority: .utility) { [weak self] in
            let result = SafariBookmarkLoader.load(from: bookmarkURL)
            guard !Task.isCancelled else { return }
            await self?.applyLoadResult(result)
        }
    }

    private func applyLoadResult(_ result: SafariBookmarkLoadResult) {
        switch result {
        case .success(let index):
            bookmarks = index.bookmarks
            cachedModificationDate = index.sourceModificationDate
            isUsingStaleCache = false
            lastError = index.bookmarks.isEmpty ? "No Safari bookmarks were found." : nil
            saveCache(index)
        case .failure(let message):
            handleRefreshFailure(message)
        }
    }

    private func handleRefreshFailure(_ message: String) {
        if bookmarks.isEmpty { loadCache() }
        if bookmarks.isEmpty {
            lastError = message
            isUsingStaleCache = false
        } else {
            lastError = message
            isUsingStaleCache = true
        }
    }

    private func loadCache() {
        guard bookmarks.isEmpty,
              let data = defaults.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(SafariBookmarkIndex.self, from: data) else { return }
        bookmarks = cached.bookmarks
        cachedModificationDate = cached.sourceModificationDate
        isUsingStaleCache = cached.stale
    }

    private func saveCache(_ index: SafariBookmarkIndex) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: bookmarkURL.path)[.modificationDate]) as? Date
    }

    static func parseBookmarkNode(_ node: [String: Any], path: [String]) -> [SafariBookmark] {
        let type = node["WebBookmarkType"] as? String
        if type == "WebBookmarkTypeLeaf",
           let urlString = node["URLString"] as? String,
           let url = URL(string: urlString) {
            let uriDictionary = node["URIDictionary"] as? [String: Any]
            let title = (uriDictionary?["title"] as? String)
                ?? (node["Title"] as? String)
                ?? url.host
                ?? url.absoluteString
            let pathText = path.isEmpty ? nil : path.joined(separator: " › ")
            return [SafariBookmark(
                id: "bookmark-\((pathText ?? "root") + "-" + title + "-" + url.absoluteString)".stableCommandPanelID,
                title: title,
                url: url,
                path: pathText
            )]
        }

        var nextPath = path
        if let title = node["Title"] as? String, !title.isEmpty, title != "BookmarksBar", title != "BookmarksMenu" {
            nextPath.append(title)
        }
        let children = node["Children"] as? [[String: Any]] ?? []
        return children.flatMap { parseBookmarkNode($0, path: nextPath) }
    }

    private static func deduplicated(_ bookmarks: [SafariBookmark]) -> [SafariBookmark] {
        var seen: Set<String> = []
        var result: [SafariBookmark] = []
        for bookmark in bookmarks {
            let key = CommandPanelRecentStore.normalized(bookmark.url) + "|" + (bookmark.path ?? "")
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(bookmark)
        }
        return result
    }
}

private enum SafariBookmarkLoadResult {
    case success(SafariBookmarkIndex)
    case failure(String)
}

private enum SafariBookmarkLoader {
    static func load(from bookmarkURL: URL) -> SafariBookmarkLoadResult {
        do {
            let modificationDate = (try? FileManager.default.attributesOfItem(atPath: bookmarkURL.path)[.modificationDate]) as? Date
            let data = try Data(contentsOf: bookmarkURL)
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let root = object as? [String: Any] else {
                return .failure("Safari bookmarks could not be parsed.")
            }
            let parsed = deduplicated(parseBookmarkNode(root, path: []))
            return .success(SafariBookmarkIndex(bookmarks: parsed, sourceModificationDate: modificationDate, parsedAt: Date(), stale: false))
        } catch {
            return .failure("Safari bookmarks are not accessible. Grant Full Disk Access to Arklike in System Settings → Privacy & Security → Full Disk Access, then refresh bookmarks.")
        }
    }

    private static func parseBookmarkNode(_ node: [String: Any], path: [String]) -> [SafariBookmark] {
        let type = node["WebBookmarkType"] as? String
        if type == "WebBookmarkTypeLeaf",
           let urlString = node["URLString"] as? String,
           let url = URL(string: urlString) {
            let uriDictionary = node["URIDictionary"] as? [String: Any]
            let title = (uriDictionary?["title"] as? String)
                ?? (node["Title"] as? String)
                ?? url.host
                ?? url.absoluteString
            let pathText = path.isEmpty ? nil : path.joined(separator: " › ")
            return [SafariBookmark(
                id: "bookmark-\((pathText ?? "root") + "-" + title + "-" + url.absoluteString)".stableCommandPanelID,
                title: title,
                url: url,
                path: pathText
            )]
        }

        var nextPath = path
        if let title = node["Title"] as? String, !title.isEmpty, title != "BookmarksBar", title != "BookmarksMenu" {
            nextPath.append(title)
        }
        let children = node["Children"] as? [[String: Any]] ?? []
        return children.flatMap { parseBookmarkNode($0, path: nextPath) }
    }

    private static func deduplicated(_ bookmarks: [SafariBookmark]) -> [SafariBookmark] {
        var seen: Set<String> = []
        var result: [SafariBookmark] = []
        for bookmark in bookmarks {
            let key = normalized(bookmark.url) + "|" + (bookmark.path ?? "")
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(bookmark)
        }
        return result
    }

    private static func normalized(_ url: URL) -> String {
        var text = url.absoluteString.lowercased()
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

extension String {
    var stableCommandPanelID: String {
        unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) {
                return String(scalar).lowercased()
            }
            return "-"
        }
        .joined()
        .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
    }
}

#if DEBUG
extension SafariBookmarkStore {
    func applyPreviewBookmarks(_ bookmarks: [SafariBookmark], error: String? = nil, isStale: Bool = false) {
        reloadTask?.cancel()
        deferredRefreshTask?.cancel()
        periodicRefreshTask?.cancel()
        reloadTask = nil
        deferredRefreshTask = nil
        periodicRefreshTask = nil
        self.bookmarks = bookmarks
        lastError = error
        isUsingStaleCache = isStale
    }
}
#endif
