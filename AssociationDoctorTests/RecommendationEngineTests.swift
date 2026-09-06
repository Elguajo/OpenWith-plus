import Foundation
import OpenWithCore
import Testing

@testable import AssociationDoctor

@Suite
struct RecommendationEngineTests {
    private static let unarchiver = AppInfo(bundleID: "cx.c3.theunarchiver", name: "The Unarchiver", path: "/Applications/The Unarchiver.app")
    private static let vlc = AppInfo(bundleID: "org.videolan.vlc", name: "VLC", path: "/Applications/VLC.app")
    private static let archiveUtility = AppInfo(
        bundleID: "com.apple.archiveutility", name: "Archive Utility",
        path: "/System/Library/CoreServices/Applications/Archive Utility.app")

    private func scanned(
        target: Target = .ext("rar"),
        uti: String? = "com.rarlab.rar-archive",
        category: FileCategory = .archive,
        currentApp: AppInfo? = nil,
        availableApps: [AppInfo]
    ) -> ScannedAssociation {
        ScannedAssociation(
            id: target.description, target: target, uti: uti, localizedTypeName: nil, category: category,
            currentApp: currentApp, availableApps: availableApps)
    }

    private func engine(typesByBundleID: [String: AppDeclaredTypes] = [:]) -> RecommendationEngine {
        RecommendationEngine(appDeclaredTypesReader: FakeAppDeclaredTypesReader(typesByBundleID: typesByBundleID))
    }

    @Test("no candidates means no recommendation")
    func noCandidatesNoRecommendation() {
        let recommendations = engine().recommend(for: [scanned(availableApps: [])], baseline: nil)
        #expect(recommendations.isEmpty)
    }

    @Test("the first (system-ranked) candidate wins when nothing else distinguishes them")
    func topRankedWinsAllElseEqual() {
        let item = scanned(availableApps: [Self.unarchiver, Self.vlc])
        let recommendation = engine().recommend(for: [item], baseline: nil)[item.id]

        #expect(recommendation?.suggestedApp.bundleID == Self.unarchiver.bundleID)
        #expect(recommendation?.reasons.contains(.topRankedBySystem) == true)
    }

    @Test("declaring the exact UTI beats being merely top-ranked")
    func exactUTIBeatsTopRanked() {
        // vlc is listed first (system-ranked), but unarchiver is the one
        // that actually declares this UTI and matches its category.
        let item = scanned(availableApps: [Self.vlc, Self.unarchiver])
        let recommendationEngine = engine(typesByBundleID: [
            Self.unarchiver.bundleID: AppDeclaredTypes(utis: ["com.rarlab.rar-archive", "public.zip-archive"])
        ])

        let recommendation = recommendationEngine.recommend(for: [item], baseline: nil)[item.id]

        #expect(recommendation?.suggestedApp.bundleID == Self.unarchiver.bundleID)
        #expect(recommendation?.reasons.contains(.declaresExactUTI) == true)
        #expect(recommendation?.reasons.contains(.categoryMatch) == true)
        #expect(recommendation?.confidence == .high)
    }

    @Test("declaring the exact extension is scored even without a matching UTI declaration")
    func declaresExactExtensionSignal() {
        // A nonsense extension guarantees no real UTType on any machine
        // resolves it to something with a category — isolates this signal
        // from the category-matching one.
        let item = scanned(target: .ext("zzzassocdoctortest"), uti: nil, availableApps: [Self.vlc, Self.unarchiver])
        let recommendationEngine = engine(typesByBundleID: [
            Self.unarchiver.bundleID: AppDeclaredTypes(extensions: ["zzzassocdoctortest"])
        ])

        let recommendation = recommendationEngine.recommend(for: [item], baseline: nil)[item.id]

        #expect(recommendation?.suggestedApp.bundleID == Self.unarchiver.bundleID)
        #expect(recommendation?.reasons.contains(.declaresExactExtension) == true)
    }

    @Test("a candidate that clearly specializes in a different category is penalized")
    func categoryMismatchIsPenalized() {
        let item = scanned(availableApps: [Self.vlc])
        // A stable, system-declared image UTI — always conforms to
        // `.image` regardless of what's installed on the test machine.
        let recommendationEngine = engine(typesByBundleID: [
            Self.vlc.bundleID: AppDeclaredTypes(utis: ["public.jpeg"])
        ])

        let recommendation = recommendationEngine.recommend(for: [item], baseline: nil)[item.id]

        #expect(recommendation?.reasons.contains(.categoryMismatch) == true)
        #expect((recommendation?.score ?? 0) < 0)
    }

    @Test("already being the default for related formats is rewarded")
    func preferredForRelatedFormatsSignal() {
        // unarchiver is already the current default for a *different*
        // archive-category target elsewhere in the same scan.
        let alreadyDefaultElsewhere = scanned(
            target: .ext("zip"), uti: "public.zip-archive", currentApp: Self.unarchiver,
            availableApps: [Self.unarchiver])
        // unarchiver is listed first here too, so the win isn't just
        // `topRankedBySystem` reappearing under another name.
        let target = scanned(availableApps: [Self.unarchiver, Self.vlc])

        let recommendations = engine().recommend(for: [alreadyDefaultElsewhere, target], baseline: nil)

        #expect(recommendations[target.id]?.reasons.contains(.preferredForRelatedFormats) == true)
        #expect(recommendations[target.id]?.suggestedApp.bundleID == Self.unarchiver.bundleID)
    }

