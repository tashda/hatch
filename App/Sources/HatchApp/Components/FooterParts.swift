import SwiftUI
import HatchCore
import HatchAgent
import HatchGit

// The footer as a calm status bar (design-review/footer.html, A): agent slots and the activity line on the left,
// the project and how work flows, and one status glyph, on the right. Quiet when calm, specific when not. Each part
// shows a glass card on hover; clicking goes where you act on it.

// MARK: Hover cards

/// Shows a card while the pointer is on the view or on the card. Leaving waits a moment, so moving onto the card
/// does not close it.
private struct HoverCard<Card: View>: ViewModifier {
    let enabled: Bool
    @ViewBuilder let card: () -> Card
    @State private var overView = false
    @State private var overCard = false
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .onHover { overView = $0; update() }
            .popover(isPresented: Binding(get: { showing && enabled }, set: { if !$0 { showing = false } }), arrowEdge: .top) {
                card().onHover { overCard = $0; update() }
            }
    }

    private func update() {
        if overView || overCard { showing = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if !overView && !overCard { showing = false } }
    }
}

extension View {
    func hoverCard<C: View>(enabled: Bool = true, @ViewBuilder _ card: @escaping () -> C) -> some View {
        modifier(HoverCard(enabled: enabled, card: card))
    }
}

/// The inside of every footer card: a title, then rows.
private struct FooterCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(width: 330, alignment: .leading)
    }
}

private struct CardRow: View {
    let label: String
    let value: String
    var tint: Color = .secondary
    /// Makes the value open this page, with an arrow to say so.
    var link: URL?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if let link {
                Button { NSWorkspace.shared.open(link) } label: {
                    Text(value + " ↗").foregroundStyle(tint).multilineTextAlignment(.trailing).lineLimit(2)
                }
                .buttonStyle(.plain)
                .help("Open the runs on GitHub")
            } else {
                Text(value).foregroundStyle(tint).multilineTextAlignment(.trailing).lineLimit(2)
            }
        }
        .font(.callout)
    }
}

// MARK: Agent slots

/// One circle per slot. Right-click, or click a free slot, for Pause, Open Agents and Agents at Once. While paused the
/// free slots are dashed, so a pause is never forgotten.
struct FooterAgentSlots: View {
    @EnvironmentObject var state: AppState
    @State private var slots: (used: Int, max: Int) = (0, 3)

    var body: some View {
        let runs = state.agentRuns
        HStack(spacing: 4) {
            ForEach(0..<max(slots.max, runs.count, 1), id: \.self) { i in
                if i < runs.count {
                    AgentSlotCircle(run: runs[i], busy: true)
                } else if i < slots.used {
                    AgentSlotCircle(run: nil, busy: true)
                } else {
                    Menu { menuItems } label: { FreeSlot(paused: state.agentsPaused) }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                        .help(state.agentsPaused ? "Agents are paused" : "A free agent slot")
                }
            }
        }
        .contextMenu { menuItems }
        .autoReload(every: 4) { load() }
    }

    @ViewBuilder private var menuItems: some View {
        Button(state.agentsPaused ? "Resume Agents" : "Pause Agents") { state.setAgentsPaused(!state.agentsPaused) }
        Button("Open Agents") { state.navigate(to: .agents) }
        Divider()
        Picker("Agents at Once", selection: Binding(get: { slots.max }, set: { n in
            state.hxSaveSetting("max_agents", String(n)); load(); state.tickLauncher()
        })) {
            ForEach(AgentSettingsPage.agentCounts, id: \.self) { n in Text(n == 3 ? "3 · Recommended" : "\(n)").tag(n) }
        }
    }

    private func load() {
        let used = (try? state.store.activeAgentCount()) ?? 0
        let maxAgents = (try? state.store.maxAgents(projectId: state.projectFilterId)) ?? 3
        if slots.used != used || slots.max != maxAgents { slots = (used, maxAgents) }
    }
}

private struct FreeSlot: View {
    let paused: Bool
    var body: some View {
        Circle()
            .strokeBorder(Color.secondary.opacity(paused ? 0.6 : 0.4), style: StrokeStyle(lineWidth: 1, dash: paused ? [2, 2] : []))
            .background(Circle().fill(Color.secondary.opacity(0.08)))
            .frame(width: 11, height: 11)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }
}

// MARK: Activity line

/// The latest thing that happened, in a few words. New events are bright for a minute, then grey. Hover: the last ten.
struct FooterActivityLine: View {
    @EnvironmentObject var state: AppState
    @State private var events: [(event: Event, ticket: Ticket)] = []

