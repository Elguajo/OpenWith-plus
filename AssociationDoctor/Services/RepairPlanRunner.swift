import Foundation
import OpenWithCore

/// Where one `RepairAction` in a running `RepairPlan` stands. `.skipped` is
/// distinct from `RepairOutcome` on purpose — it's a Review-time user
/// choice, not something `RepairService` ever produces.
enum RepairStepState: Sendable, Equatable {
    case pending
    case skipped
    case applying
    case done(RepairOutcome)
}

/// How a finished (or partially finished) plan run breaks down, for the
/// result screen.
struct RepairPlanSummary: Equatable {
    var applied = 0
    var alreadySet = 0
    var declined = 0
    var failed = 0
    var skipped = 0
    var protected = 0
    /// Included actions the run never reached — it was stopped part-way.
    var notApplied = 0

    init(states: [RepairStepState]) {
        for state in states {
            switch state {
            case .applying: continue
            case .pending: notApplied += 1
            case .skipped: skipped += 1
            case .done(let outcome):
                switch outcome {
                case .applied: applied += 1
                case .alreadySet: alreadySet += 1
                case .notConfirmed: declined += 1
                case .failed: failed += 1
                case .notPermitted: protected += 1
                }
            }
        }
    }
}

/// Drives one `RepairPlan` through Review → Apply → Result. Applies its
/// included actions strictly one at a time — never `withTaskGroup` /
/// `async let` — because each one can raise its own OS confirmation dialog
/// (§16), and firing them concurrently would stack dialogs the user never
/// asked for. Deliberately independent of SwiftUI: `apply` is injected so
/// this is testable against a fake, the same way `RepairService` is.
@MainActor
final class RepairPlanRunner: ObservableObject {
    let plan: RepairPlan
    @Published private(set) var states: [RepairStepState]
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isRunning = false
    @Published private(set) var hasRun = false
    @Published private(set) var isCancelled = false

    private let apply: (AppInfo, Target) async -> RepairOutcome

    init(plan: RepairPlan, apply: @escaping (AppInfo, Target) async -> RepairOutcome) {
        self.plan = plan
        self.states = Array(repeating: .pending, count: plan.changes.count)
        self.apply = apply
    }

    var includedCount: Int { states.filter { $0 != .skipped }.count }

    var summary: RepairPlanSummary { RepairPlanSummary(states: states) }

    /// Review-phase only: flips one action between included and skipped.
    /// No-op once running or finished — selection is a before-the-fact
    /// decision, not something you take back mid-apply.
    func toggleIncluded(at index: Int) {
        guard !isRunning, !hasRun, states.indices.contains(index) else { return }
        states[index] = (states[index] == .skipped) ? .pending : .skipped
    }

    /// Stops the run after the item currently being applied. It cannot
    /// unwind that one: its confirmation dialog already belongs to macOS,
    /// and the write either lands or doesn't regardless of what this app
    /// wants. Everything after it stays `pending` and is reported as "not
    /// applied" — the alternative was a plan the user could only watch,
    /// since closing the sheet left it running invisibly.
    func cancel() {
        guard isRunning else { return }
        isCancelled = true
    }

    /// Applies every non-skipped action in order, updating `states` live so
    /// the Review sheet can show per-item progress. Safe to call only once
    /// per runner — a finished (or in-flight) run is left alone.
    func run() async {
        guard !isRunning, !hasRun else { return }
        isRunning = true
        hasRun = true
        defer {
            isRunning = false
            currentIndex = nil
        }
        for index in plan.changes.indices where states[index] != .skipped {
            guard !isCancelled else { break }
            currentIndex = index
            states[index] = .applying
            let action = plan.changes[index]
            states[index] = .done(await apply(action.desiredApp, action.target))
        }
    }
}
