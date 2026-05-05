import Foundation

enum URLParseResult: Equatable {
    case url(URL)
    case searchQuery(String)
}

struct URLParser {
    func parse(_ input: String) -> URLParseResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .searchQuery("") }

        if let explicit = parseExplicitURL(trimmed) {
            return .url(explicit)
        }

        if let implicit = parseImplicitURL(trimmed) {
            return .url(implicit)
        }

        return .searchQuery(trimmed)
    }

    private func parseExplicitURL(_ text: String) -> URL? {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              let url = components.url else { return nil }
        return url
    }

    private func parseImplicitURL(_ text: String) -> URL? {
        guard !text.contains(where: { $0.isWhitespace }) else { return nil }
        guard looksLikeHostOrLocalURL(text) else { return nil }
        return URLComponents(string: "https://\(text)")?.url
    }

    private func looksLikeHostOrLocalURL(_ text: String) -> Bool {
        let host = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        let hostWithoutPort = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? host
        if hostWithoutPort == "localhost" { return true }
        if isIPv4(hostWithoutPort) || isIPv6(hostWithoutPort) { return true }
        if hostWithoutPort.contains(".") && !hostWithoutPort.hasPrefix(".") && !hostWithoutPort.hasSuffix(".") {
            return hostWithoutPort.split(separator: ".").allSatisfy { !$0.isEmpty }
        }
        return false
    }

    private func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), value >= 0, value <= 255 else { return false }
            return String(value) == part || part == "0"
        }
    }

    private func isIPv6(_ host: String) -> Bool {
        host.contains(":") && host.allSatisfy { char in
            char.isHexDigit || char == ":" || char == "[" || char == "]"
        }
    }
}
