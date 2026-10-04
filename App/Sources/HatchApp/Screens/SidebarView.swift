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
        let count = state.yourTurnCount
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
    @State private var slots: (used: Int, max: Int) = (0, 3)

    private var summary: AppState.SyncSummary { state.syncSummary }

    private var text: String {
        if let message = summary.message, !message.isEmpty { return message }
        if let problem = state.notebookProblem { return "Notebook not saved: \(problem)" }
        if summary.failed > 0 {
            return "\(summary.failed) failed to sync · \(summary.pending) pending"
        }
        if summary.pending > 0 {
            return "Syncing with GitHub · \(summary.pending) pending"
        }
        if summary.lastOK == nil { return "Not synced yet" }
        return "Synced with GitHub"
    }

    var body: some View {
        HStack(spacing: 14) {
            Button { state.navigate(to: .agents) } label: {
                HStack(spacing: 7) {
                    ForEach(0..<max(slots.max, 1), id: \.self) { i in
                        let running = i < slots.used
                        Circle()
                            .fill(running
                                  ? AnyShapeStyle(LinearGradient(colors: [Theme.agent.opacity(0.75), Theme.agent], startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(Color.secondary.opacity(0.08)))
                            .overlay(Circle().strokeBorder(running ? Theme.agent.opacity(0.35) : Color.secondary.opacity(0.4), lineWidth: running ? 3 : 1))
                            .shadow(color: running ? Theme.agent.opacity(0.45) : .clear, radius: 3)
                            .frame(width: 11, height: 11)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(slots.used == 0 ? "No agents running. Open Agents" : "\(slots.used) of \(slots.max) agents running. Open Agents")
            Spacer()
            Button { state.navigate(to: .log) } label: {
                HStack(spacing: 6) {
                    Image(systemName: (summary.failed > 0 || summary.message != nil) ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                        .font(.caption)
                    Text(text).font(.caption).lineLimit(1)
                }
                .foregroundStyle((summary.failed > 0 || summary.message != nil) ? Theme.critical : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Open the Log")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .autoReload(every: 4) { load() }
    }

    private func load() {
        let used = (try? state.store.activeAgentCount()) ?? 0
        let maxAgents = (try? state.store.maxAgents(projectId: state.projectFilterId)) ?? 3
        if slots.used != used || slots.max != maxAgents { slots = (used, maxAgents) }
    }
}
