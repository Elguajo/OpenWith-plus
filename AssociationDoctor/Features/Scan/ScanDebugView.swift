import SwiftUI

/// Temporary Phase 1 proof-of-concept view: prove the scanner reaches
/// LaunchServices before any diagnostics, recommendations or the real
/// Dashboard exist.
struct ScanDebugView: View {
    @State private var records: [AssociationRecord] = []
    @State private var isScanning = false
    @State private var hasScanned = false

    private let scanner = AssociationScanner()

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
                    Text(record.localizedTypeName ?? record.target.value)
                        .font(.body.weight(.medium))
                    Text("\(record.target.description) · \(record.category.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Current: \(record.currentApp?.name ?? "none")  ·  Handlers: \(record.availableApps.count)")
                        .font(.caption)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func scan() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = scanner.scan()
            DispatchQueue.main.async {
                records = result
                isScanning = false
                hasScanned = true
            }
        }
    }
}
