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

    @Test("nothing saved yet loads as empty, not an error")
    func loadWithNoFileIsEmpty() {
        let (store, _) = store()
        #expect(store.load() == .empty)
    }

    @Test("an unreadable baseline is reported and kept, never treated as absent")
    func loadWithCorruptFileIsReported() throws {
        let (store, directory) = store()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("baseline.json")
        try Data("{ this is not the baseline you are looking for".utf8).write(to: fileURL)

        let result = store.load()

        guard case .unreadable(let backupURL) = result else {
            Issue.record("expected .unreadable, got \(result)")
            return
        }
        // The bad file is preserved under a new name, so the next save
        // (which writes baseline.json) cannot destroy it.
        #expect(backupURL != nil)
        #expect(FileManager.default.fileExists(atPath: backupURL!.path))
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
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

        #expect(loaded == .loaded(baseline))
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

        #expect(store.load() == .loaded(updated))
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

    @Test("a URL scheme target is saved under its scheme, not as an anonymous row")
    func urlSchemeIsSavedByScheme() {
        let records = [record(target: .urlScheme("mailto"), uti: nil, currentApp: Self.vscode)]

        let baseline = Baseline.capturing(name: "My Mac", from: records)

        #expect(baseline.associations.first?.extensionName == nil)
        #expect(baseline.associations.first?.scheme == "mailto")
        #expect(baseline.associations.first?.bundleID == Self.vscode.bundleID)
        // The point of storing it: Compare/Restore can find it again.
        #expect(baseline.expectedBundleID(for: records[0]) == Self.vscode.bundleID)
    }

    @Test("a saved scheme is matched back by scheme, and never by a different one")
    func schemeMatchingIsExact() {
        let baseline = Baseline.capturing(
            name: "My Mac",
            from: [
                record(target: .urlScheme("mailto"), uti: nil, currentApp: Self.vscode),
                record(target: .urlScheme("ssh"), uti: nil, currentApp: Self.textEdit),
            ])

        #expect(
            baseline.expectedBundleID(forUTI: nil, target: .urlScheme("ssh")) == Self.textEdit.bundleID)
        #expect(baseline.expectedBundleID(forUTI: nil, target: .urlScheme("ftp")) == nil)
    }

    @Test("a record that identifies nothing is never saved")
    func skipsUnidentifiableRecords() {
        let records = [record(target: .file("/tmp/x"), uti: nil, currentApp: Self.vscode)]

        #expect(Baseline.capturing(name: "My Mac", from: records).associations.isEmpty)
    }

    @Test("a baseline written before schemes existed still decodes")
    func decodesLegacyEntryWithoutScheme() throws {
        let json = """
            {"associations":[{"bundleID":"com.microsoft.VSCode","extensionName":"md"}],\
            "createdAt":1700000000000,"id":"\(UUID().uuidString)","name":"My Mac"}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            Date(timeIntervalSince1970: Double(try decoder.singleValueContainer().decode(Int64.self)) / 1000)
        }

        let baseline = try decoder.decode(Baseline.self, from: Data(json.utf8))

        #expect(baseline.associations.first?.scheme == nil)
        #expect(baseline.expectedBundleID(forUTI: nil, target: .ext("md")) == Self.vscode.bundleID)
    }
}
