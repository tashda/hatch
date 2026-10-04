import SwiftUI
import AppKit
import HatchCore
import HatchSync

/// Settings, Usage (design-review/settings-pages.html).
struct UsageSettingsPage: View {
    var body: some View {
        SettingsPageForm(section: "Usage", footer: nil) {
            Text("Coming next.").foregroundStyle(.secondary)
        }
    }
}
