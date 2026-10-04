import SwiftUI
import AppKit
import ServiceManagement
import HatchCore

/// Settings, General (design-review/settings-pages.html, "General (new)"): how the app looks, what happens when it
/// opens, the Dock badge and the menu bar item, and how tickets are made and dropped. One grouped Form; every row is a
/// label and one value, saved as it changes (`Preference`).
struct GeneralSettingsPage: View {
    @EnvironmentObject var state: AppState
    @State private var loginStatus: SMAppService.Status = .notRegistered

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: state.preferenceBinding(Preference.appearance, default: AppearanceChoice.system.rawValue)) {
                    ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }

            startSection

            Section {
                Picker("Dock badge", selection: state.preferenceBinding(Preference.dockBadge, default: "waiting")) {
                    Text("Tickets waiting for you").tag("waiting")
                    Text("Off").tag("off")
                }
                Toggle(isOn: state.flagBinding(Preference.menuBar)) {
                    Text("Show in the menu bar")
                    Text("Agents and status, like the footer")
                }
            } header: {
                Text("Dock and menu bar")
            }

            Section {
                Toggle("Ask before dropping a ticket", isOn: state.flagBinding(Preference.confirmDrop))
                Picker("New ticket type", selection: state.preferenceBinding(Preference.newTicketType, default: "")) {
                    Text("Ask me").tag("")
                    Divider()
                    ForEach(TicketType.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
            } header: {
                Text("Tickets")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear(perform: readLoginStatus)
        // Approving Hatch in System Settings happens outside the app; look again when it comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in readLoginStatus() }
    }

    private var startSection: some View {
        Section {
            Toggle("Open Hatch at login", isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                                                       set: setOpenAtLogin))
            Picker("When Hatch opens", selection: state.preferenceBinding(Preference.openTo, default: "desk")) {
                Text("The Desk").tag("desk")
                Text("The last page").tag("last")
            }
            Picker("Project on opening", selection: state.preferenceBinding(Preference.openProject, default: "last")) {
                Text("The last one").tag("last")
                Text("All projects").tag("all")
            }
        } header: {
            Text("Start")
        } footer: {
            if loginStatus == .requiresApproval {
                HStack(alignment: .top) {
                    Text("macOS asks you to allow Hatch in Login Items before it opens at login.")
                    Spacer(minLength: 16)
                    Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
        }
    }

    private func readLoginStatus() {
        loginStatus = SMAppService.mainApp.status
    }

    /// Registers or removes Hatch as a login item. Snapshot and demo runs only show the switch, so a test build is never
    /// added to the owner's login items.
    private func setOpenAtLogin(_ on: Bool) {
        guard !Snapshots.demoMode else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            state.errorMessage = "Open Hatch at login: \(error.localizedDescription)"
        }
        readLoginStatus()
    }
}
