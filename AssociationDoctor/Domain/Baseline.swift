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
            var scheme: String?
            switch record.target {
            case .ext(let ext): extensionName = ext
            case .urlScheme(let value): scheme = value
            case .uti, .file: break
            }
            let entry = BaselineAssociation(
                uti: record.uti, extensionName: extensionName, scheme: scheme, bundleID: currentApp.bundleID)
            // An entry that identifies nothing can never be matched back to a
            // record, so saving it would only bloat the file with rows
            // Compare/Restore must ignore.
            return entry.identifiesATarget ? entry : nil
        }
        return Baseline(id: UUID(), name: name, createdAt: Date(), associations: associations)
    }

    /// The bundle ID this baseline expects for a target, if it has an
    /// opinion. Single matching rule for the whole app: `DiagnosticEngine`
    /// (via `RecommendationEngine.expectedBundleID`) reaches it with a
    /// `ScannedAssociation`, Profiles' Compare/Restore with an
    /// already-diagnosed `AssociationRecord` — restating it per caller is
    /// how URL schemes silently fell out of Compare/Restore before.
    func expectedBundleID(forUTI uti: String?, target: Target) -> String? {
        associations.first { $0.matches(uti: uti, target: target) }?.bundleID
    }

    func expectedBundleID(for record: AssociationRecord) -> String? {
        expectedBundleID(forUTI: record.uti, target: record.target)
    }

    func expectedBundleID(for scanned: ScannedAssociation) -> String? {
        expectedBundleID(forUTI: scanned.uti, target: scanned.target)
    }
}

/// One saved association. `uti`, `extensionName` and `scheme` mirror the
/// spec's JSON example (§13), which carries the readable form alongside the
/// UTI; at least one of them identifies the target.
///
/// `scheme` is what a URL-scheme target is keyed on: it has no UTI and no
/// extension, so without it a saved scheme default was an anonymous row
/// nothing could ever match (and Compare/Restore silently skipped every
/// scheme). Decoding a baseline written before `scheme` existed still
/// works — the key is simply absent.
struct BaselineAssociation: Sendable, Hashable, Codable {
    let uti: String?
    let extensionName: String?
    let scheme: String?
    let bundleID: String

    init(uti: String?, extensionName: String?, scheme: String? = nil, bundleID: String) {
        self.uti = uti
        self.extensionName = extensionName
        self.scheme = scheme
        self.bundleID = bundleID
    }

    var identifiesATarget: Bool {
        uti != nil || extensionName != nil || scheme != nil
    }

    func matches(uti recordUTI: String?, target: Target) -> Bool {
        if let recordUTI, let uti, recordUTI == uti { return true }
        if case .ext(let ext) = target, extensionName == ext { return true }
        if case .urlScheme(let value) = target, scheme == value { return true }
        return false
    }
}
