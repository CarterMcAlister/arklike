import XCTest
@testable import Arklike

final class URLParserTests: XCTestCase {
    let parser = URLParser()

    func testExplicitHTTPSURL() {
        XCTAssertEqual(parser.parse("https://example.com/path?q=1"), .url(URL(string: "https://example.com/path?q=1")!))
    }

    func testExplicitHTTPURL() {
        XCTAssertEqual(parser.parse("http://example.com"), .url(URL(string: "http://example.com")!))
    }

    func testBareDomainDefaultsToHTTPS() {
        XCTAssertEqual(parser.parse("example.com"), .url(URL(string: "https://example.com")!))
    }

    func testLocalhostWithPort() {
        XCTAssertEqual(parser.parse("localhost:3000/test"), .url(URL(string: "https://localhost:3000/test")!))
    }

    func testIPv4Address() {
        XCTAssertEqual(parser.parse("127.0.0.1:8080"), .url(URL(string: "https://127.0.0.1:8080")!))
    }

    func testSearchQueryWithSpaces() {
        XCTAssertEqual(parser.parse("hello world"), .searchQuery("hello world"))
    }

    func testSpecialCharacterSearchQuery() {
        XCTAssertEqual(parser.parse("swift URLComponents & spaces"), .searchQuery("swift URLComponents & spaces"))
    }
}
