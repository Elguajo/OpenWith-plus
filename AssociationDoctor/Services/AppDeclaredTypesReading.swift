import Foundation
import OpenWithCore

/// The document types and extensions one specific app declares via its
/// `CFBundleDocumentTypes` — raw material for the Recommendation Engine's
/// "declares exact UTI/extension" and "category matches" signals (§11.1).
///
/// OpenWithCore's `Discovery` only exposes a directory-wide *merged* target
/// list (for building the curated table), not a per-app declared-types
/// profile — this is a small local adapter reading the same Info.plist
/// keys `Discovery` reads internally, scoped to one app.
struct AppDeclaredTypes: Sendable, Hashable {
    var utis: Set<String> = []
    var extensions: Set<String> = []
}

protocol AppDeclaredTypesReading: Sendable {
    func declaredTypes(for app: AppInfo) -> AppDeclaredTypes
}

struct BundleAppDeclaredTypesReader: AppDeclaredTypesReading {
    func declaredTypes(for app: AppInfo) -> AppDeclaredTypes {
        guard let info = Bundle(url: URL(fileURLWithPath: app.path))?.infoDictionary else {
            return AppDeclaredTypes()
        }

        var utis: Set<String> = []
        var extensions: Set<String> = []
        for documentType in info["CFBundleDocumentTypes"] as? [[String: Any]] ?? [] {
            for uti in documentType["LSItemContentTypes"] as? [String] ?? [] where !uti.hasPrefix("dyn.") {
                utis.insert(uti)
            }
            for ext in documentType["CFBundleTypeExtensions"] as? [String] ?? [] where ext != "*" {
                extensions.insert(ext.lowercased())
            }
        }
        return AppDeclaredTypes(utis: utis, extensions: extensions)
    }
}
