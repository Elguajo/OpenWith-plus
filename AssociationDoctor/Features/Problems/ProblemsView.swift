import OpenWithCore
import SwiftUI

/// §19. Only non-healthy, non-ignored associations ever show up here —
/// "All" means "every problem," not literally every scanned type.
struct ProblemsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: ProblemFilter = .all
    @State private var appPickerRecord: AssociationRecord?
    @State private var outcomeMessage: RepairOutcomeMessage?
    @State private var isApplying = false
    @State private var reviewingPlan: RepairPlan?

    /// The `.ignored` filter is the way back out of Ignore (§23): dismissed
    /// findings are hidden from every other filter, so without a place that
    /// lists them an ignore was a one-way door for the rest of the session.
    private var problems: [AssociationRecord] {
        if filter == .ignored { return appState.displayRecords.filter { $0.status == .ignored } }
        let nonHealthy = appState.displayRecords.filter { $0.status != .healthy && $0.status != .ignored }
        guard let status = filter.status else { return nonHealthy }
        return nonHealthy.filter { $0.status == status }
    }

    /// Every currently-visible problem `appState` has an opinion on, as a
    /// batch — "Fix All" only ever offers what's on screen under the
    /// active filter, never the full unfiltered problem set behind it.
    private var fixAllPlan: RepairPlan {
        RepairPlan.build(from: problems, desiredApp: appState.desiredApp)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(ProblemFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if problems.isEmpty {
                emptyState
            } else {
                List(problems) { record in
                    ProblemCard(
                        record: record,
                        isApplying: isApplying,
                        onFix: { applyFix(record, app: $0) },
                        onChooseAnother: { appPickerRecord = record },
                        onIgnore: { appState.ignore(record) },
                        onUnignore: { appState.unignore(record) }
                    )
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Problems")
        .toolbar {
            ToolbarItem {
                let plan = fixAllPlan
                Button("Fix All (\(plan.changes.count))") { reviewingPlan = plan }
                    .disabled(plan.changes.isEmpty)
            }
        }
        .sheet(item: $appPickerRecord) { record in
            AppPickerSheet(record: record) { app in
                appPickerRecord = nil
                applyFix(record, app: app)
            }
        }
        .sheet(item: $reviewingPlan) { plan in
            RepairPlanSheet(plan: plan, apply: appState.applyRepairAction, onFinished: { Task { await appState.refresh(targets: plan.changes.map(\.target)) } })
        }
        .alert(item: $outcomeMessage) { message in
            Alert(title: Text("Repair Result"), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            ContentUnavailableView(
                "No Problems",
                systemImage: "checkmark.seal",
                description: Text(
                    appState.records.isEmpty
                        ? "Run a scan from the Dashboard first." : "Nothing needs attention in this filter."))
            Spacer()
        }
    }

    private func applyFix(_ record: AssociationRecord, app: AppInfo) {
        isApplying = true
        Task {
            let outcome = await appState.applyFix(record, app: app)
            isApplying = false
            outcomeMessage = RepairOutcomeMessage(outcome)
        }
    }
}

private enum ProblemFilter: String, CaseIterable, Identifiable {
    case all, broken, suspicious, changed, noDefault, ignored

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .broken: return "Broken"
        case .suspicious: return "Suspicious"
        case .changed: return "Changed"
        case .noDefault: return "No Default"
        case .ignored: return "Ignored"
        }
    }

    var status: AssociationStatus? {
        switch self {
        case .all: return nil
        case .broken: return .broken
        case .suspicious: return .suspicious
        case .changed: return .changed
        case .noDefault: return .noDefault
        case .ignored: return .ignored
        }
    }
}

private struct ProblemCard: View {
    let record: AssociationRecord
    let isApplying: Bool
    let onFix: (AppInfo) -> Void
    let onChooseAnother: () -> Void
    let onIgnore: () -> Void
    let onUnignore: () -> Void

    @EnvironmentObject private var appState: AppState

    private var protection: ProtectionReason? { appState.protection(for: record) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AppIconView(app: record.currentApp, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.localizedTypeName ?? record.target.value)
                        .font(.headline)
                    Text(record.target.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: record.status)
            }

            HStack(spacing: 4) {
                Text("Current:").foregroundStyle(.secondary)
                Text(record.currentApp?.name ?? "None")
            }
            .font(.subheadline)

            if let protection {
                ProtectedNotice(reason: protection)
            } else if let recommendation = appState.visibleRecommendation(for: record) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Recommended:").foregroundStyle(.secondary)
                        Text(recommendation.suggestedApp.name).fontWeight(.medium)
                    }
                    if !recommendation.reasons.isEmpty {
                        Text(recommendation.reasons.map(\.displayText).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }

            HStack {
                if protection == nil, let recommendation = appState.visibleRecommendation(for: record) {
                    Button("Fix") { onFix(recommendation.suggestedApp) }
                        .buttonStyle(.borderedProminent)
                        .disabled(isApplying)
                }
                Button("Choose Another", action: onChooseAnother)
                    .disabled(protection != nil || record.availableApps.isEmpty || isApplying)
                Spacer()
                if record.status == .ignored {
                    Button("Stop Ignoring", action: onUnignore)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Button("Ignore", action: onIgnore)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

