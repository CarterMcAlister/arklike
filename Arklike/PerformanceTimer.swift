import Foundation
import os

enum PerformanceTimer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.arklike.app",
        category: "Performance"
    )

    static func measure<T>(_ label: String, operation: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        let result = try operation()
        logIfSlow(label: label, start: start)
        return result
    }

    static func measureAsync<T>(_ label: String, operation: () async throws -> T) async rethrows -> T {
        let start = ContinuousClock.now
        let result = try await operation()
        logIfSlow(label: label, start: start)
        return result
    }

    private static func logIfSlow(label: String, start: ContinuousClock.Instant) {
        let duration = start.duration(to: .now)
        let milliseconds = Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        if milliseconds >= 25 {
            logger.info("\(label, privacy: .public) took \(milliseconds, privacy: .public)ms")
        }
    }
}
