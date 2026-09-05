import OpenWithCore

/// One diagnosed file type / URL scheme: what currently opens it and
/// whether that's healthy (§5.1). Produced by `DiagnosticEngine` from a
/// `ScannedAssociation` — never constructed directly from a scan, so
/// `status` is never a guess.
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
    /// See `ScannedAssociation.isCurated`.
    let isCurated: Bool

    init(
        id: String, target: Target, uti: String?, localizedTypeName: String?, category: FileCategory,
        currentApp: AppInfo?, availableApps: [AppInfo], status: AssociationStatus, recommendation: Recommendation?,
        isCurated: Bool = true
    ) {
        self.id = id
        self.target = target
        self.uti = uti
        self.localizedTypeName = localizedTypeName
        self.category = category
        self.currentApp = currentApp
        self.availableApps = availableApps
        self.status = status
        self.recommendation = recommendation
        self.isCurated = isCurated
    }
}

extension AssociationRecord {
    /// Used to overlay `.ignored` (§23) on the presentation layer, without
    /// `DiagnosticEngine` — which has no notion of the user's session-local
    /// ignore list — ever needing to guess at that status itself.
    func withStatus(_ status: AssociationStatus) -> AssociationRecord {
        AssociationRecord(
            id: id, target: target, uti: uti, localizedTypeName: localizedTypeName, category: category,
            currentApp: currentApp, availableApps: availableApps, status: status, recommendation: recommendation,
            isCurated: isCurated)
    }
}
