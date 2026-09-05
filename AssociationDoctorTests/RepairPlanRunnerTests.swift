import OpenWithCore
import Testing

@testable import AssociationDoctor

/// A stand-in for `RepairService.apply` that hands back one canned outcome
/// per call, in order, and records what it was asked to do — enough to
/// verify `RepairPlanRunner`'s sequencing without touching SwiftUI or real
/// LaunchServices.
@MainActor
private final class RecordingApply {
    private(set) var calls: [(app: AppInfo, target: Target)] = []
    private var outcomes: [RepairOutcome]

    init(outcomes: [RepairOutcome]) {
        self.outcomes = outcomes
    }

    func apply(_ app: AppInfo, _ target: Target) async -> RepairOutcome {
        calls.append((app, target))
        return outcomes.isEmpty ? .failed("no canned outcome") : outcomes.removeFirst()
    }
}

@MainActor
@Suite
struct RepairPlanRunnerTests {
    private static let code = AppInfo(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", path: "/Applications/Visual Studio Code.app")
    private static let xcode = AppInfo(bundleID: "com.apple.dt.Xcode", name: "Xcode", path: "/Applications/Xcode.app")
    private static let textEdit = AppInfo(bundleID: "com.apple.TextEdit", name: "TextEdit", path: "/System/Applications/TextEdit.app")

    private func action(target: Target, current: AppInfo?, desired: AppInfo) -> RepairAction {
        RepairAction(target: target, localizedTypeName: nil, currentApp: current, desiredApp: desired)
    }

    @Test("runs every included action in plan order, one at a time")
    func appliesInOrder() async {
        let plan = RepairPlan(changes: [
            action(target: .ext("zsh"), current: Self.xcode, desired: Self.code),
            action(target: .ext("py"), current: nil, desired: Self.code),
        ])
        let recorder = RecordingApply(outcomes: [.applied(Self.code), .applied(Self.code)])
        let runner = RepairPlanRunner(plan: plan, apply: recorder.apply)

        await runner.run()

        #expect(recorder.calls.map(\.target) == [.ext("zsh"), .ext("py")])
        #expect(runner.states == [.done(.applied(Self.code)), .done(.applied(Self.code))])
        #expect(runner.isRunning == false)
        #expect(runner.hasRun == true)
    }

    @Test("a skipped action is never applied and stays skipped after the run")
    func skippedActionIsNeverApplied() async {
        let plan = RepairPlan(changes: [
            action(target: .ext("zsh"), current: Self.xcode, desired: Self.code),
            action(target: .ext("py"), current: nil, desired: Self.code),
        ])
        let recorder = RecordingApply(outcomes: [.applied(Self.code)])
        let runner = RepairPlanRunner(plan: plan, apply: recorder.apply)

        runner.toggleIncluded(at: 0)
        await runner.run()

        #expect(recorder.calls.map(\.target) == [.ext("py")])
        #expect(runner.states[0] == .skipped)
        #expect(runner.states[1] == .done(.applied(Self.code)))
    }

    @Test("toggling back in un-skips an action before the run starts")
    func toggleIsReversibleBeforeRunning() async {
        let plan = RepairPlan(changes: [action(target: .ext("zsh"), current: Self.xcode, desired: Self.code)])
        let runner = RepairPlanRunner(plan: plan, apply: RecordingApply(outcomes: [.applied(Self.code)]).apply)

        runner.toggleIncluded(at: 0)
        #expect(runner.includedCount == 0)
        runner.toggleIncluded(at: 0)
        #expect(runner.includedCount == 1)
    }

    @Test("toggling after the run has finished is a no-op")
    func toggleIsIgnoredAfterRunning() async {
        let plan = RepairPlan(changes: [action(target: .ext("zsh"), current: Self.xcode, desired: Self.code)])
        let runner = RepairPlanRunner(plan: plan, apply: RecordingApply(outcomes: [.applied(Self.code)]).apply)

        await runner.run()
        runner.toggleIncluded(at: 0)

        #expect(runner.states[0] == .done(.applied(Self.code)))
    }

    @Test("running twice never re-applies")
    func runIsIdempotent() async {
        let plan = RepairPlan(changes: [action(target: .ext("zsh"), current: Self.xcode, desired: Self.code)])
        let recorder = RecordingApply(outcomes: [.applied(Self.code)])
        let runner = RepairPlanRunner(plan: plan, apply: recorder.apply)

        await runner.run()
        await runner.run()

        #expect(recorder.calls.count == 1)
    }

    @Test("summary tallies applied, alreadySet, declined, failed, and skipped")
    func summaryTalliesEveryOutcomeKind() async {
        let plan = RepairPlan(changes: [
            action(target: .ext("a"), current: nil, desired: Self.code),
            action(target: .ext("b"), current: nil, desired: Self.code),
            action(target: .ext("c"), current: nil, desired: Self.code),
            action(target: .ext("d"), current: nil, desired: Self.code),
            action(target: .ext("e"), current: nil, desired: Self.code),
        ])
        let recorder = RecordingApply(outcomes: [
            .applied(Self.code), .alreadySet(Self.code), .notConfirmed(desired: Self.code), .failed("boom"),
        ])
        let runner = RepairPlanRunner(plan: plan, apply: recorder.apply)
        runner.toggleIncluded(at: 4)

        await runner.run()
        let summary = runner.summary

        #expect(summary.applied == 1)
        #expect(summary.alreadySet == 1)
        #expect(summary.declined == 1)
        #expect(summary.failed == 1)
        #expect(summary.skipped == 1)
    }

    @Test("RepairPlan.build only includes records with a visible recommendation")
    func buildSkipsRecordsWithoutARecommendation() {
        let withRecommendation = AssociationRecord(
            id: "1", target: .ext("zsh"), uti: "public.shell-script", localizedTypeName: "Shell Script",
            category: .code, currentApp: Self.xcode, availableApps: [Self.xcode, Self.code], status: .suspicious,
            recommendation: Recommendation(suggestedApp: Self.code, score: 10, confidence: .high, reasons: [.categoryMatch]))
        let withoutRecommendation = AssociationRecord(
            id: "2", target: .ext("txt"), uti: "public.plain-text", localizedTypeName: "Plain Text", category: .document,
            currentApp: Self.textEdit, availableApps: [Self.textEdit], status: .healthy, recommendation: nil)

        let plan = RepairPlan.build(from: [withRecommendation, withoutRecommendation]) { $0.recommendation }

        #expect(plan.changes.count == 1)
        #expect(plan.changes[0].target == .ext("zsh"))
        #expect(plan.changes[0].desiredApp == Self.code)
        #expect(plan.changes[0].currentApp == Self.xcode)
        #expect(plan.changes[0].localizedTypeName == "Shell Script")
    }
}
