import SwiftUI
import HatchCore

/// The window: sidebar, content, and the Ask panel on the right (decisions B1, B4).
struct RootView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("hatch.sidebarWidth") private var sidebarWidth = 232.0
    @AppStorage("hatch.irisWidth") private var irisWidth = 344.0

    var body: some View {
        // Snapshot runs use the same window as the live app, so what they show is what you see.
        liveShell
        .commandPaletteOverlay()
        .sheet(isPresented: $state.showAddProject) { ProjectSetupAssistant(store: state.store) }
        .alert("Something went wrong", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(state.errorMessage ?? "") }
    }

    /// Iris is a column beside the page, not the native inspector: the cards float on the window
    /// background under the toolbar, as in Echo. It lives above the routed content, so it stays open across pages.
    /// The window as floating panels on the window background, as in Echo: sidebar, page and Iris are
    /// separate cards; the footer sits under the page and Iris, not under the sidebar.
    private var liveShell: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if state.showSidebar {
                    SidebarView()
                        .floatingCard()
                        .frame(width: sidebarWidth)
                        .overlay(alignment: .trailing) {
                            PanelResizer(width: $sidebarWidth, range: 190...340).offset(x: 11)
                        }
                        .padding(.init(top: 6, leading: 8, bottom: 0, trailing: 0))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                liveDetail
            }
            WindowFooter()
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .animation(.snappy(duration: 0.25), value: state.showSidebar)
        .navigationTitle(state.route.title)
        // The system's soft scroll edge under the toolbar, forced on every scroll view in the window
        // (macOS 27 defaults to the hard edge).
        .scrollEdgeEffectStyle(.soft, for: .top)
        // Never the hard toolbar background, also on pages without a scroll view under the toolbar.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar { LiveToolbar() }
    }

    /// Pages that lay out several panels themselves; the others get one card.
    private var ownsPanels: Bool {
        switch state.route {
        case .desk, .specs, .previews, .tickets, .board, .decisions, .components, .agents, .health, .log: true
        default: false
        }
    }

    @ViewBuilder private var pageCard: some View {
        // Nothing works without a project, so until there is one every page is the welcome.
        if state.projects.isEmpty { WelcomeView().floatingCard() }
        else if ownsPanels { detailContent } else { detailContent.floatingCard() }
    }

    private var liveDetail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                pageCard
                if state.showAskPanel {
                    IrisPanel()
                        .frame(width: irisWidth)
                        .overlay(alignment: .leading) {
                            PanelResizer(width: $irisWidth, range: 300...560, growsLeft: true).offset(x: -11)
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.init(top: 6, leading: 8, bottom: 0, trailing: 8))
        }
        .animation(.snappy(duration: 0.25), value: state.showAskPanel)
    }

    private var detailContent: some View {
        Group {
            if state.snapshotPresentation == .settings {
                SettingsView()
            } else if state.snapshotPresentation == .palette {
                CommandPalette()
            } else if state.snapshotPresentation == .agentCard {
                // Snapshot only: the footer's agent card with a sample agent, since a hover popover is not captured.
                AgentCard(run: Snapshots.sampleRun) {}
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.snapshotPresentation == .menuBar {
                // Snapshot only: the menu bar item's panel, which lives outside the window and is not captured.
                MenuBarPanel()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.snapshotPresentation == .addProject {
                ProjectSetupAssistant(store: state.store, demoStep: ProjectSetupModel.Step(rawValue: state.snapshotSetupStep))
                    .id(state.snapshotSetupStep)
            } else if state.snapshotPresentation == .repositorySelector {
                HXRepositorySelectionSheet(account: GitHubAccountModel(), projectName: "Acme",
                                           initial: [.tickets: "acme/hatch-tickets", .app: "acme/app",
                                                     .designSystem: "acme/design-system"]) { _ in true }
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(snapshotTitle)
    }

    private var snapshotTitle: String {
        switch state.snapshotPresentation {
        case .settings: "Settings"
        case .palette: "Search"
        case .addProject: "Add project"
        case .repositorySelector: "Choose repositories"
        case .agentCard: "Agent"
        case .menuBar: "Menu bar"
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
        case .components: ComponentsView()
        case .agents: AgentsView()
        case .health: HealthView()
        case .log: LogView()
        case .projects: ProjectView()
        case .ticket(let id): TicketDetailView(ticketId: id)
        case .newTicket: ComposerView()
        }
    }
}

/// The three buttons on the right of the toolbar.
private struct ToolbarActions: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Button { state.showPalette = true } label: { Label("Search", systemImage: "magnifyingglass") }
            .labelStyle(.iconOnly)
            .help("Search (\u{2318}K)")
        Button { state.navigate(to: .newTicket) } label: { Label("New Ticket", systemImage: "plus") }
            .labelStyle(.iconOnly)
            .help("New ticket (\u{2318}N)")
        // The icon takes the accent color while the panel is open; no pill behind it.
        Button { state.showAskPanel.toggle() } label: {
            Image(systemName: "sparkles")
                .foregroundStyle(state.showAskPanel ? Color.accentColor : Color.primary)
        }
            .help(state.showAskPanel ? "Hide Iris (\u{2325}\u{2318}A)" : "Show Iris (\u{2325}\u{2318}A)")
            .accessibilityLabel(state.showAskPanel ? "Hide Iris" : "Show Iris")
    }
}

/// The live window's toolbar, built like Echo's: the sidebar button on its own glass, then native groups for
/// Back and Forward and for the project, each apart by a fixed spacer. A zero-size principal item keeps the
/// leading and trailing groups from sliding together when the window resizes.
struct LiveToolbar: ToolbarContent {
    @EnvironmentObject var state: AppState

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { state.showSidebar.toggle() } label: { Label("Sidebar", systemImage: "sidebar.leading") }
                .labelStyle(.iconOnly)
                .help("Show or hide the sidebar (\u{2303}\u{2318}S)")
                .glassEffect(.regular.interactive())
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.fixed)

        ToolbarItem(placement: .navigation) {
            // The same control Echo's Settings uses for Back and Forward.
            ControlGroup {
                Button { state.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(!state.canGoBack)
                    .help(state.backTitle.map { "Back to \($0) (\u{2318}[)" } ?? "Go Back")
                Button { state.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(!state.canGoForward)
                    .help("Go Forward (\u{2318}])")
            }
            .controlGroupStyle(.navigation)
        }

        ToolbarSpacer(.fixed)

        if state.projects.isEmpty {
            // A plain toolbar button, so the system draws its glass.
            ToolbarItem(placement: .navigation) {
                Button { state.showAddProject = true } label: { Label("Set up a project", systemImage: "plus") }
                    .labelStyle(.titleAndIcon)
                    .help("Set up your first project")
            }
        } else {
            ToolbarItem(placement: .navigation) {
                ProjectTitleMenu()
                    .padding(.horizontal, 6)
                    .glassEffect(.regular.interactive())
            }
            .sharedBackgroundVisibility(.hidden)
        }

        ToolbarItem(placement: .principal) {
            Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
        }

        ToolbarItemGroup(placement: .primaryAction) { ToolbarActions() }
    }
}

/// The project as the window's title control (decision LK2, option D): tile and name; a click opens the list of projects.
/// "All projects" is offered only when there are two or more; with none, the toolbar shows Set up a project instead.
struct ProjectTitleMenu: View {
    @EnvironmentObject var state: AppState

    /// The project the title shows. A single project is always the current one.
    private var current: Project? {
        let projects = state.projects
        return projects.first { $0.key == state.selectedProjectKey } ?? (projects.count == 1 ? projects.first : nil)
    }

    var body: some View {
        menu(state.projects)
    }

    private func menu(_ projects: [Project]) -> some View {
        Menu {
            if projects.count > 1 {
                Button {
                    state.selectedProjectKey = nil
                } label: {
                    Label("All projects", systemImage: current == nil ? "checkmark" : "square.stack.3d.up")
                }
                Divider()
            }
            ForEach(projects) { project in
                Button {
                    state.selectedProjectKey = project.key
                } label: {
                    if current?.key == project.key {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
            Divider()
            Button("Project settings…", systemImage: "gearshape") { state.navigate(to: .projects) }
            Button("Add project…", systemImage: "plus") { state.showAddProject = true }
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

extension View {
    /// A panel that floats on the window background: rounded, softly shadowed, with a gutter around it (as in Echo).
    func floatingCard() -> some View {
        self
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.3)))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}
