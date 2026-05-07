import Foundation
import os

@MainActor
enum MainThreadStallDetector {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.arklike.app",
        category: "MainThreadStall"
    )
    private static var task: Task<Void, Never>?

    static func start() {
#if DEBUG
        guard task == nil else { return }
        task = Task.detached(priority: .background) {
            while !Task.isCancelled {
                let start = ContinuousClock.now
                await MainActor.run {}
                let duration = start.duration(to: .now)
                let milliseconds = Double(duration.components.seconds) * 1_000
                    + Double(duration.components.attoseconds) / 1_000_000_000_000_000
                if milliseconds >= 200 {
                    let message = "Main actor stalled for \(String(format: "%.1f", milliseconds))ms"
                    logger.warning("\(message, privacy: .public)")
                    await MainActor.run {
                        Diagnostics.shared.recordSlowOperation(message)
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
#endif
    }

    static func stop() {
        task?.cancel()
        task = nil
    }
}
