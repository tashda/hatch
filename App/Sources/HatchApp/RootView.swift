import SwiftUI
import HatchCore

/// The window: sidebar, content, and the Ask panel on the right (decisions B1, B4).
struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                if state.snapshotPresentation == .settings {
                    SettingsView()
                } else if state.snapshotPresentation == .palette {
                    CommandPalette()
                } else if state.snapshotPresentation == .askPanel {
                    HStack(spacing: 0) {
                        content.frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        AskPanel().frame(width: 320)
                    }
                } else {
                    HStack(spacing: 0) {
                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if state.showAskPanel {
                            Divider()
                            AskPanel().frame(width: 320)
                        }
                    }
                }
            }
            .navigationTitle(snapshotTitle)
            .toolbar {
                if state.snapshotPresentation == nil { MainToolbar() }
            }
        }
        .sheet(isPresented: $state.showPalette) { CommandPalette() }
        .alert("Something went wrong", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(state.errorMessage ?? "") }
    }

    private var snapshotTitle: String {
        switch state.snapshotPresentation {
        case .settings: "Settings"
        case .palette: "Search"
        case .askPanel: "Ask Hatch"
        case nil: state.route.title
        }
    }

    @ViewBuilder private var content: some View {
        switch state.route {
        case .desk: DeskView()
        case .tickets: TicketsView()
        case .board: BoardView()
        case .previews: PreviewsView()
        case .specs: SpecsView()
        case .decisions: DecisionsView()
        case .agents: AgentsView()
        case .log: LogView()
        case .projects: ProjectView()
        case .ticket(let id): TicketDetailView(ticketId: id)
        case .newTicket: ComposerView()
        }
    }
}

struct MainToolbar: ToolbarContent {
    @EnvironmentObject var state: AppState

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) { ProjectTitleMenu() }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { state.showPalette = true } label: { Label("Search", systemImage: "magnifyingglass") }
                .help("Search (⌘K)")
            Button { state.route = .newTicket } label: { Label("New Ticket", systemImage: "plus") }
                .help("New ticket (⌘N)")
            Button { state.showAskPanel.toggle() } label: { Label("Ask", systemImage: "sparkles") }
                .help("Ask Hatch (⌥⌘A)")
        }
    }
}

/// The project as the window's title control (decision LK2, option D): tile and name; a click opens the list of projects.
struct ProjectTitleMenu: View {
    @EnvironmentObject var state: AppState

    private var current: Project? {
        state.projects.first { $0.key == state.selectedProjectKey }
    }

    var body: some View {
        Menu {
            Button {
                state.selectedProjectKey = nil
            } label: {
                Label("All projects", systemImage: state.selectedProjectKey == nil ? "checkmark" : "square.stack.3d.up")
            }
            if !state.projects.isEmpty { Divider() }
            ForEach(state.projects) { project in
                Button {
                    state.selectedProjectKey = project.key
                } label: {
                    if state.selectedProjectKey == project.key {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
            if !state.projects.isEmpty { Divider() }
            Button("Project settings…", systemImage: "gearshape") { state.route = .projects }
        } label: {
            HStack(spacing: 6) {
                if let p = current {
                    ProjectTile(name: p.name, key: p.key)
                } else {
                    Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary).frame(width: 20, height: 20)
                }
                Text(current?.name ?? "All projects").fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .help("Switch project")
    }
}
