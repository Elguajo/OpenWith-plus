import OpenWithCore
import SwiftUI

/// Browse by program instead of by file type: pick an app, see everything
/// it can open, and set it as the default for anything it isn't already.
/// The reverse of All Associations' "type → app" view over the same scan
/// data — no separate scan or state needed.
struct ApplicationsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    private var apps: [AppInfo] {
        let all = appState.installedApps
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if appState.records.isEmpty {
                ContentUnavailableView(
                    "No Scan Yet", systemImage: "square.grid.2x2", description: Text("Run a scan from the Dashboard first."))
            } else if apps.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(apps, id: \.bundleID) { app in
                    NavigationLink(value: app) {
                        ApplicationRow(app: app, records: appState.records(for: app))
                    }
                }
            }
        }
        .navigationTitle("Applications")
        .searchable(text: $searchText, prompt: "Search applications")
        .navigationDestination(for: AppInfo.self) { app in
            ApplicationDetailView(app: app)
        }
    }
}

private struct ApplicationRow: View {
    let app: AppInfo
    let records: [AssociationRecord]

    private var defaultCount: Int {
        records.filter { $0.currentApp?.bundleID == app.bundleID }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(app: app, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                Text("\(defaultCount) of \(records.count) types set as default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
