import SwiftUI

struct DiagnosticsView: View {
    @StateObject private var diagnostics = Diagnostics.shared
    @StateObject private var permissions = PermissionsManager.shared
    @StateObject private var safari = FrontmostSafariMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Diagnostics")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    permissions.refreshAsync()
                    safari.scheduleRefresh(reason: "diagnostics refresh", delay: 0)
                }
                Button("Copy Diagnostics") { diagnostics.copyDiagnostics() }
            }
            LabeledContent("Last slow operation", value: diagnostics.lastSlowOperation)
            Text(diagnostics.report())
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
#Preview("Diagnostics") {
    let _ = PreviewFixtures.configureAppState()
    DiagnosticsView()
        .padding(20)
        .frame(width: 700)
}
#endif
