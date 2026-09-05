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
/// Owns the scan → diagnose pipeline and the single-item repair action;
/// the batch Repair Plan / Baseline persistence this will eventually
/// coordinate with are Phase 7/8.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var records: [AssociationRecord] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    // Optional (rather than defaulting to `.dashboard` as a non-optional
    // value) because `List(selection:)` in a `NavigationSplitView` sidebar
    // needs an Optional binding to reliably highlight the right row on
    // first appearance — a non-optional binding highlighted the wrong row
    // until the user clicked something.
    @Published var selectedSection: SidebarSection? = .dashboard
    @Published var settings = SettingsStore()

    /// record id → the current app's bundle ID *at the time it was
    /// ignored* (§23). Session-only for now — persisting `IgnoredFinding`
    /// to disk is a `Persistence` detail that can follow once Baseline
    /// storage (Phase 8) sets the pattern; nothing here depends on it.
    @Published private var ignoredBundleIDByRecordID: [String: String] = [:]

    private let engine = Engine.live()
    private lazy var repairService = RepairService(engine: engine)

    /// What the UI should actually render: the ignore overlay applied,
    /// and URL schemes dropped when the corresponding setting is off.
    var displayRecords: [AssociationRecord] {
        records
            .filter { settings.includeURLSchemes || !isURLScheme($0.target) }
            .map { record in
                if let ignoredBundleID = ignoredBundleIDByRecordID[record.id],
                    record.currentApp?.bundleID == ignoredBundleID
                {
                    return record.withStatus(.ignored)
                }
                return record
            }
    }

    var healthScore: HealthScore { HealthScore(records: displayRecords) }

    /// Every app that shows up anywhere in the scan — as a current default
    /// or just as a declared handler — sorted by name. The "Applications"
    /// screen's app-first view of the same data `displayRecords` already
    /// holds (§ new: browse by program instead of by file type).
    var installedApps: [AppInfo] {
        var seenBundleIDs = Set<String>()
        var apps: [AppInfo] = []
        for record in displayRecords {
            for app in record.availableApps + [record.currentApp].compactMap({ $0 }) {
                if seenBundleIDs.insert(app.bundleID).inserted {
                    apps.append(app)
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Every association `app` can open — whether or not it's currently
    /// the default — straight from LaunchServices' own handler list
    /// (`availableApps`), not a re-derived guess.
    func records(for app: AppInfo) -> [AssociationRecord] {
        displayRecords.filter { record in
            record.availableApps.contains { $0.bundleID == app.bundleID }
        }
    }

    /// `nil` when low-confidence suggestions are hidden by settings and
    /// this one doesn't clear the bar (§11.2: low only shows options, it
    /// isn't asserted as *the* recommendation).
    func visibleRecommendation(for record: AssociationRecord) -> Recommendation? {
        guard let recommendation = record.recommendation else { return nil }
        if recommendation.confidence == .low && !settings.showLowConfidenceRecommendations { return nil }
        return recommendation
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }

        let engine = engine
        let directories =
            settings.includeSystemFileTypes
            ? Discovery.defaultDirectories
            : Discovery.defaultDirectories.filter { !$0.hasPrefix("/System/") }

        let diagnosed = await Task.detached(priority: .userInitiated) {
            let scanner = AssociationScanner(engine: engine, discoveryDirectories: directories)
            let diagnosticEngine = DiagnosticEngine(provider: engine.provider)
            return diagnosticEngine.diagnose(scanner.scan())
        }.value

        records = diagnosed
        lastScanDate = Date()
    }

    func ignore(_ record: AssociationRecord) {
        guard let bundleID = record.currentApp?.bundleID else { return }
        ignoredBundleIDByRecordID[record.id] = bundleID
    }

    func unignore(_ record: AssociationRecord) {
        ignoredBundleIDByRecordID.removeValue(forKey: record.id)
    }

    /// Applies `app` as the default for `record.target` and re-scans so
    /// every screen reflects the real, read-back-verified result — never
    /// the caller's optimistic guess (§15).
    @discardableResult
    func applyFix(_ record: AssociationRecord, app: AppInfo) async -> RepairOutcome {
        let outcome = await repairService.apply(app: app, to: record.target)
        await scan()
        return outcome
    }

    /// The same single-item `RepairService.apply` used by `applyFix`, bare
    /// — for `RepairPlanRunner` (Phase 7) to sequence across a batch. No
    /// rescan here: rescanning after every step of an 8-item plan would be
    /// wasteful and would fight the running plan's own progress list, so
    /// the caller rescans once after the whole plan finishes.
    func applyRepairAction(app: AppInfo, to target: Target) async -> RepairOutcome {
        await repairService.apply(app: app, to: target)
    }

    private func isURLScheme(_ target: Target) -> Bool {
        if case .urlScheme = target { return true }
        return false
    }
}
