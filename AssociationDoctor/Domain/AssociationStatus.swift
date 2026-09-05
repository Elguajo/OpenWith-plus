/// Health of one association, as the Diagnostic Engine (Phase 4) will
/// compute it (§5.2, §10). `broken` is a technical fact; `suspicious` is a
/// heuristic — the two must never be conflated (§43).
enum AssociationStatus: String, Sendable, Hashable, CaseIterable {
    case healthy
    case suspicious
    case broken
    case changed
    case noDefault
    case ignored
}
