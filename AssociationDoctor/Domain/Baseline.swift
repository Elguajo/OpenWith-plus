import Foundation
import OpenWithCore

/// A saved snapshot of desired defaults (§13), the user's own source of
/// truth — takes priority over any heuristic (§43).
struct Baseline: Identifiable, Sendable, Hashable, Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let associations: [BaselineAssociation]
}

extension Baseline {
    /// Snapshots the current scan's apps as a new baseline — the "Save
    /// Current Defaults" / "Update Baseline" action (§13/§21). Only records
    /// with a current app are captured; there's nothing to pin down for a
    /// type nobody has set a default for yet.
    static func capturing(name: String, from records: [AssociationRecord]) -> Baseline {
        let associations = records.compactMap { record -> BaselineAssociation? in
            guard let currentApp = record.currentApp else { return nil }
            var extensionName: String?
            if case .ext(let ext) = record.target { extensionName = ext }
            return BaselineAssociation(uti: record.uti, extensionName: extensionName, bundleID: currentApp.bundleID)
        }
        return Baseline(id: UUID(), name: name, createdAt: Date(), associations: associations)
    }

    /// The bundle ID this baseline expects for `record`, if it has an
    /// opinion — the same matching rule
    /// `RecommendationEngine.expectedBundleID` applies to a
    /// `ScannedAssociation`, restated here for the already-diagnosed
    /// `AssociationRecord` that Profiles' Compare/Restore only has access to.
    func expectedBundleID(for record: AssociationRecord) -> String? {
        associations.first { entry in
            if let uti = record.uti, let entryUTI = entry.uti, uti == entryUTI { return true }
            if case .ext(let ext) = record.target, entry.extensionName == ext { return true }
            return false
        }?.bundleID
    }
}

/// One saved association. `uti` and `extensionName` mirror the spec's JSON
/// example (§13), which carries both for readability; at least one
/// identifies the target.
struct BaselineAssociation: Sendable, Hashable, Codable {
    let uti: String?
    let extensionName: String?
    let bundleID: String
}
