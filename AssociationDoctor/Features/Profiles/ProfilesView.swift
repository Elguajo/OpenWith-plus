import SwiftUI

/// §21: Save/Compare/Restore/Update against the Phase 8 `BaselineStore`.
/// MVP is the single "My Mac" baseline (§14) — no profile switcher.
/// Restore reuses Phase 7's `RepairPlanSheet`, the same Review → Apply →
/// Result flow Dashboard/Problems already use, not a second one. Export
/// (§21's wireframe) is V1.1 per the spec's own roadmap (§32) — left out.
struct ProfilesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isSaving = false
    @State private var comparingBaseline = false
    @State private var reviewingPlan: RepairPlan?
    @State private var saveErrorMessage: String?

    var body: some View {
        Group {
            if let baseline = appState.baseline {
                savedBaselineView(baseline)
            } else {
                emptyState
            }
        }
        .navigationTitle("Profiles")
        .sheet(isPresented: $comparingBaseline) {
            BaselineCompareSheet(records: changedRecords, baseline: appState.baseline)
        }
        .sheet(item: $reviewingPlan) { plan in
            RepairPlanSheet(plan: plan, apply: appState.applyRepairAction, onFinished: { Task { await appState.refresh(targets: plan.changes.map(\.target)) } })
        }
        .alert("Couldn't Save Baseline", isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    /// Every currently-scanned association that has drifted from the saved
    /// baseline — `DiagnosticEngine` already computed this as `.changed`
    /// (§43), so Compare/Restore read it straight off `displayRecords`
    /// rather than inventing a second diff model.
    private var changedRecords: [AssociationRecord] {
        appState.displayRecords.filter { $0.status == .changed }
    }

    /// Restore, as a `RepairPlan`: every changed record whose baseline app
    /// is still installed (i.e. still shows up in `availableApps`) gets a
    /// `RepairAction` back to it. A baseline entry for an app that's since
    /// been uninstalled is silently skipped — there's nothing to apply it
    /// to, the same way every other plan skips what it can't safely set.
    ///
    /// Goes through `AppState.desiredApp` rather than re-deriving the
    /// baseline match here: that one decision point is what keeps Restore,
    /// "Fix All" and "Fix N Issues" from disagreeing about which app a
    /// changed association belongs to.
    private var restorePlan: RepairPlan {
        RepairPlan.build(from: changedRecords, desiredApp: appState.desiredApp)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if let warning = appState.baselineWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)
            }
            ContentUnavailableView(
                "No Baseline Saved",
                systemImage: "person.crop.rectangle.stack",
                description: Text("Save your current defaults as a baseline to track drift and restore them later.")
            )
            Button("Save Current Defaults") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || appState.records.isEmpty)
        }
    }

    private func savedBaselineView(_ baseline: Baseline) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(baseline.name)
                    .font(.title2.weight(.semibold))
                Text("\(baseline.associations.count) saved associations")
                    .foregroundStyle(.secondary)
                Text("Created \(baseline.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(.secondary)
            }

            if !changedRecords.isEmpty {
                Label("\(changedRecords.count) changed since this baseline", systemImage: AssociationStatus.changed.systemImage)
                    .foregroundStyle(AssociationStatus.changed.tintColor)
            }

            HStack {
                Button("Compare") { comparingBaseline = true }
                    .disabled(changedRecords.isEmpty)
                Button("Restore") { reviewingPlan = restorePlan }
                    .disabled(restorePlan.changes.isEmpty)
                Button("Update Baseline") { save() }
                    .disabled(isSaving || appState.records.isEmpty)
            }
        }
        .padding(32)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await appState.saveCurrentDefaultsAsBaseline()
            } catch {
                saveErrorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// Read-only diff view for "Compare" (§21) — current app vs. what the
/// baseline expects, for every `.changed` record. No apply action here;
/// that's what Restore's `RepairPlanSheet` is for.
private struct BaselineCompareSheet: View {
    let records: [AssociationRecord]
    let baseline: Baseline?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(records) { record in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.localizedTypeName ?? record.target.value)
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 6) {
                            AppIconView(app: record.currentApp, size: 16)
                            Text(record.currentApp?.name ?? "None").foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Text(expectedAppName(for: record))
                        }
                        .font(.caption)
                    }
                    Spacer()
                    StatusBadge(status: .changed)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Changed Since Baseline")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private func expectedAppName(for record: AssociationRecord) -> String {
        guard let baseline, let bundleID = baseline.expectedBundleID(for: record) else { return "Unknown" }
        return record.availableApps.first(where: { $0.bundleID == bundleID })?.name ?? bundleID
    }
}
