import Foundation
import OpenWithCore
import Testing

@testable import AssociationDoctor

@Suite
struct DiagnosticEngineTests {
    private static let vscode = AppInfo(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", path: "/Applications/Visual Studio Code.app")
    private static let textEdit = AppInfo(bundleID: "com.apple.TextEdit", name: "TextEdit", path: "/System/Applications/TextEdit.app")

    private func scanned(
        target: Target = .ext("md"),
        uti: String? = "net.daringfireball.markdown",
        currentApp: AppInfo? = nil,
        availableApps: [AppInfo] = []
    ) -> ScannedAssociation {
        ScannedAssociation(
            id: target.description,
            target: target,
            uti: uti,
            localizedTypeName: nil,
            category: .text,
            currentApp: currentApp,
            availableApps: availableApps
        )
    }

    private func engine(
        installedApps: [AppInfo] = [],
        configureRawLookup: (inout FakeRawDefaultHandlerProvider) -> Void = { _ in },
        recommendationEngine: RecommendationEngine = RecommendationEngine(appDeclaredTypesReader: FakeAppDeclaredTypesReader())
    ) -> DiagnosticEngine {
        var rawLookup = FakeRawDefaultHandlerProvider()
        configureRawLookup(&rawLookup)
        let provider = FakeLaunchServicesProvider(apps: installedApps)
        return DiagnosticEngine(provider: provider, rawLookup: rawLookup, recommendationEngine: recommendationEngine)
    }

    @Test("a target with a current app is healthy")
    func healthyWhenCurrentAppExists() {
        let record = engine().diagnose([scanned(currentApp: Self.vscode)]).first!
        #expect(record.status == .healthy)
    }

    @Test("no current app and nothing raw-registered is noDefault, not broken")
    func noDefaultWhenNothingWasEverSet() {
        let record = engine().diagnose([scanned(currentApp: nil)]).first!
        #expect(record.status == .noDefault)
    }

    @Test("a raw registration pointing at an uninstalled app is broken")
    func brokenWhenRegisteredAppIsNotInstalled() {
        let engine = engine(installedApps: []) { rawLookup in
            rawLookup.typeBundleIDs["net.daringfireball.markdown"] = "com.adobe.Photoshop2025"
        }

        let record = engine.diagnose([scanned(currentApp: nil)]).first!

        #expect(record.status == .broken)
    }

    @Test("a raw registration pointing at an installed app is not broken")
    func notBrokenWhenRegisteredAppIsInstalled() {
        // NSWorkspace would normally have surfaced this app as `currentApp`
        // already; this only guards the fallback path in isolation.
        let engine = engine(installedApps: [Self.vscode]) { rawLookup in
            rawLookup.typeBundleIDs["net.daringfireball.markdown"] = Self.vscode.bundleID
        }

        let record = engine.diagnose([scanned(currentApp: nil)]).first!

        #expect(record.status != .broken)
    }

    @Test("a raw registration for a URL scheme is checked too")
    func brokenSchemeRegistration() {
        let engine = engine(installedApps: []) { rawLookup in
            rawLookup.schemeBundleIDs["mailto"] = "com.microsoft.Outlook"
        }

        let record = engine.diagnose([scanned(target: .urlScheme("mailto"), uti: nil, currentApp: nil)]).first!

        #expect(record.status == .broken)
    }

    @Test("deviating from the baseline is changed, even though a current app exists")
    func changedWhenCurrentAppDiffersFromBaseline() {
        let baseline = Baseline(
            id: UUID(), name: "My Mac", createdAt: Date(),
            associations: [BaselineAssociation(uti: nil, extensionName: "md", bundleID: Self.vscode.bundleID)])

        let record = engine().diagnose([scanned(currentApp: Self.textEdit)], baseline: baseline).first!

        #expect(record.status == .changed)
    }

    @Test("matching the baseline is healthy, not changed")
    func matchesBaselineIsHealthy() {
        let baseline = Baseline(
            id: UUID(), name: "My Mac", createdAt: Date(),
            associations: [BaselineAssociation(uti: nil, extensionName: "md", bundleID: Self.vscode.bundleID)])

        let record = engine().diagnose([scanned(currentApp: Self.vscode)], baseline: baseline).first!

        #expect(record.status == .healthy)
    }

    @Test("baseline priority: a missing current app the baseline expected is changed, not noDefault")
    func changedTakesPriorityOverNoDefault() {
        let baseline = Baseline(
            id: UUID(), name: "My Mac", createdAt: Date(),
            associations: [BaselineAssociation(uti: nil, extensionName: "md", bundleID: Self.vscode.bundleID)])

        let record = engine().diagnose([scanned(currentApp: nil)], baseline: baseline).first!

        #expect(record.status == .changed)
    }

    @Test("a baseline that says nothing about this target doesn't force a status")
    func baselineNotCoveringTargetFallsThrough() {
        let baseline = Baseline(
            id: UUID(), name: "My Mac", createdAt: Date(),
            associations: [BaselineAssociation(uti: nil, extensionName: "zip", bundleID: Self.vscode.bundleID)])

        let record = engine().diagnose([scanned(currentApp: Self.textEdit)], baseline: baseline).first!

        #expect(record.status == .healthy)
    }

    @Test("a confident, different recommendation makes a healthy-looking association suspicious")
    func suspiciousWhenRecommendationConfidentlyDisagrees() {
        // vscode declares the exact UTI and matches the target's category —
        // easily clears the "medium" confidence bar — while textEdit (the
        // current default) declares nothing, so vscode is the clear winner.
        let recommendationEngine = RecommendationEngine(
            appDeclaredTypesReader: FakeAppDeclaredTypesReader(typesByBundleID: [
                Self.vscode.bundleID: AppDeclaredTypes(utis: ["net.daringfireball.markdown"])
            ]))

        let record = engine(recommendationEngine: recommendationEngine)
            .diagnose([scanned(currentApp: Self.textEdit, availableApps: [Self.vscode, Self.textEdit])])
            .first!

        #expect(record.status == .suspicious)
        #expect(record.recommendation?.suggestedApp.bundleID == Self.vscode.bundleID)
    }

    @Test("baseline agreement overrides a disagreeing recommendation (§43)")
    func baselineOverridesSuspicious() {
        let recommendationEngine = RecommendationEngine(
            appDeclaredTypesReader: FakeAppDeclaredTypesReader(typesByBundleID: [
                Self.vscode.bundleID: AppDeclaredTypes(utis: ["net.daringfireball.markdown"])
            ]))
        let baseline = Baseline(
            id: UUID(), name: "My Mac", createdAt: Date(),
            associations: [BaselineAssociation(uti: nil, extensionName: "md", bundleID: Self.textEdit.bundleID)])

        let record = engine(recommendationEngine: recommendationEngine)
            .diagnose(
                [scanned(currentApp: Self.textEdit, availableApps: [Self.vscode, Self.textEdit])], baseline: baseline
            )
            .first!

        #expect(record.status == .healthy)
    }

    @Test("a low-confidence recommendation doesn't downgrade healthy to suspicious")
    func lowConfidenceRecommendationStaysHealthy() {
        // Neither candidate declares anything, so the best score any
        // candidate can reach is low (§11.2: low only shows options).
        let record = engine()
            .diagnose([scanned(currentApp: Self.textEdit, availableApps: [Self.vscode, Self.textEdit])])
            .first!

        #expect(record.status == .healthy)
    }
}
