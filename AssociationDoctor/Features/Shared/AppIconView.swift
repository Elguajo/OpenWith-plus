import AppKit
import OpenWithCore
import SwiftUI

/// An installed app's real icon via `NSWorkspace` (§27) — no cached
/// duplicates of our own; `NSWorkspace` already caches by path.
struct AppIconView: View {
    let app: AppInfo?
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app?.path ?? ""))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// A small colored dot + label pairing (§17.1's "never color alone" rule)
/// for one `AssociationStatus`.
struct StatusBadge: View {
    let status: AssociationStatus

    var body: some View {
        Label(status.displayName, systemImage: status.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.tintColor.opacity(0.15), in: Capsule())
            .foregroundStyle(status.tintColor)
    }
}

extension RecommendationReason {
    /// Plain-language reason text for Problem cards (§5.4: a suggestion is
    /// never a black box).
    var displayText: String {
        switch self {
        case .categoryMatch: return "matches this file's category"
        case .topRankedBySystem: return "top-ranked by macOS"
        case .declaresExactUTI: return "declares exact support for this type"
        case .declaresExactExtension: return "declares exact support for this extension"
        case .preferredForRelatedFormats: return "already preferred for related formats"
        case .matchesBaseline: return "matches your saved baseline"
        case .systemUtilityForSystemType: return "system utility for a system type"
        case .categoryMismatch: return "category looks inconsistent"
        case .appMissing: return "app is not installed"
        case .weakHandlerMatch: return "only a weak, generic handler"
        }
    }
}

extension RecommendationConfidence {
    var displayName: String {
        switch self {
        case .low: return "low confidence"
        case .medium: return "medium confidence"
        case .high: return "high confidence"
        }
    }
}

extension AssociationStatus {
    var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .suspicious: return "Suspicious"
        case .broken: return "Broken"
        case .changed: return "Changed"
        case .noDefault: return "No Default"
        case .ignored: return "Ignored"
        }
    }

    var systemImage: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .suspicious: return "questionmark.circle.fill"
        case .broken: return "xmark.circle.fill"
        case .changed: return "arrow.triangle.2.circlepath.circle.fill"
        case .noDefault: return "circle.dashed"
        case .ignored: return "eye.slash.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .healthy: return .green
        case .suspicious: return .yellow
        case .broken: return .red
        case .changed: return .orange
        case .noDefault: return .secondary
        case .ignored: return .secondary
        }
    }
}
