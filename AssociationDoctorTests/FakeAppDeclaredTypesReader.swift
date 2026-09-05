import OpenWithCore

@testable import AssociationDoctor

/// In-memory `AppDeclaredTypesReading` stand-in, so `RecommendationEngine`
/// tests never read a real app bundle's Info.plist from disk.
struct FakeAppDeclaredTypesReader: AppDeclaredTypesReading {
    var typesByBundleID: [String: AppDeclaredTypes] = [:]

    func declaredTypes(for app: AppInfo) -> AppDeclaredTypes {
        typesByBundleID[app.bundleID] ?? AppDeclaredTypes()
    }
}
