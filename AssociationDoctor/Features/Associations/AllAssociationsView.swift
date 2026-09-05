import OpenWithCore
import SwiftUI

/// §20. Every scanned association, searchable and grouped by category.
///
/// Defaults to `isCurated` types only (OpenWithCore's hand-picked common
/// list — .rar/.zip/.mp4/.mp3 and the like): a scan easily turns up 1000+
/// obscure types found only because *some* installed app happens to
/// declare them, and burying .rar among those defeats the "5-second read"
/// the spec asks for (§42). "All" un-hides the long tail for anyone who
/// wants it.
struct AllAssociationsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var scope: Scope = .common
    @State private var appPickerRecord: AssociationRecord?
    @State private var outcomeMessage: RepairOutcomeMessage?

    private enum Scope: String, CaseIterable, Identifiable {
        case common, all
        var id: String { rawValue }
        var title: String { self == .common ? "Common" : "All" }
    }

    private var scoped: [AssociationRecord] {
        scope == .common ? appState.displayRecords.filter(\.isCurated) : appState.displayRecords
    }

    private var filtered: [AssociationRecord] {
        guard !searchText.isEmpty else { return scoped }
        let needle = searchText.lowercased()
        return scoped.filter { record in
            (record.localizedTypeName?.lowercased().contains(needle) ?? false)
                || record.target.value.lowercased().contains(needle)
                || (record.currentApp?.name.lowercased().contains(needle) ?? false)
        }
    }

    private var grouped: [(category: FileCategory, records: [AssociationRecord])] {
        Dictionary(grouping: filtered, by: \.category)
            .sorted { $0.key.displayName < $1.key.displayName }
            .map { (category: $0.key, records: $0.value.sorted { recordSortKey($0) < recordSortKey($1) }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            content
        }
        .navigationTitle("All Associations")
        .searchable(text: $searchText, prompt: "Search file types or apps")
        .sheet(item: $appPickerRecord) { record in
            AppPickerSheet(record: record) { app in
                appPickerRecord = nil
                applyChange(record, app: app)
            }
        }
        .alert(item: $outcomeMessage) { message in
            Alert(title: Text("Repair Result"), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.records.isEmpty {
            ContentUnavailableView(
                "No Scan Yet", systemImage: "magnifyingglass", description: Text("Run a scan from the Dashboard first."))
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List {
                ForEach(grouped, id: \.category) { group in
                    Section(group.category.displayName) {
                        ForEach(group.records) { record in
                            AssociationRow(
                                record: record, showAdvancedUTI: appState.settings.showAdvancedUTIIdentifiers,
                                onChange: { appPickerRecord = record })
                        }
                    }
                }
            }
        }
    }

    private func recordSortKey(_ record: AssociationRecord) -> String {
        record.localizedTypeName ?? record.target.value
    }

    private func applyChange(_ record: AssociationRecord, app: AppInfo) {
        Task {
            let outcome = await appState.applyFix(record, app: app)
            outcomeMessage = RepairOutcomeMessage(outcome)
        }
    }
}

private struct AssociationRow: View {
    let record: AssociationRecord
    let showAdvancedUTI: Bool
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(app: record.currentApp, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.localizedTypeName ?? record.target.value)
                Text(showAdvancedUTI ? (record.uti ?? record.target.description) : record.target.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(record.currentApp?.name ?? "None")
                .foregroundStyle(.secondary)
            StatusBadge(status: record.status)
            Button("Change...", action: onChange)
                .buttonStyle(.link)
                .disabled(record.availableApps.isEmpty)
        }
        .padding(.vertical, 2)
    }
}
