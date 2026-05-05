import XCTest
@testable import Arklike

final class TrafficRuleMatcherTests: XCTestCase {
    func testDomainMatchesSubdomain() {
        let rule = TrafficRule(name: "Work", order: 0, matcherType: .domain, pattern: "example.com", targetProfileNumber: 1)
        XCTAssertNotNil(TrafficRuleMatcher().firstMatch(for: URL(string: "https://docs.example.com/a")!, rules: [rule]))
    }

    func testFirstMatchWins() {
        let one = TrafficRule(name: "One", order: 0, matcherType: .substring, pattern: "example", targetProfileNumber: 1)
        let two = TrafficRule(name: "Two", order: 1, matcherType: .substring, pattern: "example", targetProfileNumber: 2)
        XCTAssertEqual(TrafficRuleMatcher().firstMatch(for: URL(string: "https://example.com")!, rules: [two, one])?.rule.targetProfileNumber, 1)
    }

    func testWildcard() {
        let rule = TrafficRule(name: "Wildcard", order: 0, matcherType: .wildcard, pattern: "https://*.example.com/*", targetProfileNumber: 1)
        XCTAssertNotNil(TrafficRuleMatcher().firstMatch(for: URL(string: "https://a.example.com/path")!, rules: [rule]))
    }

    func testRegexValidation() {
        let invalid = TrafficRule(name: "Bad", order: 0, matcherType: .regex, pattern: "[", targetProfileNumber: 1)
        XCTAssertNotNil(TrafficRuleMatcher().validate(invalid))
    }
}
