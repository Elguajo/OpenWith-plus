import OpenWithCore

/// One scanned file type / URL scheme and what currently opens it (§5.1).
///
/// `status` and `recommendation` join this record once the Diagnostic
/// Engine (Phase 4) and Recommendation Engine (Phase 5) exist to compute
/// them — a scanner-only guess would just be redone there.
struct AssociationRecord: Identifiable, Hashable, Sendable {
    let id: String
    let target: Target
    let uti: String?
    let localizedTypeName: String?
    let category: FileCategory
    let currentApp: AppInfo?
    let availableApps: [AppInfo]
}
