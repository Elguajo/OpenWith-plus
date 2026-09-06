import Foundation
import SwiftUI

/// Shared by every screen that can trigger a repair — single-item
/// (Problems, All Associations, Applications) or batch (`RepairPlanSheet`,
/// Phase 7) — one place for the user-facing wording of §15/§16's "never
/// assume success" outcomes.
extension RepairOutcome {
    var displayMessage: String {
        switch self {
        case .applied(let app): return "\(app.name) is now the default."
        case .alreadySet(let app): return "\(app.name) was already the default."
        case .notConfirmed(let desired):
            return
                "macOS didn't confirm the change to \(desired.name) — you may have declined the system dialog, or it's still pending your answer."
        case .failed(let message): return "Couldn't change the default: \(message)"
        case .notPermitted(let reason):
            return
                "This association is protected. \(reason.explanation) You can allow changes like this in Settings."
        }
    }

    /// Short label for a compact per-row badge, e.g. in `RepairPlanSheet`'s
    /// result list — `displayMessage` is the sentence, this is the chip.
    var shortLabel: String {
        switch self {
        case .applied: return "Applied"
        case .alreadySet: return "Already Set"
        case .notConfirmed: return "Declined"
        case .failed: return "Failed"
        case .notPermitted: return "Protected"
        }
    }

    var systemImage: String {
        switch self {
        case .applied: return "checkmark.circle.fill"
        case .alreadySet: return "checkmark.circle"
        case .notConfirmed: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .notPermitted: return "lock.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .applied: return .green
        case .alreadySet: return .secondary
        case .notConfirmed: return .orange
        case .failed: return .red
        case .notPermitted: return .secondary
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

/// Same visual language as `StatusBadge` (`AppIconView.swift`) — a colored
/// capsule pairing an icon with text, never color alone (§17.1) — applied
/// to a repair result instead of an association status.
struct RepairOutcomeBadge: View {
    let outcome: RepairOutcome

    var body: some View {
        Label(outcome.shortLabel, systemImage: outcome.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(outcome.tintColor.opacity(0.15), in: Capsule())
            .foregroundStyle(outcome.tintColor)
    }
}
