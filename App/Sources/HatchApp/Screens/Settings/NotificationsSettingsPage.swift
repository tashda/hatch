import SwiftUI
import AppKit
import HatchCore
import HatchSync

/// Settings, Notifications (design-review/settings-pages.html).
struct NotificationsSettingsPage: View {
    var body: some View {
        SettingsPageForm(section: "Notifications", footer: nil) {
            Text("Coming next.").foregroundStyle(.secondary)
        }
    }
}
