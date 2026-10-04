import SwiftUI
import HatchCore

/// Work / Views / Reference / Machine sections, sync footer and Project settings (decisions B1, B5, D3).
/// The project switch is the toolbar title control (LK2), not a popup here.
struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @State private var yourTurn: Int = 0
    @State private var views: [SavedView] = []
    /// Read by TicketsView, which applies it as its filter (decision D3).
    @AppStorage("hatch.pendingTicketQuery") private var pendingQuery = ""

    private var selection: Binding<Route?> {
        Binding<Route?>(
            get: { Self.sidebarRoute(for: state.route) },
            set: { newValue in
                if let newValue { state.navigate(to: newValue) }
            }
        )
    }

    /// A ticket page or the composer highlights nothing; the other routes highlight themselves.
    private static func sidebarRoute(for route: Route) -> Route? {
        switch route {
        case .ticket, .newTicket: return nil
        default: return route
        }
    }

    var body: some View {
        List(selection: selection) {
            if state.projects.isEmpty {
                // Everything else needs a project; it appears once one is set up.
                Section("Get started") {
                    Button { state.showAddProject = true } label: {
                        Label("Set up a project", systemImage: "plus")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.plain)
                }
                Section("Machine") {
                    SidebarRow(route: .agents).tag(Route.agents)
                }
            } else {
            Section("Work") {
                deskRow
                SidebarRow(route: .tickets).tag(Route.tickets)
                SidebarRow(route: .board).tag(Route.board)
                SidebarRow(route: .previews).tag(Route.previews)
            }
            if !views.isEmpty {
                Section("Views") {
                    ForEach(views) { view in
                        Button {
                            pendingQuery = view.query
                            state.navigate(to: .tickets)
                        } label: {
                            Label(view.name, systemImage: "bookmark")
                        }
                        .buttonStyle(.plain)
                        .help(view.query)
                    }
                }
            }
            Section("Reference") {
                SidebarRow(route: .specs).tag(Route.specs)
                SidebarRow(route: .decisions).tag(Route.decisions)
                SidebarRow(route: .components).tag(Route.components)
            }
            Section("Machine") {
                SidebarRow(route: .agents).tag(Route.agents)
                SidebarRow(route: .health).tag(Route.health)
                SidebarRow(route: .log).tag(Route.log)
            }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .autoReload(every: 5) { reloadCounts() }
        .onAppear { reloadViews() }
    }

    /// The same saved views the Tickets screen keeps; the built-in ones show until the owner saves their own.
    private func reloadViews() {
        guard let json = (try? state.store.setting("views")) ?? nil,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SavedView].self, from: data) else {
            if views != TicketsView.defaultViews { views = TicketsView.defaultViews }
            return
        }
        if views != decoded { views = decoded }
    }

    private func reloadCounts() {
        reloadViews()
        let count = state.decisionCount
        if count != yourTurn { yourTurn = count }
        let counts = (try? state.store.syncCounts()) ?? (pending: 0, failed: 0)
        if counts.pending != state.syncSummary.pending || counts.failed != state.syncSummary.failed {
            state.refreshSyncSummary()
        }
    }

    private var deskRow: some View {
        HStack {
            Label(Route.desk.title, systemImage: Route.desk.symbol)
            Spacer()
            if yourTurn > 0 {
                Text("\(yourTurn)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.you)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Theme.youBackground, in: Capsule())
            }
        }
        .tag(Route.desk)
    }
}

struct SidebarRow: View {
    let route: Route

    var body: some View {
        Label(route.title, systemImage: route.symbol)
            .tag(route)
    }
}

/// The window footer, across the whole window: agent slots on the left (filled = running, outline = free),
/// GitHub sync on the right. "Synced with GitHub · 2 pending"; red when something failed. Click opens the Log (decision B5).
struct WindowFooter: View {
    @EnvironmentObject var state: AppState

    /// The calm status bar (design-review/footer.html): agents and what just happened on the left, where you are and
    /// whether everything is saved on the right.
    var body: some View {
        HStack(spacing: 14) {
            if state.projects.isEmpty {
                // Nothing runs or syncs yet, so the bar only points at the first step.
                Button { state.showAddProject = true } label: {
                    Text("Set up a project to get started").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 20)
                Spacer(minLength: 12)
            } else {
                FooterAgentSlots()
                FooterActivityLine()
                Spacer(minLength: 12)
                FooterProjectPill()
                FooterStatusGlyph()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
    }
}