    @Test("the baseline's own choice is rewarded even without any declared-type signal")
    func matchesBaselineSignal() {
        // unarchiver listed first too, so the +10 baseline bonus isn't
        // just riding along on `topRankedBySystem`.
        let item = scanned(availableApps: [Self.unarchiver, Self.vlc])
        let baseline = Baseline(
            id: UUID(), name: "My Mac", createdAt: Date(),
            associations: [BaselineAssociation(uti: nil, extensionName: "rar", bundleID: Self.unarchiver.bundleID)])

        let recommendation = engine().recommend(for: [item], baseline: baseline)[item.id]

        #expect(recommendation?.suggestedApp.bundleID == Self.unarchiver.bundleID)
        #expect(recommendation?.reasons.contains(.matchesBaseline) == true)
    }

    @Test("a system utility is rewarded for a system-declared (public.*) type")
    func systemUtilitySignal() {
        // archiveUtility listed first too, so the +5 bonus isn't just
        // riding along on `topRankedBySystem`.
        let item = scanned(uti: "public.zip-archive", availableApps: [Self.archiveUtility, Self.vlc])

        let recommendation = engine().recommend(for: [item], baseline: nil)[item.id]

        #expect(recommendation?.suggestedApp.bundleID == Self.archiveUtility.bundleID)
        #expect(recommendation?.reasons.contains(.systemUtilityForSystemType) == true)
    }

    @Test("a URL scheme handler is never penalized as a weak match")
    func urlSchemeSkipsWeakHandlerPenalty() {
        let item = scanned(target: .urlScheme("mailto"), uti: nil, availableApps: [Self.vlc])

        let recommendation = engine().recommend(for: [item], baseline: nil)[item.id]

        #expect(recommendation?.reasons.contains(.weakHandlerMatch) != true)
    }

    @Test("a URL scheme handler is never penalized for category mismatch")
    func urlSchemeSkipsCategoryMismatchPenalty() {
        // Real browsers (Safari, Chrome) declare far more non-web document
        // types (icons, images, plain text...) than actual web-page types,
        // so their *dominant* declared category is often `.image`, not
        // `.web` — but `FileCategoryClassifier` always reports `.web` for
        // any `.urlScheme` target regardless of what the specific scheme
        // is. Scoring that mismatch would wrongly penalize the correct,
        // sole handler of `http`/`https` (and unfairly favor some other
        // app that happens to declare only HTML types). VLC standing in
        // for "an app whose declared types skew toward a different
        // category" here, same as `categoryMismatchIsPenalized`.
        let item = scanned(target: .urlScheme("http"), uti: nil, category: .web, availableApps: [Self.vlc])
        let recommendationEngine = engine(typesByBundleID: [
            Self.vlc.bundleID: AppDeclaredTypes(utis: ["public.jpeg"])
        ])

        let recommendation = recommendationEngine.recommend(for: [item], baseline: nil)[item.id]

        #expect(recommendation?.reasons.contains(.categoryMismatch) != true)
        #expect(recommendation?.reasons.contains(.categoryMatch) != true)
    }

    @Test("a plain extension handler with no declarations is a weak match")
    func weakHandlerMatchForUndeclaredExtension() {
        let item = scanned(availableApps: [Self.vlc])

        let recommendation = engine().recommend(for: [item], baseline: nil)[item.id]

        #expect(recommendation?.reasons.contains(.weakHandlerMatch) == true)
    }

    @Test("confidence rises with the number of agreeing signals")
    func confidenceTiers() {
        // Low: two candidates, neither declares anything — the winner is
        // just whoever is system-ranked first, netted against the weak-
        // handler penalty (+20 - 15 = 5).
        let low = scanned(target: .ext("zzzconfidencelow"), uti: nil, availableApps: [Self.vlc, Self.unarchiver])

        // Medium: unarchiver isn't system-ranked first, but a category
        // match alone (+30) outweighs the weak-handler penalty (-15 — it
        // still isn't the *exact* declared type) for a net of 15.
        let medium = scanned(availableApps: [Self.vlc, Self.unarchiver])
        let mediumEngine = engine(typesByBundleID: [
            Self.unarchiver.bundleID: AppDeclaredTypes(utis: ["org.gnu.gnu-zip-archive"])
        ])

        // High: unarchiver is system-ranked first, matches the category,
        // AND declares the exact UTI — three agreeing signals.
        let high = scanned(uti: "public.zip-archive", availableApps: [Self.unarchiver, Self.vlc])
        let highEngine = engine(typesByBundleID: [
            Self.unarchiver.bundleID: AppDeclaredTypes(utis: ["public.zip-archive"])
        ])

        #expect(engine().recommend(for: [low], baseline: nil)[low.id]?.confidence == .low)
        #expect(mediumEngine.recommend(for: [medium], baseline: nil)[medium.id]?.confidence == .medium)
        #expect(highEngine.recommend(for: [high], baseline: nil)[high.id]?.confidence == .high)
    }
}
