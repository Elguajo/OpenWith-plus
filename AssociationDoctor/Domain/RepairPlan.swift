import OpenWithCore

/// One pending default-app change, shown to the user for review before
/// RepairService (Phase 7) applies it (§15).
struct RepairAction: Sendable, Hashable {
    let target: Target
    let currentApp: AppInfo?
    let desiredApp: AppInfo
}

/// A reviewed batch of changes. Applied sequentially, one macOS
/// confirmation dialog at a time (§16) — never assumed to succeed without
/// a read-back.
struct RepairPlan: Sendable {
    let changes: [RepairAction]
}
