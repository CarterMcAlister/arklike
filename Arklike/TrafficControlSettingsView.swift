import SwiftUI

struct TrafficControlSettingsView: View {
    @StateObject private var store = TrafficRuleStore.shared
    @StateObject private var profileStore = ProfileStore.shared
    @State private var testURL = ""
    @State private var testResult = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Traffic Control")
                    .font(.headline)
                Spacer()
                Button("Add Rule") { addRule() }
                    .disabled(profileStore.profiles.isEmpty)
            }
            Text("Rules are evaluated top-to-bottom. First enabled match wins and routes external links to the selected Safari profile.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if profileStore.profiles.isEmpty {
                Text("No Safari profiles have been discovered yet. Refresh Profiles before adding Traffic Control rules.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.rules) { rule in
                TrafficRuleRow(rule: rule)
            }
            HStack {
                TextField("Test URL", text: $testURL)
                Button("Test") { test() }
            }
            if !testResult.isEmpty { Text(testResult).font(.callout).foregroundStyle(.secondary) }
        }
    }

    private func addRule() {
        guard let profile = profileStore.profiles.first else { return }
        let nextOrder = (store.rules.map(\.order).max() ?? 0) + 1
        store.upsert(TrafficRule(name: "New Rule", order: nextOrder, matcherType: .domain, pattern: "example.com", targetProfileNumber: profile.assignedNumber))
    }

    private func test() {
        guard let url = URL(string: testURL) else { testResult = "Invalid URL"; return }
        if let match = TrafficRuleMatcher().firstMatch(for: url, rules: store.rules) {
            let profileName = profileStore.profile(number: match.rule.targetProfileNumber)?.displayName ?? "Profile \(match.rule.targetProfileNumber)"
            testResult = "Matched \(match.rule.name) → \(profileName)"
        } else {
            testResult = "No matching rule; Safari default behavior will be used."
        }
    }
}

#if DEBUG
#Preview("Traffic Control Settings") {
    let _ = PreviewFixtures.configureAppState()
    TrafficControlSettingsView()
        .padding(20)
        .frame(width: 760)
}
#endif

private struct TrafficRuleRow: View {
    @StateObject private var store = TrafficRuleStore.shared
    @StateObject private var profileStore = ProfileStore.shared
    @State var rule: TrafficRule
    @State private var validation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $rule.enabled).labelsHidden()
                TextField("Name", text: $rule.name)
                Picker("Type", selection: $rule.matcherType) {
                    ForEach(TrafficMatcherType.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Pattern", text: $rule.pattern)
                profileMenu
            }
            HStack {
                Button("Save") { save() }
                Button("Delete", role: .destructive) { store.delete(rule) }
                if let validation { Text(validation).foregroundStyle(.red) }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { selectExistingProfileIfNeeded(profileStore.profiles) }
        .onChange(of: profileStore.profiles) { _, profiles in
            selectExistingProfileIfNeeded(profiles)
        }
    }

    private var profileMenu: some View {
        Menu {
            ForEach(profileStore.profiles) { profile in
                Button(profile.displayName) {
                    rule.targetProfileNumber = profile.assignedNumber
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedProfileName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 160, alignment: .leading)
        }
        .disabled(profileStore.profiles.isEmpty)
    }

    private func save() {
        validation = TrafficRuleMatcher().validate(rule)
        if validation == nil, profileStore.profile(number: rule.targetProfileNumber) == nil {
            validation = "Select an existing Safari profile."
        }
        guard validation == nil else { return }
        store.upsert(rule)
    }

    private var selectedProfileName: String {
        profileStore.profile(number: rule.targetProfileNumber)?.displayName ?? "No profile selected"
    }

    private func selectExistingProfileIfNeeded(_ profiles: [Profile]) {
        guard !profiles.contains(where: { $0.assignedNumber == rule.targetProfileNumber }),
              let firstProfile = profiles.first else { return }
        rule.targetProfileNumber = firstProfile.assignedNumber
    }
}
