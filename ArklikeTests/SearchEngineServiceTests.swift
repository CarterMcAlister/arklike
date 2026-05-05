import XCTest
@testable import Arklike

final class SearchEngineServiceTests: XCTestCase {
    func testPercentEncodesSearchQuery() {
        let url = SearchEngineService.searchURL(for: "hello world & swift", template: "https://example.com/search?q=%@")
        XCTAssertEqual(url?.absoluteString, "https://example.com/search?q=hello%20world%20%26%20swift")
    }

    func testBraceTemplate() {
        let url = SearchEngineService.searchURL(for: "foo bar", template: "https://search.example/?query={query}")
        XCTAssertEqual(url?.absoluteString, "https://search.example/?query=foo%20bar")
    }

    func testTemplateWithoutPlaceholderAppendsQ() {
        let url = SearchEngineService.searchURL(for: "foo", template: "https://search.example/")
        XCTAssertEqual(url?.absoluteString, "https://search.example/?q=foo")
    }
}
