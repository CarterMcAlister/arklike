import SwiftUI

struct ProfilesSettingsView: View {
    @StateObject private var store = ProfileStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Safari Profiles")
                    .font(.headline)
                Spacer()
                Button("Refresh from Safari") { _ = store.refreshFromSafari() }
            }
            Text("Arklike detects named Safari profile menu items automatically. Safari’s default profile is intentionally not mapped. Ctrl+1 maps to the first named profile Safari exposes, Ctrl+2 to the next, and so on. If a matching profile window is already open, Arklike switches to it instead of opening a duplicate.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(store.lastDiscoveryMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            if store.profiles.isEmpty {
                Text("No named Safari profiles detected. Create profiles in Safari Settings, then click Refresh from Safari.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            ForEach(store.profiles) { profile in
                HStack(spacing: 12) {
                    Text("Ctrl+\(profile.assignedNumber)")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 64, alignment: .leading)
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(.body)
                        Text("Safari menu: File > New \(profile.effectiveMenuName) Window")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(8)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear {
#if DEBUG
            guard !PreviewFixtures.isRunningForPreviews else { return }
#endif
            if store.profiles.isEmpty {
                _ = store.refreshFromSafari()
            }
        }
    }
}

#if DEBUG
#Preview("Profiles Settings") {
    let _ = PreviewFixtures.configureAppState()
    ProfilesSettingsView()
        .padding(20)
        .frame(width: 680)
}
#endif
