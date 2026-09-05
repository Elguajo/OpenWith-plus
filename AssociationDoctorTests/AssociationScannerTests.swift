import OpenWithCore
import Testing

@testable import AssociationDoctor

@Suite
struct AssociationScannerTests {
    private static let vscode = AppInfo(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", path: "/Applications/Visual Studio Code.app")
    private static let textEdit = AppInfo(bundleID: "com.apple.TextEdit", name: "TextEdit", path: "/System/Applications/TextEdit.app")

    private func scanner(_ configure: (inout FakeLaunchServicesProvider) -> Void) -> AssociationScanner {
        var provider = FakeLaunchServicesProvider()
        configure(&provider)
        // Curated.targets is fixed; Discovery is disabled (no directories) so
        // results are limited to what the fake provider resolves, keeping
        // the test deterministic and off the real filesystem.
        return AssociationScanner(engine: Engine(provider: provider), discoveryDirectories: [])
    }

    @Test("resolves a curated extension to its UTI and current default")
    func resolvesExtensionToCurrentDefault() {
        let scanner = scanner { provider in
            provider.apps = [Self.vscode]
            provider.extensionMap = ["md": "net.daringfireball.markdown"]
            provider.declaredTypes = ["net.daringfireball.markdown"]
            provider.typeDefaults = ["net.daringfireball.markdown": Self.vscode.bundleID]
            provider.descriptions = ["net.daringfireball.markdown": "Markdown Document"]
        }

        let record = scanner.scan().first { $0.target == .ext("md") }

        #expect(record != nil)
        #expect(record?.uti == "net.daringfireball.markdown")
        #expect(record?.localizedTypeName == "Markdown Document")
        #expect(record?.currentApp == Self.vscode)
    }

    @Test("lists all declared handlers, not just the current default")
    func listsAllHandlers() {
        let scanner = scanner { provider in
            provider.apps = [Self.vscode, Self.textEdit]
            provider.extensionMap = ["md": "net.daringfireball.markdown"]
            provider.typeDefaults = ["net.daringfireball.markdown": Self.vscode.bundleID]
            provider.typeHandlers = ["net.daringfireball.markdown": [Self.vscode.bundleID, Self.textEdit.bundleID]]
        }

        let record = scanner.scan().first { $0.target == .ext("md") }

        #expect(record?.availableApps.count == 2)
        #expect(record?.availableApps.contains(Self.textEdit) == true)
    }

    @Test("dedupes records that resolve to the same LaunchServices key")
    func dedupesByResolvedTarget() {
        let scanner = scanner { provider in
            provider.apps = [Self.vscode]
            // Curated already has `.uti("public.zip-archive")`; forcing
            // "tar" and "gz" to resolve to it too simulates two different
            // `Target`s colliding on the same LaunchServices key — the
            // scanner must keep exactly one record, not three.
            provider.extensionMap = ["tar": "public.zip-archive", "gz": "public.zip-archive"]
            provider.declaredTypes = ["public.zip-archive"]
            provider.typeDefaults = ["public.zip-archive": Self.vscode.bundleID]
        }

        let matches = scanner.scan().filter { $0.uti == "public.zip-archive" }

        #expect(matches.count == 1)
        #expect(matches.first?.target == .uti("public.zip-archive"))
    }

    @Test("skips extension targets the provider cannot resolve, instead of crashing")
    func skipsUnresolvableTargets() {
        // An empty extension map: every curated `.ext` target fails to
        // resolve to a UTI and must be dropped, not crash the scan.
        // (`.uti` and `.urlScheme` targets resolve unconditionally — see
        // `Engine.resolve` — so they are expected to still show up, just
        // with no current app.)
        let scanner = scanner { _ in }

        let unresolvedExtensions = scanner.scan().filter {
            if case .ext = $0.target { return true }
            return false
        }
        #expect(unresolvedExtensions.isEmpty)
    }

    @Test("returns no default when the provider has none, without treating it as an error")
    func noDefaultIsNilNotCrash() {
        let scanner = scanner { provider in
            provider.extensionMap = ["md": "net.daringfireball.markdown"]
            provider.declaredTypes = ["net.daringfireball.markdown"]
            // No typeDefaults entry: nothing currently opens .md.
        }

        let record = scanner.scan().first { $0.target == .ext("md") }

        #expect(record != nil)
        #expect(record?.currentApp == nil)
        #expect(record?.availableApps.isEmpty == true)
    }
}
