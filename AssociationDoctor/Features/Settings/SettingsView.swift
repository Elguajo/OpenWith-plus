import SwiftUI

/// §22. MVP settings only — no automatic repair toggle: repair always
/// needs explicit user action (§16, §22).
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Scanning") {
                Toggle("Scan on launch", isOn: $appState.settings.scanOnLaunch)
                Toggle("Include URL schemes", isOn: $appState.settings.includeURLSchemes)
                Toggle("Include system file types", isOn: $appState.settings.includeSystemFileTypes)
            }

            Section("Recommendations") {
                Toggle("Show low-confidence recommendations", isOn: $appState.settings.showLowConfidenceRecommendations)
            }

            Section("Advanced") {
                Toggle("Show advanced UTI identifiers", isOn: $appState.settings.showAdvancedUTIIdentifiers)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(maxWidth: 480)
    }
}
