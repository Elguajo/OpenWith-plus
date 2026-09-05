import OpenWithCore
import SwiftUI

/// Everything one app can open, with a direct "Make Default" for whatever
/// it isn't already handling — the answer to "what can this program open,
/// and can I just tell it to open all of that."
struct ApplicationDetailView: View {
    let app: AppInfo

    @EnvironmentObject private var appState: AppState
    @State private var applyingRecordID: String?
    @State private var outcomeMessage: RepairOutcomeMessage?

    private var records: [AssociationRecord] {
        appState.records(for: app).sorted {
            ($0.localizedTypeName ?? $0.target.value).localizedCaseInsensitiveCompare($1.localizedTypeName ?? $1.target.value)
                == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    AppIconView(app: app, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.title3.weight(.semibold))
                        Text(app.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Can Open (\(records.count))") {
                ForEach(records) { record in
                    ApplicationCapabilityRow(
                        record: record,
                        isDefault: record.currentApp?.bundleID == app.bundleID,
                        isApplying: applyingRecordID == record.id,
                        onMakeDefault: { makeDefault(record) }
                    )
                }
            }
        }
        .navigationTitle(app.name)
        .alert(item: $outcomeMessage) { message in
            Alert(title: Text("Repair Result"), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
    }

    private func makeDefault(_ record: AssociationRecord) {
        applyingRecordID = record.id
        Task {
            let outcome = await appState.applyFix(record, app: app)
            applyingRecordID = nil
            outcomeMessage = RepairOutcomeMessage(outcome)
        }
    }
}

private struct ApplicationCapabilityRow: View {
    let record: AssociationRecord
    let isDefault: Bool
    let isApplying: Bool
    let onMakeDefault: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.localizedTypeName ?? record.target.value)
                Text(record.target.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDefault {
                Label("Default", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Make Default", action: onMakeDefault)
                    .disabled(isApplying)
            }
        }
        .padding(.vertical, 2)
    }
}
