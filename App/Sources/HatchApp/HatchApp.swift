import SwiftUI
import HatchCore

@main
struct HatchApp: App {
    @StateObject private var state = (Snapshots.folder == nil && !Snapshots.demoMode) ? AppState.live() : Snapshots.demoState()

    init() {
        // Snapshot and demo runs share the app's preferences and saved windows. They neither restore nor save window
        // state, so they always open their own window and never change the one the owner gets next.
        if Snapshots.demoMode {
            UserDefaults.standard.setVolatileDomain(["ApplePersistenceIgnoreState": true], forName: UserDefaults.argumentDomain)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .background(WindowTag(identifier: HatchWindows.mainIdentifier))
                .focusedSceneValue(\.windowNavigation, WindowNavigation(
                    canGoBack: state.canGoBack, canGoForward: state.canGoForward,
                    goBack: { state.goBack() }, goForward: { state.goForward() }))
                .focusedSceneValue(\.currentTicketId, state.currentTicketId)
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

        // One ticket in its own window. Opening the same ticket again brings the existing window forward.
        WindowGroup("Ticket", id: "ticket", for: Int.self) { $ticketId in
            if let ticketId {
                TicketWindowView(ticketId: ticketId)
                    .environmentObject(state)
            }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 900, height: 760)

        // A regular window lets NavigationSplitView place its sidebar toggle in the titlebar.
        Window("Settings", id: "settings") {
            SettingsView().environmentObject(state)
        }
        .defaultSize(width: 1040, height: 720)
    }
}

/// Menu commands. Every key comes from `ShortcutStore`, so the Settings page changes them live.
struct HatchCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var state: AppState
    @ObservedObject private var keys = ShortcutStore.shared
    @FocusedValue(\.windowNavigation) private var navigation
    @FocusedValue(\.currentTicketId) private var ticketId

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: "settings") }
                .shortcut("settings", keys)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Ticket") { state.navigate(to: .newTicket) }.shortcut("page.newTicket", keys)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Tickets") { state.openPalette(.tickets) }.shortcut("search.tickets", keys)
            Button("Actions…") { state.openPalette(.actions) }.shortcut("search.actions", keys)
            Button("Search Spec and Decisions") { state.openPalette(.reference) }.shortcut("search.reference", keys)
            Button("Sync with GitHub") { state.syncNow() }.shortcut("sync", keys)
            Button("Iris") { state.showAskPanel.toggle() }.shortcut("iris.toggle", keys)
        }
        CommandGroup(after: .toolbar) {
            Button("Back") { navigation?.goBack() }.shortcut("back", keys).disabled(!(navigation?.canGoBack ?? false))
            Button("Forward") { navigation?.goForward() }.shortcut("forward", keys).disabled(!(navigation?.canGoForward ?? false))
        }
        CommandGroup(after: .sidebar) {
            Toggle("Sidebar", isOn: $state.showSidebar).shortcut("sidebar", keys)
            Toggle("Iris Inspector", isOn: $state.showAskPanel).shortcut("iris.inspector", keys)
        }
        CommandMenu("Go") {
            Button("Go to…") { state.openPalette(.places) }.shortcut("go.places", keys)
            Divider()
            ForEach(Route.pages, id: \.self) { route in
                if let id = route.shortcutId {
                    Button(ShortcutCatalog.command(id)?.title ?? route.title) { state.navigate(to: route) }.shortcut(id, keys)
                }
            }
        }
        CommandMenu("Ticket") {
            Button("Open in New Window") { if let ticketId { openWindow(id: "ticket", value: ticketId) } }
                .shortcut("ticket.openWindow", keys)
                .disabled(ticketId == nil)
        }
    }
}
