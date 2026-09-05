@testable import AssociationDoctor

/// In-memory `RawDefaultHandlerProviding` stand-in, so `DiagnosticEngine`
/// tests never call the real LaunchServices C API.
struct FakeRawDefaultHandlerProvider: RawDefaultHandlerProviding {
    var typeBundleIDs: [String: String] = [:]
    var schemeBundleIDs: [String: String] = [:]

    func rawDefaultBundleID(forContentType uti: String) -> String? { typeBundleIDs[uti] }
    func rawDefaultBundleID(forScheme scheme: String) -> String? { schemeBundleIDs[scheme] }
}
