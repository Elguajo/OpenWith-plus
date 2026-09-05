import Foundation

/// One diagnostic finding surfaced on the Problems screen (§5.3, §19).
struct Finding: Identifiable, Sendable {
    let id: UUID
    let severity: FindingSeverity
    let type: FindingType
    let title: String
    let description: String
    let association: AssociationRecord?
    let recommendation: Recommendation?

    init(
        id: UUID = UUID(),
        severity: FindingSeverity,
        type: FindingType,
        title: String,
        description: String,
        association: AssociationRecord? = nil,
        recommendation: Recommendation? = nil
    ) {
        self.id = id
        self.severity = severity
        self.type = type
        self.title = title
        self.description = description
        self.association = association
        self.recommendation = recommendation
    }
}

enum FindingSeverity: String, Sendable, Hashable, CaseIterable {
    case info
    case warning
    case critical
}

/// What kind of problem this is. Not a 1:1 mirror of `AssociationStatus`:
/// duplicate/legacy-app (§10.5) is informational and has no status of its
/// own.
enum FindingType: String, Sendable, Hashable, CaseIterable {
    case broken
    case noDefault
    case changed
    case suspicious
    case duplicateLegacyApp
}
