import SwiftUI

/// §21. The `Baseline` domain model exists (Phase 2), but saving/loading
/// one (`BaselineStore`) is Phase 8 — an honest empty state beats wiring
/// Save/Compare/Restore/Export against storage that isn't built yet.
struct ProfilesView: View {
    var body: some View {
        ContentUnavailableView(
            "No Baseline Saved",
            systemImage: "person.crop.rectangle.stack",
            description: Text("Saving, comparing, and restoring a baseline of your current defaults is coming in a later update.")
        )
        .navigationTitle("Profiles")
    }
}
