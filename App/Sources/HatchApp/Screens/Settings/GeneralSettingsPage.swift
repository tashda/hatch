import SwiftUI
import AppKit
import HatchCore
import HatchSync

/// Settings, General (design-review/settings-pages.html).
struct GeneralSettingsPage: View {
    @AppStorage(DecideFeedback.hapticsKey) private var haptics = true
    @AppStorage(DecideFeedback.soundKey) private var sound = false

    var body: some View {
        SettingsPageForm(section: "Decide", footer: "What you feel and hear when you decide a card in a Decide session (decision DC7).") {
            Toggle("Trackpad tap", isOn: $haptics)
            Toggle("Sound", isOn: $sound)
        }
    }
}
