import SwiftUI

/// Temporary proof-of-concept view: prove the scan → diagnose pipeline
/// reaches LaunchServices before recommendations, repair, or the real
/// Dashboard exist.
struct ScanDebugView: View {
    @State private var records: [AssociationRecord] = []
    @State private var isScanning = false
    @State private var hasScanned = false

    private let scanner: AssociationScanner
    private let diagnosticEngine: DiagnosticEngine

    init() {
        let scanner = AssociationScanner()
        self.scanner = scanner
        self.diagnosticEngine = DiagnosticEngine(provider: scanner.engine.provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Association Doctor — Scan Debug")
                    .font(.headline)
                Spacer()
                Button(isScanning ? "Scanning…" : "Scan") {
                    scan()
                }
                .disabled(isScanning)
            }
            .padding()

            Divider()

            content
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    @ViewBuilder
    private var content: some View {
        if records.isEmpty {
            Spacer()
            Text(hasScanned ? "No file types found." : "Press Scan to inspect this Mac's file associations.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Spacer()
        } else {
            List(records) { record in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(record.localizedTypeName ?? record.target.value)
                            .font(.body.weight(.medium))
                        StatusBadge(status: record.status)
                    }
                    Text("\(record.target.description) · \(record.category.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Current: \(record.currentApp?.name ?? "none")  ·  Handlers: \(record.availableApps.count)")
                        .font(.caption)
                    if let recommendation = record.recommendation,
                        recommendation.suggestedApp.bundleID != record.currentApp?.bundleID
                    {
                        Text("Suggested: \(recommendation.suggestedApp.name) (\(recommendation.confidence.rawValue)) — \(recommendation.reasons.map(\.rawValue).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func scan() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = scanner.scan()
            let diagnosed = diagnosticEngine.diagnose(scanned)
            DispatchQueue.main.async {
                records = diagnosed
                isScanning = false
                hasScanned = true
            }
        }
    }
}

private struct StatusBadge: View {
    let status: AssociationStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .healthy: return .green
        case .suspicious: return .yellow
        case .broken: return .red
        case .changed: return .orange
        case .noDefault: return .secondary
        case .ignored: return .secondary
        }
    }
}
