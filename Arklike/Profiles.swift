import Combine
import Foundation

struct Profile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var displayName: String
    var assignedNumber: Int
    var safariMenuTitle: String?
    var colorName: String?
    var iconName: String?

    var effectiveMenuName: String { safariMenuTitle?.isEmpty == false ? safariMenuTitle! : displayName }
}

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var profiles: [Profile] {
        didSet { save() }
    }

    @Published private(set) var lastDiscoveryMessage: String = "No named Safari profiles have been detected yet."

    private let defaults = UserDefaults.standard
    private let key = "profiles.v3.namedOnlyAutoDiscovered"
    private var isPersistenceEnabled = true
    private var periodicRefreshTask: Task<Void, Never>?
    private var deferredRefreshTask: Task<Void, Never>?
    private var safariSnapshotCancellable: AnyCancellable?
    private var lastRefreshAt: Date?

    private init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
            profiles = Self.normalized(decoded)
        } else {
            profiles = []
        }
    }

    func profile(number: Int) -> Profile? {
        profiles.first { $0.assignedNumber == number }
    }

    func refreshFromSafari() -> Result<[Profile], SafariAutomationError> {
        lastRefreshAt = Date()
        switch SafariProfileManager.shared.discoverProfileNames() {
        case .success(let names):
            replaceWithDiscoveredNames(names)
            if names.isEmpty {
                lastDiscoveryMessage = "No named Safari profiles were found. Arklike only maps named profiles, not Safari’s default profile."
            } else {
                lastDiscoveryMessage = "Mapped Ctrl+1... to: \(profiles.map { "Ctrl+\($0.assignedNumber)=\($0.displayName)" }.joined(separator: ", "))."
            }
            return .success(profiles)
        case .failure(let error):
            profiles = Self.normalized(profiles)
            lastDiscoveryMessage = "Could not refresh Safari profile names: \(error.localizedDescription)"
            return .failure(error)
        }
    }

    func ensureAutoDiscovered() {
        _ = refreshFromSafari()
    }

    func startPeriodicRefresh(interval: TimeInterval = 300) {
        guard periodicRefreshTask == nil else { return }

        safariSnapshotCancellable = FrontmostSafariMonitor.shared.$snapshot.sink { [weak self] snapshot in
            guard snapshot.isSafariFrontmost else { return }
            Task { @MainActor in
                self?.scheduleRefreshIfStale(after: 1, maxAge: interval)
            }
        }

        scheduleRefreshIfStale(after: 1, maxAge: interval)

        periodicRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let nanoseconds = UInt64(max(interval, 60) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.refreshIfStale(maxAge: interval)
                }
            }
        }
    }

    func stopPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        deferredRefreshTask?.cancel()
        periodicRefreshTask = nil
        deferredRefreshTask = nil
        safariSnapshotCancellable = nil
    }

    func scheduleRefreshIfStale(after delay: TimeInterval, maxAge: TimeInterval = 300) {
        deferredRefreshTask?.cancel()
        deferredRefreshTask = Task { [weak self] in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.refreshIfStale(maxAge: maxAge)
            }
        }
    }

    private func refreshIfStale(maxAge: TimeInterval) {
        guard FrontmostSafariMonitor.shared.snapshot.isSafariFrontmost else { return }
        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < maxAge { return }
        _ = refreshFromSafari()
    }

    func replaceWithDiscoveredNames(_ names: [String]) {
        let uniqueNames = Array(NSOrderedSet(array: names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })) as? [String] ?? names
        let next = uniqueNames.prefix(9).enumerated().map { index, name in
            Profile(
                displayName: name,
                assignedNumber: index + 1,
                safariMenuTitle: name,
                colorName: nil,
                iconName: "person.crop.circle"
            )
        }
        profiles = Self.normalized(next)
    }

    private func save() {
        guard isPersistenceEnabled else { return }
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: key)
    }

    private static func normalized(_ profiles: [Profile]) -> [Profile] {
        profiles
            .filter { !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(9)
            .enumerated()
            .map { offset, profile in
                var profile = profile
                profile.assignedNumber = offset + 1
                if profile.safariMenuTitle?.isEmpty != false {
                    profile.safariMenuTitle = profile.displayName
                }
                return profile
            }
    }
}

#if DEBUG
extension ProfileStore {
    func applyPreviewProfiles(_ profiles: [Profile], message: String) {
        periodicRefreshTask?.cancel()
        deferredRefreshTask?.cancel()
        periodicRefreshTask = nil
        deferredRefreshTask = nil
        safariSnapshotCancellable = nil
        isPersistenceEnabled = false
        self.profiles = Self.normalized(profiles)
        isPersistenceEnabled = true
        lastDiscoveryMessage = message
    }
}
#endif
