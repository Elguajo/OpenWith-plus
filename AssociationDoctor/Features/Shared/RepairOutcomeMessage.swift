import Foundation

/// Shared by every screen that can trigger a single-item repair (Problems,
/// All Associations, Applications) — one place for the user-facing wording
/// of §15/§16's "never assume success" outcomes.
extension RepairOutcome {
    var displayMessage: String {
        switch self {
        case .applied(let app): return "\(app.name) is now the default."
        case .alreadySet(let app): return "\(app.name) was already the default."
        case .notConfirmed(let desired):
            return
                "macOS didn't confirm the change to \(desired.name) — you may have declined the system dialog, or it's still pending your answer."
        case .failed(let message): return "Couldn't change the default: \(message)"
        }
    }
}

struct RepairOutcomeMessage: Identifiable {
    let id = UUID()
    let text: String

    init(_ outcome: RepairOutcome) {
        self.text = outcome.displayMessage
    }
}
