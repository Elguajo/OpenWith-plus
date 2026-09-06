import Foundation
import OpenWithCore
import Testing

@testable import AssociationDoctor

/// The layer every screen actually talks to — the ignore overlay, the
/// baseline-first repair decision, protection, and the scan/refresh
/// pipeline. It had no tests at all, which is exactly where the bugs
/// these cover were living.
///
/// Everything is injected: a writable fake provider (no real
/// LaunchServices), a temp Application Support directory, an isolated
/// `UserDefaults` suite, no discovery directories (so only
/// `Curated.targets` are scanned), and a fake raw-handler lookup — without
/// that last one, `broken` vs `noDefault` would depend on whatever this
/// particular Mac has registered.
@MainActor
@Suite
struct AppStateTests {
    private static let code = AppInfo(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", path: "/Applications/Visual Studio Code.app")
    private static let textEdit = AppInfo(bundleID: "com.apple.TextEdit", name: "TextEdit", path: "/System/Applications/TextEdit.app")
    private static let ghost = AppInfo(bundleID: "com.example.Ghost", name: "Ghost", path: "/Applications/Ghost.app")
    private static let markdownUTI = "net.daringfireball.markdown"

    private struct Harness {
        let appState: AppState
        let provider: FakeWritableLaunchServicesProvider
        let suiteName: String
        let directory: URL

        func tearDown() {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// `apps` doubles as the handler list for every content type (see
    /// `FakeWritableLaunchServicesProvider`), so its order is what
    /// "top-ranked by macOS" means in these tests.
    private func harness(
        apps: [AppInfo],
        markdownDefault: AppInfo? = nil,
        baseline: Baseline? = nil
    ) throws -> Harness {
        let provider = FakeWritableLaunchServicesProvider()
        provider.apps = apps
        provider.extensionMap = ["md": Self.markdownUTI]
        if let markdownDefault { provider.typeDefaults[Self.markdownUTI] = markdownDefault.bundleID }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        let store = BaselineStore(directory: directory)
        if let baseline { try store.save(baseline) }

        let suiteName = "AppStateTests.\(UUID().uuidString)"
        let appState = AppState(
            engine: Engine(provider: provider),
            baselineStore: store,
            settings: SettingsStore(defaults: UserDefaults(suiteName: suiteName)!),
            discoveryDirectories: [],
            rawDefaultHandlerProvider: FakeRawDefaultHandlerProvider())
        return Harness(appState: appState, provider: provider, suiteName: suiteName, directory: directory)
    }

    private func markdownBaseline(_ app: AppInfo) -> Baseline {
        Baseline(
            id: UUID(), name: "My Mac", createdAt: Date(),
            associations: [BaselineAssociation(uti: nil, extensionName: "md", bundleID: app.bundleID)])
    }

    private func markdownRecord(_ appState: AppState) -> AssociationRecord? {
        appState.displayRecords.first { $0.target == .ext("md") }
    }

    @Test("a record with no default can be ignored, and un-ignored again")
    func ignoreWorksWithoutACurrentApp() async throws {
        let h = try harness(apps: [Self.code])
        defer { h.tearDown() }
        await h.appState.scan()

        let record = try #require(markdownRecord(h.appState))
        // The case the old ignore silently dropped: nothing is set, so
        // there was no bundle ID to key the ignore on.
        #expect(record.currentApp == nil)
        #expect(record.status == .noDefault)

        h.appState.ignore(record)
        #expect(markdownRecord(h.appState)?.status == .ignored)

        h.appState.unignore(record)
        #expect(markdownRecord(h.appState)?.status == .noDefault)
    }

    @Test("an ignore lapses once the association moves again")
    func ignoreExpiresWhenTheCurrentAppChanges() async throws {
        let h = try harness(apps: [Self.code, Self.textEdit], markdownDefault: Self.textEdit)
        defer { h.tearDown() }
        await h.appState.scan()

        let record = try #require(markdownRecord(h.appState))
        h.appState.ignore(record)
        #expect(markdownRecord(h.appState)?.status == .ignored)

        _ = await h.appState.applyFix(record, app: Self.code)

        #expect(markdownRecord(h.appState)?.currentApp?.bundleID == Self.code.bundleID)
        #expect(markdownRecord(h.appState)?.status != .ignored)
    }

    @Test("a batch repair follows the saved baseline, not the higher-scoring recommendation")
    func baselineOutranksTheRecommendation() async throws {
        // Ghost is first in the handler list, so the heuristic crowns it
        // ("top-ranked by macOS"); the user's baseline says TextEdit; the
        // current default is VS Code. All three deliberately differ.
        let h = try harness(
            apps: [Self.ghost, Self.code, Self.textEdit],
            markdownDefault: Self.code,
            baseline: markdownBaseline(Self.textEdit))
        defer { h.tearDown() }
        h.appState.settings.showLowConfidenceRecommendations = true
        await h.appState.scan()

        let record = try #require(markdownRecord(h.appState))
        #expect(record.status == .changed)
        #expect(h.appState.visibleRecommendation(for: record)?.suggestedApp.bundleID == Self.ghost.bundleID)

        // What "Fix All" / "Fix N Issues" / "Restore" will actually apply.
        #expect(h.appState.desiredApp(for: record)?.bundleID == Self.textEdit.bundleID)

        let plan = RepairPlan.build(from: [record], desiredApp: h.appState.desiredApp)
        #expect(plan.changes.map(\.desiredApp.bundleID) == [Self.textEdit.bundleID])
    }

    @Test("a baseline app that is no longer installed is skipped, not replaced by a guess")
    func uninstalledBaselineAppIsSkipped() async throws {
        let h = try harness(
            apps: [Self.ghost, Self.code],
            markdownDefault: Self.code,
            baseline: markdownBaseline(Self.textEdit))
        defer { h.tearDown() }
        h.appState.settings.showLowConfidenceRecommendations = true
        await h.appState.scan()

        let record = try #require(markdownRecord(h.appState))
        #expect(record.status == .changed)
        #expect(h.appState.desiredApp(for: record) == nil)
        #expect(RepairPlan.build(from: [record], desiredApp: h.appState.desiredApp).changes.isEmpty)
    }

    @Test("a protected association is never planned and never written")
    func protectedAssociationsAreRefused() async throws {
        let h = try harness(apps: [Self.code])
        defer { h.tearDown() }

        let record = AssociationRecord(
            id: "extension:app", target: .ext("app"), uti: "com.apple.application-file",
            localizedTypeName: "Application", category: .executable, currentApp: nil,
            availableApps: [Self.code], status: .noDefault,
            recommendation: Recommendation(
                suggestedApp: Self.code, score: 40, confidence: .high, reasons: [.topRankedBySystem]))

        #expect(h.appState.protection(for: record) == .executable)
        #expect(h.appState.desiredApp(for: record) == nil)

        let outcome = await h.appState.applyFix(record, app: Self.code)
        #expect(outcome == .notPermitted(reason: .executable))
        #expect(h.provider.writeLog.isEmpty)

        let batchOutcome = await h.appState.applyRepairAction(app: Self.code, to: .ext("app"))
        #expect(batchOutcome == .notPermitted(reason: .executable))
        #expect(h.provider.writeLog.isEmpty)
    }

    @Test("the risky setting is what unlocks a protected association")
    func settingUnlocksProtectedAssociations() async throws {
        let h = try harness(apps: [Self.code])
        defer { h.tearDown() }

        let record = AssociationRecord(
            id: "extension:dmg", target: .ext("dmg"), uti: "com.apple.disk-image-udif",
            localizedTypeName: "Disk Image", category: .diskImage, currentApp: nil,
            availableApps: [Self.code], status: .noDefault, recommendation: nil)

        #expect(h.appState.protection(for: record) == .installerOrDiskImage)
        h.appState.settings.allowProtectedAssociationChanges = true
        #expect(h.appState.protection(for: record) == nil)
    }

    @Test("a repair reads its own write back, without a full rescan")
    func repairRefreshesTheTargetItTouched() async throws {
        let h = try harness(apps: [Self.code, Self.textEdit], markdownDefault: Self.textEdit)
        defer { h.tearDown() }
        await h.appState.scan()
        #expect(markdownRecord(h.appState)?.currentApp?.bundleID == Self.textEdit.bundleID)

        let outcome = await h.appState.applyFix(try #require(markdownRecord(h.appState)), app: Self.code)

        #expect(outcome == .applied(Self.code))
        #expect(markdownRecord(h.appState)?.currentApp?.bundleID == Self.code.bundleID)
        #expect(h.appState.isScanning == false)
    }

    @Test("a declined write is reported as such and leaves the record alone")
    func declinedWriteDoesNotMoveTheRecord() async throws {
        let h = try harness(apps: [Self.code, Self.textEdit], markdownDefault: Self.textEdit)
        defer { h.tearDown() }
        await h.appState.scan()
        h.provider.declineWrites = true

        let outcome = await h.appState.applyFix(try #require(markdownRecord(h.appState)), app: Self.code)

        #expect(outcome == .notConfirmed(desired: Self.code))
        #expect(markdownRecord(h.appState)?.currentApp?.bundleID == Self.textEdit.bundleID)
    }

    @Test("overlapping scans settle without leaving the spinner stuck or the scan half-applied")
    func overlappingScansSerialize() async throws {
        let h = try harness(apps: [Self.code], markdownDefault: Self.code)
        defer { h.tearDown() }

        async let first: Void = h.appState.scan()
        async let second: Void = h.appState.scan()
        _ = await (first, second)

        #expect(h.appState.isScanning == false)
        #expect(h.appState.lastScanDate != nil)
        #expect(markdownRecord(h.appState)?.currentApp?.bundleID == Self.code.bundleID)
    }

    @Test("saving a baseline re-diagnoses the current scan against it")
    func savingABaselineUpdatesStatuses() async throws {
        let h = try harness(apps: [Self.code, Self.textEdit], markdownDefault: Self.textEdit)
        defer { h.tearDown() }
        await h.appState.scan()

        try await h.appState.saveCurrentDefaultsAsBaseline()

        #expect(h.appState.baseline?.expectedBundleID(forUTI: Self.markdownUTI, target: .ext("md")) == Self.textEdit.bundleID)
        #expect(markdownRecord(h.appState)?.status == .healthy)

        // And drifting away from it now reads as `.changed`.
        _ = await h.appState.applyFix(try #require(markdownRecord(h.appState)), app: Self.code)
        #expect(markdownRecord(h.appState)?.status == .changed)
    }

    @Test("the derived views agree with each other and refresh when their inputs change")
    func derivedStateStaysConsistent() async throws {
        let h = try harness(apps: [Self.code, Self.textEdit], markdownDefault: Self.textEdit)
        defer { h.tearDown() }
        await h.appState.scan()

        let withSchemes = h.appState.displayRecords.count
        #expect(h.appState.displayRecords.contains { $0.target == .urlScheme("mailto") })

        h.appState.settings.includeURLSchemes = false
        #expect(!h.appState.displayRecords.contains { $0.target == .urlScheme("mailto") })
        #expect(h.appState.displayRecords.count < withSchemes)

        // `records(for:)` is served from an index now, so it has to agree
        // with the filter it replaced.
        let byIndex = h.appState.records(for: Self.code).map(\.id).sorted()
        let byFilter = h.appState.displayRecords
            .filter { record in record.availableApps.contains { $0.bundleID == Self.code.bundleID } }
            .map(\.id).sorted()
        #expect(byIndex == byFilter)
        #expect(h.appState.installedApps.map(\.bundleID).sorted() == [Self.textEdit.bundleID, Self.code.bundleID].sorted())
    }
}
