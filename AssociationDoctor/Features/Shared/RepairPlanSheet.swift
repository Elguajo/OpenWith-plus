import OpenWithCore
import SwiftUI

/// Phase 7: review a `RepairPlan` before touching anything, then watch it
/// apply one item at a time (§15/§16). One sheet, three phases driven by
/// `RepairPlanRunner`'s own state — not a separate screen, per the phase
/// brief: this is an action/sheet flow off Dashboard and Problems.
struct RepairPlanSheet: View {
    @StateObject private var runner: RepairPlanRunner
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(plan: RepairPlan, apply: @escaping (AppInfo, Target) async -> RepairOutcome, onFinished: @escaping () -> Void) {
        _runner = StateObject(wrappedValue: RepairPlanRunner(plan: plan, apply: apply))
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            List {
                if runner.hasRun {
                    Section("Result") { summaryRows }
                }
                Section {
                    ForEach(Array(runner.plan.changes.enumerated()), id: \.offset) { index, action in
                        RepairActionRow(
                            action: action,
                            state: runner.states[index],
                            isEditable: !runner.hasRun,
                            onToggle: { runner.toggleIncluded(at: index) })
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(runner.hasRun ? "Done" : "Cancel") { dismiss() }
                }
                if !runner.hasRun {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply \(runner.includedCount) Changes") {
                            Task {
                                await runner.run()
                                onFinished()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(runner.includedCount == 0)
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 480)
    }

    private var title: String {
        if !runner.hasRun { return "Review \(runner.plan.changes.count) Changes" }
        return runner.isRunning ? "Applying…" : "Repair Complete"
    }

    private var summaryRows: some View {
        let summary = runner.summary
        return Group {
            if summary.applied > 0 { summaryRow("Applied", count: summary.applied, color: .green) }
            if summary.alreadySet > 0 { summaryRow("Already Set", count: summary.alreadySet, color: .secondary) }
            if summary.declined > 0 { summaryRow("Declined / Unconfirmed", count: summary.declined, color: .orange) }
            if summary.failed > 0 { summaryRow("Failed", count: summary.failed, color: .red) }
            if summary.skipped > 0 { summaryRow("Skipped", count: summary.skipped, color: .secondary) }
        }
    }

    private func summaryRow(_ label: String, count: Int, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count)").fontWeight(.medium).monospacedDigit()
        }
        .foregroundStyle(color)
    }
}

private struct RepairActionRow: View {
    let action: RepairAction
    let state: RepairStepState
    let isEditable: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isEditable {
                Button(action: onToggle) {
                    Image(systemName: state == .skipped ? "circle" : "checkmark.circle.fill")
                        .foregroundStyle(state == .skipped ? .secondary : Color.accentColor)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(action.localizedTypeName ?? action.target.value)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    AppIconView(app: action.currentApp, size: 16)
                    Text(action.currentApp?.name ?? "None").foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    AppIconView(app: action.desiredApp, size: 16)
                    Text(action.desiredApp.name)
                }
                .font(.caption)
            }

            Spacer()
            statusView
        }
        .opacity(state == .skipped ? 0.5 : 1)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .pending:
            EmptyView()
        case .skipped:
            Text("Skipped").font(.caption).foregroundStyle(.secondary)
        case .applying:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for confirmation…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .done(let outcome):
            RepairOutcomeBadge(outcome: outcome)
        }
    }
}
