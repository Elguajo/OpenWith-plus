import OpenWithCore
import UniformTypeIdentifiers

/// Deterministic recommendation scoring (§11) — no AI/LLM. Every score is
/// a sum of explainable, named signals, so a suggestion is never a black
/// box (§5.4).
///
/// Candidates are restricted to `availableApps` (already-installed
/// handlers LaunchServices knows about) — never installed apps that
/// aren't a handler at all, so the `-25 appMissing` signal from §11.1 has
/// no candidate it could ever apply to in this design and stays
/// unreachable, same spirit as the never-guessed statuses in
/// `DiagnosticEngine`.
struct RecommendationEngine {
    var appDeclaredTypesReader: any AppDeclaredTypesReading

    init(appDeclaredTypesReader: any AppDeclaredTypesReading = BundleAppDeclaredTypesReader()) {
        self.appDeclaredTypesReader = appDeclaredTypesReader
    }

    /// One recommendation per scanned item that has at least one candidate,
    /// keyed by `ScannedAssociation.id`. Computed as a batch (rather than
    /// one at a time) so "preferred for related formats" — which needs to
    /// know what's already default *elsewhere* in the scan — and declared
    /// declared-type lookups can be shared instead of recomputed for every
    /// row that happens to list the same handler app.
    func recommend(for allScanned: [ScannedAssociation], baseline: Baseline?) -> [String: Recommendation] {
        var declaredTypesCache: [String: AppDeclaredTypes] = [:]
        func declaredTypes(for app: AppInfo) -> AppDeclaredTypes {
            if let cached = declaredTypesCache[app.bundleID] { return cached }
            let types = appDeclaredTypesReader.declaredTypes(for: app)
            declaredTypesCache[app.bundleID] = types
            return types
        }

        var dominantCategoryCache: [String: FileCategory?] = [:]
        func dominantCategory(for app: AppInfo) -> FileCategory? {
            if let cached = dominantCategoryCache[app.bundleID] { return cached }
            let category = Self.dominantCategory(of: declaredTypes(for: app))
            dominantCategoryCache[app.bundleID] = category
            return category
        }

        // Which bundle IDs are already the current default for each
        // category, anywhere else in this scan (§11.1 "already preferred
        // for related formats").
        var preferredBundleIDsByCategory: [FileCategory: Set<String>] = [:]
        for item in allScanned {
            guard let currentApp = item.currentApp else { continue }
            preferredBundleIDsByCategory[item.category, default: []].insert(currentApp.bundleID)
        }

        var results: [String: Recommendation] = [:]
        for item in allScanned {
            guard
                let recommendation = recommendation(
                    for: item,
                    declaredTypes: declaredTypes(for:),
                    dominantCategory: dominantCategory(for:),
                    preferredBundleIDsByCategory: preferredBundleIDsByCategory,
                    baseline: baseline
                )
            else { continue }
            results[item.id] = recommendation
        }
        return results
    }

    private func recommendation(
        for scanned: ScannedAssociation,
        declaredTypes: (AppInfo) -> AppDeclaredTypes,
        dominantCategory: (AppInfo) -> FileCategory?,
        preferredBundleIDsByCategory: [FileCategory: Set<String>],
        baseline: Baseline?
    ) -> Recommendation? {
        guard !scanned.availableApps.isEmpty else { return nil }
        let expectedBaselineBundleID = Self.expectedBundleID(for: scanned, baseline: baseline)

        var best: (app: AppInfo, score: Double, reasons: [RecommendationReason])?
        for (index, app) in scanned.availableApps.enumerated() {
            let scored = score(
                app: app,
                isTopRanked: index == 0,
                scanned: scanned,
                declaredTypes: declaredTypes(app),
                dominantCategory: dominantCategory(app),
                isPreferredForCategory: preferredBundleIDsByCategory[scanned.category]?.contains(app.bundleID) == true,
                matchesBaseline: expectedBaselineBundleID == app.bundleID
            )
            if best == nil || scored.score > best!.score {
                best = (app, scored.score, scored.reasons)
            }
        }

        guard let best else { return nil }
        return Recommendation(
            suggestedApp: best.app, score: best.score, confidence: confidence(for: best.score), reasons: best.reasons)
    }

