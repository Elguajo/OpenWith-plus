import OpenWithCore
import Testing

@testable import AssociationDoctor

@Suite
struct RepairServiceTests {
    private static let vscode = AppInfo(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", path: "/Applications/Visual Studio Code.app")
    private static let textEdit = AppInfo(bundleID: "com.apple.TextEdit", name: "TextEdit", path: "/System/Applications/TextEdit.app")

    @Test("applying a new default reports .applied after a successful read-back")
    func appliesAndConfirms() async {
        let provider = FakeWritableLaunchServicesProvider()
        provider.apps = [Self.vscode, Self.textEdit]
        provider.typeDefaults["public.plain-text"] = Self.textEdit.bundleID
        let service = RepairService(engine: Engine(provider: provider))

        let outcome = await service.apply(app: Self.vscode, to: .uti("public.plain-text"))

        #expect(outcome == .applied(Self.vscode))
        #expect(provider.typeDefaults["public.plain-text"] == Self.vscode.bundleID)
    }

    @Test("applying the app that's already the default reports .alreadySet without writing")
    func alreadySetSkipsWrite() async {
        let provider = FakeWritableLaunchServicesProvider()
        provider.apps = [Self.vscode]
        provider.typeDefaults["public.plain-text"] = Self.vscode.bundleID
        let service = RepairService(engine: Engine(provider: provider))

        let outcome = await service.apply(app: Self.vscode, to: .uti("public.plain-text"))

        #expect(outcome == .alreadySet(Self.vscode))
        #expect(provider.writeLog.isEmpty)
    }

    @Test("a declined write is reported as notConfirmed, never as success")
    func declinedWriteIsNotConfirmed() async {
        let provider = FakeWritableLaunchServicesProvider()
        provider.apps = [Self.vscode, Self.textEdit]
        provider.typeDefaults["public.plain-text"] = Self.textEdit.bundleID
        provider.declineWrites = true
        let service = RepairService(engine: Engine(provider: provider))

        let outcome = await service.apply(app: Self.vscode, to: .uti("public.plain-text"))

        #expect(outcome == .notConfirmed(desired: Self.vscode))
        #expect(provider.typeDefaults["public.plain-text"] == Self.textEdit.bundleID)
    }

    @Test("an unresolvable target fails instead of crashing")
    func unresolvableTargetFails() async {
        let provider = FakeWritableLaunchServicesProvider()
        let service = RepairService(engine: Engine(provider: provider))

        let outcome = await service.apply(app: Self.vscode, to: .ext("unknownextension"))

        guard case .failed = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
    }
}
