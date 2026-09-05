import OpenWithCore

/// One diagnosed file type / URL scheme: what currently opens it and
/// whether that's healthy (§5.1). Produced by `DiagnosticEngine` from a
/// `ScannedAssociation` — never constructed directly from a scan, so
/// `status` is never a guess.
///
/// `recommendation` stays `nil` until the Recommendation Engine (Phase 5)
/// exists to compute it.
struct AssociationRecord: Identifiable, Hashable, Sendable {
    let id: String
    let target: Target
    let uti: String?
    let localizedTypeName: String?
    let category: FileCategory
    let currentApp: AppInfo?
    let availableApps: [AppInfo]
    let status: AssociationStatus
    let recommendation: Recommendation?
}
