import OpenWithCore
import SwiftUI

/// Lets the user pick any declared handler for one association — used by
/// Problems' "Choose Another" and by All Associations' "Change" (§19/§20).
struct AppPickerSheet: View {
    let record: AssociationRecord
    let onSelect: (AppInfo) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(record.availableApps, id: \.bundleID) { app in
                Button {
                    onSelect(app)
                } label: {
                    HStack {
                        AppIconView(app: app, size: 24)
                        Text(app.name)
                        Spacer()
                        if app.bundleID == record.currentApp?.bundleID {
                            Text("Current").font(.caption).foregroundStyle(.secondary)
                        }
                    }
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
