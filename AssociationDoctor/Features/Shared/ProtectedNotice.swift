import SwiftUI

/// Why a repair control is unavailable, said out loud. A disabled button
/// with no explanation reads as a bug; this is the same "never a black
/// box" rule the Recommendation Engine follows (§5.4), applied to a
/// refusal instead of a suggestion.
struct ProtectedNotice: View {
    let reason: ProtectionReason

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lock.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Protected by default")
                    .fontWeight(.medium)
                Text(reason.explanation)
                Text("Settings → Risky → Allow changing protected system associations")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// The compact form for dense rows (All Associations, an app's type list),
/// where the full explanation belongs in a tooltip instead of the layout.
struct ProtectedBadge: View {
    let reason: ProtectionReason

    var body: some View {
        Label("Protected", systemImage: "lock.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.6), in: Capsule())
            .foregroundStyle(.secondary)
            .help(reason.explanation)
    }
}
