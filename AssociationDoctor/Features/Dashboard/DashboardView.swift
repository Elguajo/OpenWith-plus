import SwiftUI

/// §18. The 5-second read: is anything wrong, and how much.
struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if appState.lastScanDate == nil && !appState.isScanning {
                    emptyState
                } else {
                    scoreSection
                    breakdownSection
                    Button("Review Problems") {
                        appState.selectedSection = .problems
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.healthScore.scannedCount == 0 || problemCount == 0)

                    lastScanFooter
                }
            }
            .padding(32)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await appState.scan() }
                } label: {
                    if appState.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Scan", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(appState.isScanning)
            }
        }
    }

    private var problemCount: Int {
        let score = appState.healthScore
        return score.suspiciousCount + score.brokenCount + score.changedCount + score.noDefaultCount
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to Association Doctor")
                .font(.title2.weight(.semibold))
            Text("We'll scan the file types known on this Mac and show which apps currently open them. Nothing will be changed without your approval.")
                .foregroundStyle(.secondary)
            Button("Scan My Mac") {
                Task { await appState.scan() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isScanning)
        }
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Association Health")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(appState.healthScore.score)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                Text("%")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\(appState.healthScore.scannedCount) file types scanned")
                .foregroundStyle(.secondary)
        }
    }

    private var breakdownSection: some View {
        let score = appState.healthScore
        return VStack(alignment: .leading, spacing: 10) {
            breakdownRow(.healthy, count: score.healthyCount)
            breakdownRow(.suspicious, count: score.suspiciousCount)
            breakdownRow(.broken, count: score.brokenCount)
            breakdownRow(.changed, count: score.changedCount)
            breakdownRow(.noDefault, count: score.noDefaultCount)
            if score.ignoredCount > 0 {
                breakdownRow(.ignored, count: score.ignoredCount)
            }
        }
    }

    private func breakdownRow(_ status: AssociationStatus, count: Int) -> some View {
        HStack {
            Label(status.displayName, systemImage: status.systemImage)
                .foregroundStyle(status.tintColor)
            Spacer()
            Text("\(count)")
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private var lastScanFooter: some View {
        Group {
            if let lastScanDate = appState.lastScanDate {
                Text("Last scan: \(lastScanDate, format: .relative(presentation: .named))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
