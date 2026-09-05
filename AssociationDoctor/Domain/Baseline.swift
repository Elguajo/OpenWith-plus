import Foundation

/// A saved snapshot of desired defaults (§13), the user's own source of
/// truth — takes priority over any heuristic (§43).
struct Baseline: Identifiable, Sendable, Hashable, Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let associations: [BaselineAssociation]
}

/// One saved association. `uti` and `extensionName` mirror the spec's JSON
/// example (§13), which carries both for readability; at least one
/// identifies the target.
struct BaselineAssociation: Sendable, Hashable, Codable {
    let uti: String?
    let extensionName: String?
    let bundleID: String
}
