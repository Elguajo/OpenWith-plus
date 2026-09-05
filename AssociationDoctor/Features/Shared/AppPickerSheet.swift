import OpenWithCore
import SwiftUI

/// Lets the user pick any declared handler for one association — used by
/// Problems' "Choose Another" and by All Associations' "Change" (§19/§20).
/// The Recommendation Engine's pick (if any, and if visible per settings)
/// floats to the top with a "Recommended" label — manual choice stays
/// free, but the best-scored option is never buried in whatever order
/// LaunchServices happened to hand back.
struct AppPickerSheet: View {
    let record: AssociationRecord
    let onSelect: (AppInfo) -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var recommendedBundleID: String? {
        appState.visibleRecommendation(for: record)?.suggestedApp.bundleID
    }

    private var orderedApps: [AppInfo] {
        guard let recommendedID = recommendedBundleID,
            let index = record.availableApps.firstIndex(where: { $0.bundleID == recommendedID })
        else { return record.availableApps }
        var apps = record.availableApps
        let recommended = apps.remove(at: index)
        apps.insert(recommended, at: 0)
        return apps
    }

    var body: some View {
        NavigationStack {
            List(orderedApps, id: \.bundleID) { app in
                Button {
                    onSelect(app)
                } label: {
                    AppPickerRow(
                        app: app, isRecommended: app.bundleID == recommendedBundleID,
                        isCurrent: app.bundleID == record.currentApp?.bundleID)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Choose an App")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 320)
    }
}

private struct AppPickerRow: View {
    let app: AppInfo
    let isRecommended: Bool
    let isCurrent: Bool

    var body: some View {
        HStack {
            AppIconView(app: app, size: 24)
            Text(app.name)
            Spacer()
            if isRecommended {
                Text("Recommended").font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
            }
            if isCurrent {
                Text("Current").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
