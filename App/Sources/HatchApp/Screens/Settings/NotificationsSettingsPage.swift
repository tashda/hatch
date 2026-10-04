import SwiftUI
import AppKit
import UserNotifications
import HatchCore

/// Settings, Notifications (design-review/settings-pages.html, "Notifications (new)"): which events deserve a
/// notification and how they sound. Only things that need you or went wrong are on by default; every status change is
/// off. `NotificationCenterBridge` reads these switches before it posts anything.
struct NotificationsSettingsPage: View {
    @EnvironmentObject var state: AppState
    /// Whether macOS lets Hatch notify at all; nil until asked.
    @State private var allowed: Bool?

    var body: some View {
        Form {
            if allowed == false { offSection }

            Section {
                Toggle(isOn: state.flagBinding(Preference.notifyWaiting)) {
                    Text("A ticket waits for me")
                    Text("A choice, an answer or a Preview to verify")
                }
                Toggle("An agent hands in", isOn: state.flagBinding(Preference.notifyHandIn))
                Toggle("An agent stops or needs me", isOn: state.flagBinding(Preference.notifyAgentStops))
                // Hatch looks at CI only when asked (the footer, Previews); the switch is kept for when it watches.
                Toggle(isOn: state.flagBinding(Preference.notifyCI)) {
                    Text("CI fails on Hatch's branch")
                    Text("Used once Hatch watches CI")
                }
                Toggle("Sync or the notebook fails", isOn: state.flagBinding(Preference.notifySync))
                Toggle("Every status change", isOn: state.flagBinding(Preference.notifyEveryStatus))
            } header: {
                Text("Tell me when")
            }

            Section {
                Picker("Sound", selection: state.preferenceBinding(Preference.notifySound, default: NotificationSound.needsMe.rawValue)) {
                    ForEach(NotificationSound.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Group by project", isOn: state.flagBinding(Preference.notifyGroup))
            } header: {
                HStack {
                    Text("How")
                    Spacer()
                    Button("Send a Test") { NotificationCenterBridge.shared.sendTest() }
                        .buttonStyle(.link)
                        .disabled(Snapshots.demoMode || allowed == false)
                }
            } footer: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Hatch follows Focus and macOS notification settings.")
                    Button("Open Notification Settings…", action: openNotificationSettings).buttonStyle(.link)
                        .font(.callout)
                    Spacer(minLength: 0)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task { await readAuthorization() }
        // Turning notifications on happens in System Settings; look again when Hatch comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await readAuthorization() }
        }
    }

    /// One warning row when macOS has notifications turned off for Hatch, with the way to turn them on.
    private var offSection: some View {
        Section {
            LabeledContent {
                Button("Turn On…", action: openNotificationSettings)
            } label: {
                Label {
                    Text("Notifications are off for Hatch in System Settings")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.you)
                }
            }
        }
    }

    private func readAuthorization() async {
        guard NotificationCenterBridge.canNotify else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        allowed = settings.authorizationStatus != .denied
    }

    private func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier.map { "?id=\($0)" } ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}
