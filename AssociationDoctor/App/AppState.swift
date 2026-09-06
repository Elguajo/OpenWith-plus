import Foundation
import OpenWithCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard
    case problems
    case allAssociations
    case applications
    case profiles
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .problems: return "Problems"
        case .allAssociations: return "All Associations"
        case .applications: return "Applications"
        case .profiles: return "Profiles"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .problems: return "exclamationmark.triangle"
        case .allAssociations: return "list.bullet.rectangle"
        case .applications: return "square.grid.2x2"
        case .profiles: return "person.crop.rectangle.stack"
        case .settings: return "gearshape"
        }
    }
}

/// App-wide state: the current scan, navigation selection, and settings.
/// Owns the scan → diagnose pipeline (baseline-aware since Phase 8), the
/// single-item repair action, and the saved `Baseline` itself.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var records: [AssociationRecord] = [] { didSet { recordsRevision += 1 } }
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    // Optional (rather than defaulting to `.dashboard` as a non-optional
    // value) because `List(selection:)` in a `NavigationSplitView` sidebar
    // needs an Optional binding to reliably highlight the right row on
    // first appearance — a non-optional binding highlighted the wrong row
    // until the user clicked something.
    @Published var selectedSection: SidebarSection? = .dashboard
    @Published var settings: SettingsStore
    /// The saved baseline, if any (§13/§14) — loaded once at launch and
    /// kept in sync with `baselineStore` by every save. `scan()` feeds it to
    /// `DiagnosticEngine`/`RecommendationEngine` so `.changed` and
    /// `matchesBaseline` go live the moment one exists.
    @Published private(set) var baseline: Baseline?

    /// record id → what the record looked like when the user ignored it
    /// (§23), so the ignore auto-expires as soon as the association moves
    /// again. Session-only for now — persisting `IgnoredFinding` to disk is
    /// a `Persistence` detail that can follow once Baseline storage
    /// (Phase 8) sets the pattern; nothing here depends on it.
    ///
    /// The snapshot carries an *optional* bundle ID rather than a bare
    /// `String`: `broken` and `noDefault` records have no current app at
    /// all, and keying on a non-optional bundle ID silently dropped every
    /// ignore on exactly those two statuses — the most common problems.
    @Published private var ignoredByRecordID: [String: IgnoredSnapshot] = [:]

    struct IgnoredSnapshot: Equatable {
        let currentAppBundleID: String?
    }

    private let engine: Engine
    private lazy var repairService = RepairService(engine: engine)
    private let baselineStore: BaselineStore
    private let discoveryDirectories: [String]
    /// Only reason it's held here: `DiagnosticEngine` needs it to tell
    /// `broken` from `noDefault`, and it reads the real LaunchServices
    /// database — so a test that doesn't inject one would have its
    /// statuses depend on whatever this Mac happens to have registered.
    private let rawDefaultHandlerProvider: any RawDefaultHandlerProviding

    /// The last raw scan, kept so a repair can re-read just the targets it
    /// touched (and a new baseline can re-diagnose) instead of sweeping
    /// LaunchServices again.
    private var scanned: [ScannedAssociation] = []
    /// The scan/refresh currently in flight, if any — see `serialized`.
    private var scanTask: Task<Void, Never>?
    private var inFlightCount = 0

    private var recordsRevision = 0
    private var cachedDerived: (key: DerivedKey, value: Derived)?

    /// Set when the saved baseline was on disk but couldn't be read, so
    /// Profiles can say so instead of silently presenting the "no baseline
    /// yet" empty state over a file the user still has.
    @Published private(set) var baselineWarning: String?

    /// Everything the app talks to from here is injectable, so tests can
    /// exercise this layer — the ignore overlay, the baseline-first repair
    /// decision, the scan/refresh pipeline — against fakes instead of the
    /// machine's real defaults, real Application Support and real
    /// `UserDefaults`. The defaults are the live ones the app ships with.
    init(
        engine: Engine = .live(),
        baselineStore: BaselineStore = BaselineStore(),
        settings: SettingsStore = SettingsStore(),
        discoveryDirectories: [String] = Discovery.defaultDirectories,
        rawDefaultHandlerProvider: any RawDefaultHandlerProviding = LiveRawDefaultHandlerProvider()
    ) {
        self.engine = engine
        self.rawDefaultHandlerProvider = rawDefaultHandlerProvider
        self.settings = settings
        self.discoveryDirectories = discoveryDirectories
        self.baselineStore = baselineStore
        switch baselineStore.load() {
        case .loaded(let baseline):
            self.baseline = baseline
        case .empty:
            self.baseline = nil
        case .unreadable(let backupURL):
            self.baseline = nil
            self.baselineWarning =
                backupURL.map {
                    "Your saved baseline couldn't be read. It was kept at \($0.path) — saving again won't overwrite it."
                } ?? "Your saved baseline couldn't be read, and a copy of it couldn't be kept."
        }
    }

    /// What the UI should actually render: the ignore overlay applied,
    /// and URL schemes dropped when the corresponding setting is off.
    var displayRecords: [AssociationRecord] { derived.displayRecords }

    func isIgnored(_ record: AssociationRecord) -> Bool {
        guard let snapshot = ignoredByRecordID[record.id] else { return false }
        return snapshot.currentAppBundleID == record.currentApp?.bundleID
    }

    var healthScore: HealthScore { HealthScore(records: displayRecords) }

    /// Every app that shows up anywhere in the scan — as a current default
    /// or just as a declared handler — sorted by name. The "Applications"
    /// screen's app-first view of the same data `displayRecords` already
    /// holds (§ new: browse by program instead of by file type).
    var installedApps: [AppInfo] { derived.installedApps }

    /// Every association `app` can open — whether or not it's currently
    /// the default — straight from LaunchServices' own handler list
    /// (`availableApps`), not a re-derived guess.
    func records(for app: AppInfo) -> [AssociationRecord] {
        derived.recordsByAppBundleID[app.bundleID] ?? []
    }

    /// `displayRecords`, `installedApps` and `records(for:)` in one pass,
    /// memoized until something they depend on actually changes.
    ///
    /// Each of them used to walk the whole scan — ~1,700 records on a
    /// typical Mac — on *every* access, and SwiftUI touches them several
    /// times per render. The Applications list was quadratic on top of
    /// that: one full filter-and-map per row, per pass. The key covers
    /// every input, so the cache can't go stale without being rebuilt.
    private var derived: Derived {
        let key = DerivedKey(
            recordsRevision: recordsRevision,
            includeURLSchemes: settings.includeURLSchemes,
            ignored: ignoredByRecordID)
        if let cachedDerived, cachedDerived.key == key { return cachedDerived.value }
        let value = buildDerived()
        cachedDerived = (key, value)
        return value
    }

    private func buildDerived() -> Derived {
        let includeURLSchemes = settings.includeURLSchemes
        var displayRecords: [AssociationRecord] = []
        displayRecords.reserveCapacity(records.count)
        var recordsByAppBundleID: [String: [AssociationRecord]] = [:]
        var appsByBundleID: [String: AppInfo] = [:]

        for record in records {
            guard includeURLSchemes || !isURLScheme(record.target) else { continue }
            let shown = isIgnored(record) ? record.withStatus(.ignored) : record
            displayRecords.append(shown)

            for app in shown.availableApps {
                recordsByAppBundleID[app.bundleID, default: []].append(shown)
                if appsByBundleID[app.bundleID] == nil { appsByBundleID[app.bundleID] = app }
            }
            if let currentApp = shown.currentApp, appsByBundleID[currentApp.bundleID] == nil {
                appsByBundleID[currentApp.bundleID] = currentApp
            }
        }

        return Derived(
            displayRecords: displayRecords,
            installedApps: appsByBundleID.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            },
            recordsByAppBundleID: recordsByAppBundleID)
    }

    private struct Derived {
        let displayRecords: [AssociationRecord]
        let installedApps: [AppInfo]
        let recordsByAppBundleID: [String: [AssociationRecord]]
    }

    private struct DerivedKey: Equatable {
        let recordsRevision: Int
        let includeURLSchemes: Bool
        let ignored: [String: IgnoredSnapshot]
    }

    /// `nil` when low-confidence suggestions are hidden by settings and
    /// this one doesn't clear the bar (§11.2: low only shows options, it
    /// isn't asserted as *the* recommendation), or when the suggestion is
    /// already the current app — a `.changed` record (baseline mismatch)
    /// can still have `RecommendationEngine` independently score the
    /// *current* app highest, which isn't a fix worth offering: "Fix" and
    /// the batch Repair Plan should never present a same-app no-op.
    func visibleRecommendation(for record: AssociationRecord) -> Recommendation? {
        guard let recommendation = record.recommendation else { return nil }
        if recommendation.suggestedApp.bundleID == record.currentApp?.bundleID { return nil }
        if recommendation.confidence == .low && !settings.showLowConfidenceRecommendations { return nil }
        return recommendation
    }

    /// What a batch repair should set for `record` — the single source of
    /// truth behind every "Fix All" / "Fix N Issues" / "Restore" plan.
    ///
    /// The saved baseline wins outright when it has an opinion (§43: the
    /// user's own state outranks any heuristic). `RecommendationEngine`
    /// only scores `matchesBaseline` at +10, which a category match plus a
    /// system top-ranking easily outbids — so a plan built straight from
    /// the recommendation could silently move a `.changed` association to
    /// an app the user never chose, while `DiagnosticEngine` was at the
    /// same time reporting it as drift *from* the baseline.
    ///
    /// `nil` means "this plan has nothing safe to apply here": the baseline
    /// app is no longer installed (never fall back to the heuristic — that
    /// is the same silent override), or there is no visible recommendation.
    func desiredApp(for record: AssociationRecord) -> AppInfo? {
        guard protection(for: record) == nil else { return nil }
        if let expectedBundleID = baseline?.expectedBundleID(for: record) {
            guard expectedBundleID != record.currentApp?.bundleID else { return nil }
            return record.availableApps.first { $0.bundleID == expectedBundleID }
        }
        return visibleRecommendation(for: record)?.suggestedApp
    }

    /// A full LaunchServices sweep. Serialized against every other scan and
    /// refresh (see `serialized`).
    func scan() async {
        await serialized { await self.performFullScan() }
    }

    /// Re-reads only `targets` and re-diagnoses everything against the
    /// result — what a repair needs, instead of the full sweep it used to
    /// trigger. A scan resolves and queries LaunchServices for every known
    /// target (~1,700 on a typical Mac); doing that after each single
    /// "Fix" made the result alert wait on work the change couldn't
    /// possibly have affected.
    ///
    /// Known limit, and the reason the manual Scan button stays: when
    /// LaunchServices cascades a change to related types (setting a mail
    /// client also moves several of its schemes), only the targets named
    /// here are re-read — the rest catch up on the next full scan.
    func refresh(targets: [Target]) async {
        await serialized { await self.performRefresh(targets: targets) }
    }

    /// Snapshots `displayRecords`' current apps as the baseline and
    /// persists it — "Save Current Defaults" the first time, "Update
    /// Baseline" (§21) after. Re-diagnoses afterward so `.changed`/
    /// `matchesBaseline` reflect the just-saved state immediately: nothing
    /// on disk changed, so re-reading LaunchServices would tell us exactly
    /// what we already know.
    func saveCurrentDefaultsAsBaseline(name: String = "My Mac") async throws {
        let newBaseline = Baseline.capturing(name: name, from: displayRecords)
        try baselineStore.save(newBaseline)
        baseline = newBaseline
        await serialized { await self.rediagnose() }
    }

    /// Runs `work` after whatever scan or refresh is already in flight.
    ///
    /// `records` is last-writer-wins, so overlapping runs — the launch scan
    /// against a manual one, or a repair's refresh against either — could
    /// land out of order and leave the UI showing pre-repair state. They
    /// also each flipped `isScanning` off on their own, so the spinner
    /// stopped and the Scan button re-enabled while another pass was still
    /// running. Chaining costs a little duplicate work in the rare overlap
    /// and buys an invariant worth more: a refresh always observes its own
    /// write.
    private func serialized(_ work: @escaping @MainActor () async -> Void) async {
        inFlightCount += 1
        isScanning = true
        let previous = scanTask
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        scanTask = task
        await task.value
        inFlightCount -= 1
        isScanning = inFlightCount > 0
    }

    private func performFullScan() async {
        let engine = engine
        let rawLookup = rawDefaultHandlerProvider
        let baseline = baseline
        let directories =
            settings.includeSystemFileTypes
            ? discoveryDirectories
            : discoveryDirectories.filter { !$0.hasPrefix("/System/") }

        let result = await Task.detached(priority: .userInitiated) {
            let scanner = AssociationScanner(engine: engine, discoveryDirectories: directories)
            let scanned = scanner.scan()
            let diagnosticEngine = DiagnosticEngine(provider: engine.provider, rawLookup: rawLookup)
            return (scanned, diagnosticEngine.diagnose(scanned, baseline: baseline))
        }.value

        scanned = result.0
        records = result.1
        lastScanDate = Date()
    }

    private func performRefresh(targets: [Target]) async {
        guard !scanned.isEmpty else { return await performFullScan() }

        let engine = engine
        let rawLookup = rawDefaultHandlerProvider
        let baseline = baseline
        let current = scanned
        let wanted = Set(targets)

        let result = await Task.detached(priority: .userInitiated) {
            let scanner = AssociationScanner(engine: engine)
            let updated = current.map { wanted.contains($0.target) ? scanner.refreshed($0) : $0 }
            let diagnosticEngine = DiagnosticEngine(provider: engine.provider, rawLookup: rawLookup)
            return (updated, diagnosticEngine.diagnose(updated, baseline: baseline))
        }.value

        scanned = result.0
        records = result.1
    }

    /// Re-runs diagnosis over the last scan without touching
    /// LaunchServices — for changes that only move *our* opinion, like
    /// saving a new baseline.
    private func rediagnose() async {
        guard !scanned.isEmpty else { return }
        let engine = engine
        let rawLookup = rawDefaultHandlerProvider
        let baseline = baseline
        let current = scanned

        records = await Task.detached(priority: .userInitiated) {
            DiagnosticEngine(provider: engine.provider, rawLookup: rawLookup).diagnose(current, baseline: baseline)
        }.value
    }

    /// Works for every status, including `broken`/`noDefault`, where there
    /// is no current app to remember — "nothing is set here and I'm fine
    /// with that" is exactly the case a user wants to dismiss.
    func ignore(_ record: AssociationRecord) {
        ignoredByRecordID[record.id] = IgnoredSnapshot(currentAppBundleID: record.currentApp?.bundleID)
    }

    func unignore(_ record: AssociationRecord) {
        ignoredByRecordID.removeValue(forKey: record.id)
    }

    /// Why this association can't be reassigned, or `nil` when it's the
    /// user's to change. The setting is checked here rather than inside
    /// `AssociationProtection` so the policy itself stays a pure, testable
    /// rule set and there is exactly one place the override is honored.
    func protection(for record: AssociationRecord) -> ProtectionReason? {
        protection(forTarget: record.target, uti: record.uti)
    }

    private func protection(forTarget target: Target, uti: String?) -> ProtectionReason? {
        guard !settings.allowProtectedAssociationChanges else { return nil }
        return AssociationProtection.reason(for: target, uti: uti)
    }

    /// Applies `app` as the default for `record.target` and re-reads that
    /// target so every screen reflects the real, read-back-verified result
    /// — never the caller's optimistic guess (§15).
    @discardableResult
    func applyFix(_ record: AssociationRecord, app: AppInfo) async -> RepairOutcome {
        if let reason = protection(for: record) { return .notPermitted(reason: reason) }
        let outcome = await repairService.apply(app: app, to: record.target)
        await refresh(targets: [record.target])
        return outcome
    }

    /// The same single-item `RepairService.apply` used by `applyFix`, bare
    /// — for `RepairPlanRunner` (Phase 7) to sequence across a batch. No
    /// rescan here: rescanning after every step of an 8-item plan would be
    /// wasteful and would fight the running plan's own progress list, so
    /// the caller rescans once after the whole plan finishes.
    ///
    /// Re-checks protection even though `desiredApp` already excluded
    /// protected records from every plan: this is the one call that
    /// actually writes, so it — not the screen that built the plan — is
    /// where the guarantee has to hold (a plan can outlive the setting
    /// that was on when it was built).
    func applyRepairAction(app: AppInfo, to target: Target) async -> RepairOutcome {
        let uti = records.first { $0.target == target }?.uti
        if let reason = protection(forTarget: target, uti: uti) { return .notPermitted(reason: reason) }
        return await repairService.apply(app: app, to: target)
    }

    private func isURLScheme(_ target: Target) -> Bool {
        if case .urlScheme = target { return true }
        return false
    }
}