    var body: some View {
        Button { state.navigate(to: .log) } label: {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 5) {
                    if state.agentsPaused {
                        Text("Agents paused").foregroundStyle(Theme.you)
                    } else if let latest = events.first {
                        let fresh = context.date.timeIntervalSince(latest.event.at) < 60
                        Text(Self.line(latest)).foregroundStyle(fresh ? Color.primary : Color.secondary)
                            .contentTransition(.opacity)
                        Text("· \(Format.relative(latest.event.at, now: context.date))").foregroundStyle(.tertiary)
                    } else {
                        Text("Nothing has happened yet").foregroundStyle(.tertiary)
                    }
                }
                .font(.caption).lineLimit(1)
            }
            .animation(.easeInOut(duration: 0.4), value: events.first?.event.id)
        }
        .buttonStyle(.plain)
        .hoverCard(enabled: !events.isEmpty) {
            FooterCard(title: "Latest") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events, id: \.event.id) { item in
                        Button { state.open(item.ticket) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Format.relative(item.event.at)).foregroundStyle(.tertiary).frame(width: 64, alignment: .leading)
                                Text(Self.line(item)).foregroundStyle(.primary).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.callout).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: state.revision) { load() }
        .autoReload(every: 10) { load() }
    }

    private func load() {
        let next = (try? state.store.recentEvents(projectId: state.projectFilterId, limit: 10)) ?? []
        if next.map(\.event.id) != events.map(\.event.id) { events = next }
    }

    /// "#151 moved to To verify", "Agent on #152 started", or the Log's wording for anything else.
    static func line(_ item: (event: Event, ticket: Ticket)) -> String {
        let e = item.event, n = item.ticket.displayNumber
        switch e.kind {
        case "status": return "\(n) moved to \(EventText.statusName(e.payload["to"]?.stringValue))"
        case "take": return e.actor.contains(n) ? "\(e.actor) started" : "\(e.actor) started \(n)"
        case "release": return "\(n) was given back"
        case "created": return "\(n) created: \(item.ticket.title)"
        default: return "\(n): \(EventText.describe(e))"
        }
    }
}

// MARK: Where you are

/// "Echo · hatch → dev": the project and how work reaches its base branch. Hover: each repository and its clone.
struct FooterProjectPill: View {
    @EnvironmentObject var state: AppState
    @State private var probes: [(repo: Repo, probe: RepoProbe?)] = []

    var body: some View {
        if let text {
            Button { state.navigate(to: .health) } label: {
                Label(text, systemImage: "arrow.triangle.branch")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
            .buttonStyle(.plain)
            .hoverCard(enabled: state.hxProject != nil) {
                FooterCard(title: state.hxProject?.name ?? "Project") {
                    if probes.isEmpty { ProgressView().controlSize(.small) }
                    ForEach(probes, id: \.repo.id) { item in
                        CardRow(label: hxRoleName(item.repo.role), value: describe(item.repo, item.probe),
                                tint: item.probe?.exists == false ? Theme.critical : .secondary)
                    }
                }
                .task { await loadProbes() }
            }
        }
    }

    private var text: String? {
        let projects = state.projects
        if state.selectedProjectKey == nil && projects.count > 1 { return "\(projects.count) projects" }
        guard let p = state.hxProject else { return nil }
        let integration = p.config?.integrationBranch ?? "hatch"
        let base = p.config?.repo(.app)?.branch ?? "dev"
        return "\(p.name) · \(integration) → \(base)"
    }

    private func describe(_ repo: Repo, _ p: RepoProbe?) -> String {
        guard repo.localPath != nil else { return repo.role == .tickets ? "\(repo.remote) · issues" : "\(repo.remote) · no clone" }
        guard let p else { return repo.remote }
        guard p.exists else { return "No clone on this Mac" }
        var parts = [p.branch ?? "?"]
        if p.dirtyFiles > 0 { parts.append("\(p.dirtyFiles) uncommitted") }
        if let a = p.ahead, a > 0 { parts.append("\(a) to push") }
        if let b = p.behind, b > 0 { parts.append("\(b) behind") }
        if parts.count == 1 { parts.append("in step") }
        return "\(repo.remote.split(separator: "/").last.map(String.init) ?? repo.remote) · " + parts.joined(separator: " · ")
    }

    private func loadProbes() async {
        guard let project = state.hxProject else { return }
        let store = state.store
        probes = await Task.detached {
            ((try? store.repos(projectId: project.id)) ?? []).map { repo in
                (repo, repo.localPath.map { RepoProbe.run(path: $0, remote: repo.remote, commits: 1) })
            }
        }.value
    }
}

// MARK: Status

/// One glyph for everything that moves data: GitHub sync, the notebooks and the database. A check when all is saved, a
/// spinner while something moves, orange when something needs a look, red when something failed. Hover: what is where.
/// How the data is doing, for the footer glyph and the menu bar item.
enum SaveLevel {
    case calm, busy, attention, problem

