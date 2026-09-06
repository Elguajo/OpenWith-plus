import SwiftUI

/// §22. MVP settings only — no automatic repair toggle: repair always
/// needs explicit user action (§16, §22).
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Scan on launch", isOn: $appState.settings.scanOnLaunch)
                Toggle("Include URL schemes", isOn: $appState.settings.includeURLSchemes)
                Toggle("Include types declared by system apps", isOn: $appState.settings.includeSystemFileTypes)
            } header: {
                Text("Scanning")
            } footer: {
                Text("System apps live in /System/Applications. Turning this off shrinks the scan to the apps you installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recommendations") {
                Toggle("Show low-confidence recommendations", isOn: $appState.settings.showLowConfidenceRecommendations)
            }

            Section("Advanced") {
                Toggle("Show advanced UTI identifiers", isOn: $appState.settings.showAdvancedUTIIdentifiers)
            }

            Section {
                Toggle(
                    "Allow changing protected system associations",
                    isOn: $appState.settings.allowProtectedAssociationChanges)
            } header: {
                Text("Risky")
            } footer: {
                Label(
                    "Applications, installers, disk images, macOS components and Apple's internal URL schemes are left alone by default. Turning this on lets Fix and Repair Plans change them, which can stop apps from launching or software from installing.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(maxWidth: 480)
        // Unlike every other setting here, this one only takes effect while
        // scanning — leaving it to the next manual scan made the toggle look
        // like it did nothing at all.
        .onChange(of: appState.settings.includeSystemFileTypes) {
            guard appState.lastScanDate != nil else { return }
            Task { await appState.scan() }
        }
    }
}
