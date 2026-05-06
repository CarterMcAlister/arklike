import Foundation

@MainActor
final class CommandPanelWebSuggestionService {
    static let shared = CommandPanelWebSuggestionService()

    private var cache: [String: [String]] = [:]
    private var task: Task<Void, Never>?

    private init() {}

    func suggestions(for query: String, completion: @escaping @MainActor ([String]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        guard AppSettings.shared.webSearchSuggestionsEnabled, trimmed.count >= 2, !looksLikeURL(trimmed) else {
            completion([])
            return
        }
        if let cached = cache[trimmed.lowercased()] {
            completion(cached)
            return
        }

        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            let suggestions = await Self.fetchGoogleSuggestions(for: trimmed)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.cache[trimmed.lowercased()] = suggestions
                completion(suggestions)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func looksLikeURL(_ text: String) -> Bool {
        if case .url = URLParser().parse(text) { return true }
        return false
    }

    private static func fetchGoogleSuggestions(for query: String) async -> [String] {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "q", value: query)
        ]
        guard let url = components?.url else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            guard let array = try JSONSerialization.jsonObject(with: data) as? [Any],
                  array.count > 1,
                  let suggestions = array[1] as? [String] else { return [] }
            return Array(NSOrderedSet(array: suggestions).compactMap { $0 as? String }.prefix(6))
        } catch {
            Diagnostics.shared.log("Web search suggestions failed: \(error.localizedDescription)")
            return []
        }
    }
}