    var title: String {
        switch self {
        case .calm: "Everything is saved"
        case .busy: "Saving…"
        case .attention: "Not synced yet"
        case .problem: "Something needs a look"
        }
    }
}

extension AppState {
    var saveLevel: SaveLevel {
        let s = syncSummary
        if s.failed > 0 || s.message != nil || notebookProblem != nil { return .problem }
        if syncing || exportingNotebooks || s.pending > 0 { return .busy }
        if s.lastOK == nil && projects.contains(where: { !($0.config?.ticketsRepo ?? "").isEmpty }) { return .attention }
        if usageLevel != .fine { return .attention }
        return .calm
    }

    /// The status in words; orange from the daily token limits says which one.
    var saveTitle: String {
        let level = saveLevel
        guard level == .attention else { return level.title }
        switch usageLevel {
        case .pause: return "Agents paused for today"
        case .warn: return "Many tokens used today"
        case .fine: return level.title
        }
    }
}

/// The status glyph: a check when all is saved, a turning arrow while something moves, orange or red when not.
struct SaveLevelGlyph: View {
    let level: SaveLevel
    var body: some View {
        Group {
            switch level {
            case .calm: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.finished)
            case .busy: Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                    .symbolEffect(.rotate, options: .repeating)
            case .attention: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .problem: Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.critical)
            }
        }
        .contentTransition(.symbolEffect(.replace))
    }
}

struct FooterStatusGlyph: View {
    @EnvironmentObject var state: AppState
    @State private var ci: String?

    private var level: SaveLevel { state.saveLevel }

    var body: some View {
        Button { state.navigate(to: .health) } label: {
            SaveLevelGlyph(level: level)
            .font(.system(size: 13))
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .hoverCard {
            FooterCard(title: title) {
                CardRow(label: "GitHub", value: githubLine, tint: state.syncSummary.failed > 0 ? Theme.critical : .secondary)
                ForEach(state.projects.filter { $0.config?.repo(.notebook) != nil }) { p in
                    CardRow(label: state.projects.count > 1 ? "\(p.name) notebook" : "Notebook", value: notebookLine(p),
                            tint: (try? state.store.notebookStatus(projectId: p.id).error) ?? nil == nil ? .secondary : Theme.critical)
                }
                CardRow(label: "Decisions", value: decisionsLine)
                if state.usageLevel != .fine {
                    CardRow(label: "Usage", value: state.usageLevel == .pause ? "Above the pause limit; nothing new starts today" : "Above the daily warning",
                            tint: .orange)
                }
                // A repository with no CI has nothing to say here; "not checked" and "cancelled" are grey, only a failure is red.
                if let ci, ci != HXCIAdapter.noCI {
                    CardRow(label: "CI on \(state.hxProject?.config?.integrationBranch ?? "hatch")", value: ci,
                            tint: ci.hasPrefix("failing") ? Theme.critical : .secondary, link: ciURL)
                }
            }
            .task { await loadCI() }
        }
    }

    private var title: String { state.saveTitle }

    private var githubLine: String {
        let s = state.syncSummary
        if let m = s.message, !m.isEmpty { return m }
        if s.failed > 0 { return "\(s.failed) failed, \(s.pending) waiting" }
        if s.pending > 0 { return "\(s.pending) waiting to sync" }
        return s.lastOK.map { "Synced \(Format.relative($0))" } ?? "Not synced yet"
    }

    private func notebookLine(_ p: Project) -> String {
        let status = (try? state.store.notebookStatus(projectId: p.id)) ?? (exportedAt: nil, pushedAt: nil, error: nil)
        if let e = status.error { return e }
        return status.pushedAt.map { "Pushed \(Format.relative($0))" } ?? "Not pushed yet"
    }

    private var decisionsLine: String {
        let all = (try? state.store.decisionRecords(projectId: state.projectFilterId)) ?? []
        let waiting = all.filter { $0.filePath == nil }.count
        return waiting == 0 ? "\(all.count), all in the notebook" : "\(all.count), \(waiting) not written yet"
    }

    /// CI on Hatch's branch, asked from GitHub once per hover.
    private func loadCI() async {
        guard let p = state.hxProject, let app = p.config?.repo(.app) else { return }
        let branch = p.config?.integrationBranch ?? "hatch"
        let store = state.store, projectId = p.id
        ci = await Task.detached { HXCIAdapter.status(remote: app.remote, ref: branch, store: store, projectId: projectId) }.value
    }

    private var ciURL: URL? {
        guard let app = state.hxProject?.config?.repo(.app) else { return nil }
        return HXCIAdapter.runsURL(remote: app.remote, ref: state.hxProject?.config?.integrationBranch ?? "hatch")
    }
}
