import Foundation
import OpenWithCore
import Testing

@testable import AssociationDoctor

@Suite
struct BaselineStoreTests {
    private static let vscode = AppInfo(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", path: "/Applications/Visual Studio Code.app")
    /// `BaselineStore` stores `createdAt` at millisecond precision (see its
    /// doc comment) — a fixed, already-millisecond-aligned date so
    /// round-trip comparisons in these tests aren't chasing sub-millisecond
    /// jitter from a live `Date()`.
    private static let fixedDate = Date(timeIntervalSince1970: 1_725_000_000.500)

    /// A fresh, never-shared temp directory per test — never the real
    /// `~/Library/Application Support/AssociationDoctor` (see convention #2
    /// in the phase brief).
    private func store() -> (BaselineStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (BaselineStore(directory: directory), directory)
    }

    @Test("nothing saved yet loads as nil, not an error")
    func loadWithNoFileIsNil() {
        let (store, _) = store()
        #expect(store.load() == nil)
    }

    @Test("a saved baseline round-trips through disk unchanged")
    func saveThenLoadRoundTrips() throws {
        let (store, _) = store()
        let baseline = Baseline(
            id: UUID(), name: "My Mac", createdAt: Self.fixedDate,
            associations: [
                BaselineAssociation(uti: "public.zip-archive", extensionName: "zip", bundleID: Self.vscode.bundleID),
                BaselineAssociation(uti: nil, extensionName: "md", bundleID: "com.apple.TextEdit"),
            ])

        try store.save(baseline)
        let loaded = store.load()

        #expect(loaded == baseline)
    }

    @Test("saving creates the Application Support subdirectory on demand")
    func saveCreatesMissingDirectory() throws {
        let (store, directory) = store()
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        try store.save(Baseline(id: UUID(), name: "My Mac", createdAt: Self.fixedDate, associations: []))

        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("baseline.json").path))
    }

    @Test("updating an existing baseline overwrites it, not appends")
    func saveOverwritesPreviousBaseline() throws {
        let (store, _) = store()
        try store.save(Baseline(id: UUID(), name: "My Mac", createdAt: Self.fixedDate, associations: [
            BaselineAssociation(uti: nil, extensionName: "md", bundleID: "com.apple.TextEdit")
        ]))

        let updated = Baseline(id: UUID(), name: "My Mac", createdAt: Self.fixedDate, associations: [
            BaselineAssociation(uti: "public.zip-archive", extensionName: "zip", bundleID: Self.vscode.bundleID)
        ])
        try store.save(updated)

        #expect(store.load() == updated)
    }
}

@Suite
struct BaselineCapturingTests {
    private static let vscode = AppInfo(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", path: "/Applications/Visual Studio Code.app")
    private static let textEdit = AppInfo(bundleID: "com.apple.TextEdit", name: "TextEdit", path: "/System/Applications/TextEdit.app")

    private func record(target: Target, uti: String?, currentApp: AppInfo?) -> AssociationRecord {
        AssociationRecord(
            id: target.description, target: target, uti: uti, localizedTypeName: nil, category: .unknown,
            currentApp: currentApp, availableApps: [], status: .healthy, recommendation: nil)
    }

    @Test("captures one BaselineAssociation per record with a current app")
    func capturesCurrentApps() {
        let records = [
            record(target: .ext("zip"), uti: "public.zip-archive", currentApp: Self.vscode),
            record(target: .ext("md"), uti: "net.daringfireball.markdown", currentApp: Self.textEdit),
        ]

        let baseline = Baseline.capturing(name: "My Mac", from: records)

        #expect(baseline.name == "My Mac")
        #expect(baseline.associations.count == 2)
        #expect(baseline.associations.contains { $0.bundleID == Self.vscode.bundleID && $0.extensionName == "zip" })
        #expect(baseline.associations.contains { $0.bundleID == Self.textEdit.bundleID && $0.extensionName == "md" })
    }

    @Test("a record with no current app is skipped — nothing to pin down")
    func skipsRecordsWithNoCurrentApp() {
        let records = [record(target: .ext("md"), uti: nil, currentApp: nil)]

        let baseline = Baseline.capturing(name: "My Mac", from: records)

        #expect(baseline.associations.isEmpty)
    }

    @Test("a URL scheme target carries no extension, only the UTI/bundle")
    func urlSchemeHasNoExtension() {
        let records = [record(target: .urlScheme("mailto"), uti: nil, currentApp: Self.vscode)]

        let baseline = Baseline.capturing(name: "My Mac", from: records)

        #expect(baseline.associations.first?.extensionName == nil)
        #expect(baseline.associations.first?.bundleID == Self.vscode.bundleID)
    }
}
