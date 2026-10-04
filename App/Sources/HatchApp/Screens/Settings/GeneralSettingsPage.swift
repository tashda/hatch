import SwiftUI
import AppKit
import HatchCore
import HatchSync

/// Settings, General (design-review/settings-pages.html).
struct GeneralSettingsPage: View {
    var body: some View {
        SettingsPageForm(section: "General", footer: nil) {
            Text("Coming next.").foregroundStyle(.secondary)
        }
    }
}
