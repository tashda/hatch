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

/// Menu commands and shortcuts from the design: New ticket (cmd-N), Search (cmd-K), Ask (opt-cmd-A). The palette's
/// scopes each have their own: Tickets cmd-K, Actions shift-cmd-K, Go to cmd-O, Spec and decisions shift-cmd-O.
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
            Button("Search Tickets") { state.openPalette(.tickets) }.keyboardShortcut("k")
            Button("Actions…") { state.openPalette(.actions) }.keyboardShortcut("k", modifiers: [.shift, .command])
            Button("Search Spec and Decisions") { state.openPalette(.reference) }.keyboardShortcut("o", modifiers: [.shift, .command])
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
            Button("Go to…") { state.openPalette(.places) }.keyboardShortcut("o")
            Divider()
            Button("Desk") { state.navigate(to: .desk) }.keyboardShortcut("1")
            Button("Tickets") { state.navigate(to: .tickets) }.keyboardShortcut("2")
            Button("Board") { state.navigate(to: .board) }.keyboardShortcut("3")
            Button("Previews") { state.navigate(to: .previews) }.keyboardShortcut("4")
            Button("Specs") { state.navigate(to: .specs) }.keyboardShortcut("5")
            Button("Decisions") { state.navigate(to: .decisions) }.keyboardShortcut("6")
            Button("Agents") { state.navigate(to: .agents) }.keyboardShortcut("7")
            Button("Log") { state.navigate(to: .log) }.keyboardShortcut("8")
            Button("Project Settings") { state.navigate(to: .projects) }.keyboardShortcut("9")
        }
    }
}
