import SwiftUI

struct RootView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $appState.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationTitle("Association Doctor")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            NavigationStack {
                detail
            }
        }
        .environmentObject(appState)
        .task {
            if appState.settings.scanOnLaunch, appState.lastScanDate == nil {
                await appState.scan()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.selectedSection ?? .dashboard {
        case .dashboard: DashboardView()
        case .problems: ProblemsView()
        case .allAssociations: AllAssociationsView()
        case .applications: ApplicationsView()
        case .profiles: ProfilesView()
        case .settings: SettingsView()
        }
    }
}
