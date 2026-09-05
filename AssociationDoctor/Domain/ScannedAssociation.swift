import OpenWithCore

/// Raw output of `AssociationScanner`, before diagnosis (§7): what a target
/// currently resolves to, with no opinion yet about whether that's healthy.
/// `DiagnosticEngine` turns these into `AssociationRecord`s.
struct ScannedAssociation: Identifiable, Hashable, Sendable {
    let id: String
    let target: Target
    let uti: String?
    let localizedTypeName: String?
    let category: FileCategory
    let currentApp: AppInfo?
    let availableApps: [AppInfo]
}
