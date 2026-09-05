import OpenWithCore

/// In-memory `LaunchServicesProviding` stand-in so tests never touch the
/// machine's real defaults (mirrors OpenWithCore's own internal
/// `FakeProvider`, which isn't exposed outside its test target).
struct FakeLaunchServicesProvider: LaunchServicesProviding {
    var apps: [AppInfo] = []
    var extensionMap: [String: String] = [:]
    var declaredTypes: Set<String> = []
    var typeDefaults: [String: String] = [:]
    var typeHandlers: [String: [String]] = [:]
    var schemeDefaults: [String: String] = [:]
    var schemeHandlers: [String: [String]] = [:]
    var descriptions: [String: String] = [:]

    func defaultApp(forContentType uti: String, role: Role) -> AppInfo? {
        typeDefaults[uti].flatMap { id in apps.first { $0.bundleID == id } }
    }

    func defaultApp(forScheme scheme: String) -> AppInfo? {
        schemeDefaults[scheme].flatMap { id in apps.first { $0.bundleID == id } }
    }

    func handlers(forContentType uti: String, role: Role) -> [AppInfo] {
        (typeHandlers[uti] ?? []).compactMap { id in apps.first { $0.bundleID == id } }
    }

    func handlers(forScheme scheme: String) -> [AppInfo] {
        (schemeHandlers[scheme] ?? []).compactMap { id in apps.first { $0.bundleID == id } }
    }

    func setDefault(bundleID: String, forContentType uti: String, role: Role) async throws {}
    func setDefault(bundleID: String, forScheme scheme: String) async throws {}

    func app(forBundleID bundleID: String) -> AppInfo? {
        apps.first { $0.bundleID == bundleID }
    }

    func app(atPath path: String) -> AppInfo? {
        apps.first { $0.path == path }
    }

    func app(named name: String) -> AppInfo? {
        apps.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func contentType(forExtension ext: String) -> String? { extensionMap[ext] }
    func contentType(forFileAt path: String) -> String? { nil }
    func localizedDescription(forContentType uti: String) -> String? { descriptions[uti] }
    func isDeclared(contentType uti: String) -> Bool { declaredTypes.contains(uti) }
}
