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
    /// True for OpenWithCore's hand-picked common types (§6.2 —
    /// `Curated.targets`, e.g. .rar/.zip/.mp4/.mp3), false for the long
    /// tail found only by scanning installed apps' own declarations
    /// (`Discovery`). Lets the UI default to the popular types people
    /// actually look for instead of 1000+ obscure ones (default `true`
    /// so existing call sites/tests that don't care about this still
    /// compile).
    let isCurated: Bool

    init(
        id: String, target: Target, uti: String?, localizedTypeName: String?, category: FileCategory,
        currentApp: AppInfo?, availableApps: [AppInfo], isCurated: Bool = true
    ) {
        self.id = id
        self.target = target
        self.uti = uti
        self.localizedTypeName = localizedTypeName
        self.category = category
        self.currentApp = currentApp
        self.availableApps = availableApps
        self.isCurated = isCurated
    }
}
