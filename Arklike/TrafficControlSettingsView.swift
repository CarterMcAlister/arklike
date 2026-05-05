import SwiftUI

struct TrafficControlSettingsView: View {
    @StateObject private var store = TrafficRuleStore.shared
    @State private var testURL = ""
    @State private var testResult = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Traffic Control")
                    .font(.headline)
                Spacer()
                Button("Add Rule") { addRule() }
            }
            Text("Rules are evaluated top-to-bottom. First enabled match wins and routes external links to the selected Safari profile.")
                .font(.callout)
                .foregroundStyle(.secondary)
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
        let nextOrder = (store.rules.map(\.order).max() ?? 0) + 1
        store.upsert(TrafficRule(name: "New Rule", order: nextOrder, matcherType: .domain, pattern: "example.com", targetProfileNumber: 1))
    }

    private func test() {
        guard let url = URL(string: testURL) else { testResult = "Invalid URL"; return }
        if let match = TrafficRuleMatcher().firstMatch(for: url, rules: store.rules) {
            testResult = "Matched \(match.rule.name) → profile \(match.rule.targetProfileNumber)"
        } else {
            testResult = "No matching rule; Safari default behavior will be used."
        }
    }
}

private struct TrafficRuleRow: View {
    @StateObject private var store = TrafficRuleStore.shared
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
                Stepper("Profile \(rule.targetProfileNumber)", value: $rule.targetProfileNumber, in: 1...9)
            }
            HStack {
                Picker("Behavior", selection: $rule.openBehavior) {
                    ForEach(TrafficOpenBehavior.allCases) { Text($0.rawValue).tag($0) }
                }
                Button("Save") { save() }
                Button("Delete", role: .destructive) { store.delete(rule) }
                if let validation { Text(validation).foregroundStyle(.red) }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func save() {
        validation = TrafficRuleMatcher().validate(rule)
        guard validation == nil else { return }
        store.upsert(rule)
    }
}
