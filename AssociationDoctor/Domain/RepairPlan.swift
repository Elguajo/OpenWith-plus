import Foundation
import OpenWithCore

/// One pending default-app change, shown to the user for review before
/// RepairService applies it (§15). `localizedTypeName` is carried along
/// purely for display — Review shouldn't have to walk back to the source
/// `AssociationRecord` just to show a readable row.
struct RepairAction: Sendable, Hashable {
    let target: Target
    let localizedTypeName: String?
    let currentApp: AppInfo?
    let desiredApp: AppInfo
}

/// A reviewed batch of changes (Phase 7). Applied sequentially, one macOS
/// confirmation dialog at a time (§16) — never assumed to succeed without
/// a read-back. `id` exists only so a plan can be handed to `.sheet(item:)`.
struct RepairPlan: Identifiable, Sendable {
    let id = UUID()
    let changes: [RepairAction]
}

extension RepairPlan {
    /// Builds a batch from every record `desiredApp` has an opinion on —
    /// Problems' "Fix All", Dashboard's "Fix N Issues" and Profiles'
    /// "Restore" all start here. Records it returns `nil` for are silently
    /// skipped: there's nothing this plan could safely set for them.
    ///
    /// `desiredApp` is a closure rather than something derived from
    /// `record.recommendation` so the decision stays in one place —
    /// `AppState.desiredApp`, which puts the saved baseline ahead of the
    /// heuristic (§43), respects the low-confidence display setting
    /// (§11.2), and refuses protected system associations.
    static func build(
        from records: [AssociationRecord], desiredApp: (AssociationRecord) -> AppInfo?
    ) -> RepairPlan {
        let changes = records.compactMap { record -> RepairAction? in
            guard let app = desiredApp(record) else { return nil }
            return RepairAction(
                target: record.target, localizedTypeName: record.localizedTypeName,
                currentApp: record.currentApp, desiredApp: app)
        }
        return RepairPlan(changes: changes)
    }
}
