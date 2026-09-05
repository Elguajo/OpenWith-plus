import OpenWithCore

/// A suggested replacement app for an association, with an explainable
/// trail of reasons (§5.4) — the Recommendation Engine (Phase 5) must never
/// be a black box.
struct Recommendation: Sendable, Hashable {
    let suggestedApp: AppInfo
    let score: Double
    let confidence: RecommendationConfidence
    let reasons: [RecommendationReason]
}

/// MVP rule (§11.2): `low` shows options only, `medium` shows the
/// recommendation, `high` additionally allows One-click Fix.
enum RecommendationConfidence: String, Sendable, Hashable, CaseIterable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// One scoring signal from §11.1, positive or negative.
enum RecommendationReason: String, Sendable, Hashable, CaseIterable {
    case categoryMatch
    case topRankedBySystem
    case declaresExactUTI
    case declaresExactExtension
    case preferredForRelatedFormats
    case matchesBaseline
    case systemUtilityForSystemType
    case categoryMismatch
    case appMissing
    case weakHandlerMatch
}
