import OpenWithCore

/// `FakeLaunchServicesProvider`'s `setDefault` is a deliberate no-op (fine
/// for every test so far — nothing exercised the write path before
/// `RepairService`). Testing a real apply → read-back cycle needs a fake
/// where writes actually stick, which needs interior mutability the
/// protocol's non-mutating `setDefault` can't get from a plain struct —
/// same reason OpenWithCore's own internal test fake is a class.
///
/// `@unchecked Sendable`: a test double touched strictly sequentially
/// within one test, never concurrently.
final class FakeWritableLaunchServicesProvider: LaunchServicesProviding, @unchecked Sendable {
    var apps: [AppInfo] = []
    var typeDefaults: [String: String] = [:]
    var extensionMap: [String: String] = [:]
    var declineWrites = false
    private(set) var writeLog: [String] = []

    func defaultApp(forContentType uti: String, role: Role) -> AppInfo? {
        typeDefaults[uti].flatMap { id in apps.first { $0.bundleID == id } }
    }

    func defaultApp(forScheme scheme: String) -> AppInfo? { nil }
    func handlers(forContentType uti: String, role: Role) -> [AppInfo] { apps }
    func handlers(forScheme scheme: String) -> [AppInfo] { [] }

    func setDefault(bundleID: String, forContentType uti: String, role: Role) async throws {
        writeLog.append("\(uti)|\(role.rawValue)=\(bundleID)")
        guard !declineWrites else { return }
        typeDefaults[uti] = bundleID
    }

    func setDefault(bundleID: String, forScheme scheme: String) async throws {}

    func app(forBundleID bundleID: String) -> AppInfo? { apps.first { $0.bundleID == bundleID } }
    func app(atPath path: String) -> AppInfo? { apps.first { $0.path == path } }
    func app(named name: String) -> AppInfo? { apps.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
    func contentType(forExtension ext: String) -> String? { extensionMap[ext] }
    func contentType(forFileAt path: String) -> String? { nil }
    func localizedDescription(forContentType uti: String) -> String? { nil }
    func isDeclared(contentType uti: String) -> Bool { true }
}
