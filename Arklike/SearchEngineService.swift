import Foundation

@MainActor
final class SearchEngineService: ObservableObject {
    static let shared = SearchEngineService()

    @Published var searchURLTemplate: String {
        didSet { defaults.set(searchURLTemplate, forKey: Self.templateKey) }
    }

    private let defaults: UserDefaults
    private static let templateKey = "searchEngine.template"
    nonisolated static let defaultTemplate = "https://www.google.com/search?q={query}"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.searchURLTemplate = defaults.string(forKey: Self.templateKey) ?? Self.defaultTemplate
    }

    func searchURL(for query: String) -> URL? {
        Self.searchURL(for: query, template: searchURLTemplate)
    }

    nonisolated static func searchURL(for query: String, template: String = defaultTemplate) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .arklikeSearchQueryAllowed) ?? query
        let string: String
        if template.contains("{query}") {
            string = template.replacingOccurrences(of: "{query}", with: encoded)
        } else {
            let separator = template.contains("?") ? "&" : "?"
            string = template + separator + "q=" + encoded
        }
        return URL(string: string)
    }
}

private extension CharacterSet {
    static let arklikeSearchQueryAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#%")
        return allowed
    }()
}
