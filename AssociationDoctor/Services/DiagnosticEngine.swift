import OpenWithCore

/// Turns raw scan results into diagnosed `AssociationRecord`s (§10).
///
/// Covers `healthy` / `broken` / `noDefault` / `changed` / `suspicious`.
/// `ignored` needs the Ignore feature (§23) and stays unreachable here on
/// purpose rather than guessed at.
struct DiagnosticEngine {
    var provider: any LaunchServicesProviding
    var rawLookup: any RawDefaultHandlerProviding
    var recommendationEngine: RecommendationEngine

    init(
        provider: any LaunchServicesProviding,
        rawLookup: any RawDefaultHandlerProviding = LiveRawDefaultHandlerProvider(),
        recommendationEngine: RecommendationEngine = RecommendationEngine()
    ) {
        self.provider = provider
        self.rawLookup = rawLookup
        self.recommendationEngine = recommendationEngine
    }

    /// - Parameter baseline: the user's desired state, if one has been
    ///   saved (Phase 8 persists it; this engine only needs the value).
    ///   Without one, `changed` can never be reported — there is nothing to
    ///   compare against.
    func diagnose(_ scanned: [ScannedAssociation], baseline: Baseline? = nil) -> [AssociationRecord] {
        let recommendations = recommendationEngine.recommend(for: scanned, baseline: baseline)
        return scanned.map { diagnose($0, baseline: baseline, recommendation: recommendations[$0.id]) }
    }

    private func diagnose(_ scanned: ScannedAssociation, baseline: Baseline?, recommendation: Recommendation?) -> AssociationRecord {
        AssociationRecord(
            id: scanned.id,
            target: scanned.target,
            uti: scanned.uti,
            localizedTypeName: scanned.localizedTypeName,
            category: scanned.category,
            currentApp: scanned.currentApp,
            availableApps: scanned.availableApps,
            status: status(for: scanned, baseline: baseline, recommendation: recommendation),
            recommendation: recommendation
        )
    }

    private func status(for scanned: ScannedAssociation, baseline: Baseline?, recommendation: Recommendation?) -> AssociationStatus {
        let expected = RecommendationEngine.expectedBundleID(for: scanned, baseline: baseline)

        // A baseline mismatch is the most specific signal available — it
        // means the user had an explicit preference and something moved
        // it — so it wins over the generic healthy/broken/noDefault read.
        if let expected, scanned.currentApp?.bundleID != expected {
            return .changed
        }

        guard let currentApp = scanned.currentApp else {
            return isRegisteredButUninstalled(scanned) ? .broken : .noDefault
        }

        // Only second-guess the current app when the baseline has no
        // opinion here at all (§43: baseline outranks heuristics) and the
        // Recommendation Engine is confident enough to act on (§10.4,
        // §11.2 — "medium" is the show-a-recommendation bar).
        if expected == nil, let recommendation,
            recommendation.confidence >= .medium,
            recommendation.suggestedApp.bundleID != currentApp.bundleID
        {
            return .suspicious
        }

        return .healthy
    }

    /// True when LaunchServices still has *something* registered as the
    /// default but that bundle ID no longer resolves to an installed app —
    /// the ".psd → Photoshop 2025" case in §10.1, as opposed to a type that
    /// never had a default set.
    private func isRegisteredButUninstalled(_ scanned: ScannedAssociation) -> Bool {
        let bundleID: String?
        if let uti = scanned.uti {
            bundleID = rawLookup.rawDefaultBundleID(forContentType: uti)
        } else if case .urlScheme(let scheme) = scanned.target {
            bundleID = rawLookup.rawDefaultBundleID(forScheme: scheme)
        } else {
            bundleID = nil
        }

        guard let bundleID, !bundleID.isEmpty else { return false }
        return provider.app(forBundleID: bundleID) == nil
    }
}