    private func score(
        app: AppInfo,
        isTopRanked: Bool,
        scanned: ScannedAssociation,
        declaredTypes: AppDeclaredTypes,
        dominantCategory: FileCategory?,
        isPreferredForCategory: Bool,
        matchesBaseline: Bool
    ) -> (score: Double, reasons: [RecommendationReason]) {
        var score = 0.0
        var reasons: [RecommendationReason] = []

        // A URL scheme's `.category` is always `.web` in `FileCategoryClassifier`
        // regardless of what the scheme actually is (`tel:`, `ssh:`, `vnc:`...) —
        // there is no real "declared document category" to compare a scheme
        // handler against, so this signal would otherwise penalize (or
        // wrongly favor) apps based on unrelated file types they happen to
        // open. Same rationale as `weakHandlerMatch` below being skipped for
        // schemes.
        if case .urlScheme = scanned.target {
            // no-op
        } else if let dominantCategory {
            if dominantCategory == scanned.category {
                score += 30
                reasons.append(.categoryMatch)
            } else {
                score -= 30
                reasons.append(.categoryMismatch)
            }
        }

        if isTopRanked {
            score += 20
            reasons.append(.topRankedBySystem)
        }

        let declaresExactUTI = scanned.uti.map(declaredTypes.utis.contains) ?? false
        if declaresExactUTI {
            score += 15
            reasons.append(.declaresExactUTI)
        }

        var declaresExactExtension = false
        if case .ext(let ext) = scanned.target, declaredTypes.extensions.contains(ext) {
            declaresExactExtension = true
            score += 10
            reasons.append(.declaresExactExtension)
        }

        if isPreferredForCategory {
            score += 10
            reasons.append(.preferredForRelatedFormats)
        }

        if matchesBaseline {
            score += 10
            reasons.append(.matchesBaseline)
        }

        if isSystemUtility(app), isSystemCompatibleType(scanned.uti) {
            score += 5
            reasons.append(.systemUtilityForSystemType)
        }

        // URL schemes have no UTI/extension declaration to check against,
        // so "weak handler" isn't a meaningful signal for them — every
        // scheme handler would otherwise be penalized unfairly.
        if case .urlScheme = scanned.target {
            // no-op
        } else if !declaresExactUTI && !declaresExactExtension {
            score -= 15
            reasons.append(.weakHandlerMatch)
        }

        return (score, reasons)
    }

    /// Thresholds are an MVP judgment call (the spec gives weights, not
    /// cutoffs): `high` needs roughly two major signals to agree, `medium`
    /// needs one, anything weaker stays `low` per §11.2's "only show
    /// options" rule.
    private func confidence(for score: Double) -> RecommendationConfidence {
        switch score {
        case ..<15: return .low
        case 15..<35: return .medium
        default: return .high
        }
    }

    private func isSystemUtility(_ app: AppInfo) -> Bool {
        app.path.hasPrefix("/System/")
    }

    private func isSystemCompatibleType(_ uti: String?) -> Bool {
        uti?.hasPrefix("public.") == true
    }

    private static func dominantCategory(of types: AppDeclaredTypes) -> FileCategory? {
        var counts: [FileCategory: Int] = [:]
        for uti in types.utis {
            let category = FileCategoryClassifier.classify(target: .uti(uti), uti: uti, curatedCategory: nil)
            if category != .unknown { counts[category, default: 0] += 1 }
        }
        for ext in types.extensions {
            // The classifier needs a UTI to run its `UTType.conforms(to:)`
            // check; an app's declared extension has no paired UTI of its
            // own (unlike a scan target, which is always a resolved
            // `ResolvedTarget`), so resolve one the same way LaunchServices
            // would for a bare extension.
            let resolvedUTI = UTType(filenameExtension: ext)?.identifier
            let category = FileCategoryClassifier.classify(target: .ext(ext), uti: resolvedUTI, curatedCategory: nil)
            if category != .unknown { counts[category, default: 0] += 1 }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    static func expectedBundleID(for scanned: ScannedAssociation, baseline: Baseline?) -> String? {
        guard let baseline else { return nil }
        return baseline.associations.first { entry in
            if let uti = scanned.uti, let entryUTI = entry.uti, uti == entryUTI { return true }
            if case .ext(let ext) = scanned.target, entry.extensionName == ext { return true }
            return false
        }?.bundleID
    }
}
