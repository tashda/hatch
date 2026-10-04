import SwiftUI
import AppKit
import HatchCore
import HatchSync

/// Settings, Storage (was Local data; design-review/settings-pages.html). To be redesigned.
struct StorageSettingsPage: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        SettingsPageForm(section: "Local data", footer: "Hatch's database and working files stay on this Mac.") {
            LabeledContent("Hatch home") { Text(state.paths.root.path).textSelection(.enabled) }
            LabeledContent("Database") { Text(state.paths.database.path).textSelection(.enabled) }
        }
    }
}

