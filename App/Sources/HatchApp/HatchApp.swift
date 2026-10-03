import SwiftUI
import HatchCore

@main
struct HatchApp: App {
    @StateObject private var state = (Snapshots.folder == nil && !Snapshots.demoMode) ? AppState.live() : Snapshots.demoState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1280, minHeight: 680)
                .task {
                    if let folder = Snapshots.folder {
                        await Snapshots.run(state: state, into: folder)
                    } else if !Snapshots.demoMode {
                        state.startServices()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    Snapshots.restoreDemoPreferences()
                    state.stopServices()
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1500, height: 920)
        .commands {
            HatchCommands(state: state)
        }

        // A regular window lets NavigationSplitView place its sidebar toggle in the titlebar.
        Window("Settings", id: "settings") {
            SettingsView().environmentObject(state)
        }
        .defaultSize(width: 1040, height: 720)
    }
}

/// Menu commands and shortcuts from the design: New ticket (cmd-N), Search (cmd-K), Ask (opt-cmd-A).
struct HatchCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: "settings") }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Ticket") { state.navigate(to: .newTicket) }.keyboardShortcut("n")
        }
        CommandGroup(after: .textEditing) {
            Button("Search") { state.showPalette = true }.keyboardShortcut("k")
            Button("Sync with GitHub") { state.syncNow() }.keyboardShortcut("r", modifiers: [.shift, .command])
            Button("Iris") { state.showAskPanel.toggle() }.keyboardShortcut("a", modifiers: [.option, .command])
        }
        CommandGroup(after: .toolbar) {
            Button("Back") { state.goBack() }.keyboardShortcut("[").disabled(!state.canGoBack)
            Button("Forward") { state.goForward() }.keyboardShortcut("]").disabled(!state.canGoForward)
        }
        CommandGroup(after: .sidebar) {
            Toggle("Sidebar", isOn: $state.showSidebar)
                .keyboardShortcut("s", modifiers: [.control, .command])
            Toggle("Iris Inspector", isOn: $state.showAskPanel)
                .keyboardShortcut("i", modifiers: [.control, .command])
        }
        CommandMenu("Go") {
            Button("Desk") { state.navigate(to: .desk) }.keyboardShortcut("1")
            Button("Tickets") { state.navigate(to: .tickets) }.keyboardShortcut("2")
            Button("Board") { state.navigate(to: .board) }.keyboardShortcut("3")
            Button("Previews") { state.navigate(to: .previews) }.keyboardShortcut("4")
        }
    }
}
