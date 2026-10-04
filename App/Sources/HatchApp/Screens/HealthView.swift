import SwiftUI
import AppKit
import HatchCore
import HatchGit

/// Health: where every part of a project lives and whether it is in step. Checks first, then how data moves between
/// Hatch's database, GitHub and the notebook, then each repository, then the latest activity across all of them.
/// Everything is read locally (database and git), so opening the page costs nothing.
struct HealthView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var model = HealthModel()

    var body: some View {
        Group {
            if let project = state.hxProject {
                content(project)
            } else {
                ContentUnavailableView("No project yet", systemImage: "stethoscope", description: Text("Set up a project to see its health."))
                    .floatingCard()
            }
        }
        .environment(\.hxCardOnGray, true)
        .onAppear { reload() }
        .onChange(of: state.hxProject?.id) { reload() }
        .onChange(of: state.revision) { model.reloadSoon(state: state) }
    }

    private func reload() { model.load(state: state) }

    private func content(_ project: Project) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                HXHeader(title: "Health", subtitle: "Where everything is for \(project.name), and whether it is in step. Read from this Mac; nothing is fetched.")
                Spacer()
                if model.loading { ProgressView().controlSize(.small) }
                Button("Save Notebook Now", systemImage: "arrow.up.doc") { state.exportNotebooks(); model.reloadSoon(state: state) }
                    .help("Write waiting decisions and NOW.md to the notebook, commit and push")
                Button("Refresh", systemImage: "arrow.clockwise") { reload() }
            }
            .padding(16)
            .floatingCard()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let s = model.snapshot {
                        checksCard(s)
                        flowCard(s)
                        reposCard(s)
                        activityCard(s)
                    }
                }
                .padding(3)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Checks

    private func checksCard(_ s: HealthSnapshot) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 10) {
                cardTitle("Checks", detail: s.checks.allSatisfy { $0.level == .ok } ? "Everything is in step." : "\(s.checks.filter { $0.level != .ok }.count) need a look.")
                ForEach(s.checks) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: c.level.symbol).foregroundStyle(c.level.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.title)
                            if let d = c.detail { Text(d).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                        Spacer()
                        if let action = c.action { Button(action.title) { run(action) } }
                    }
                }
            }
        }
    }

    // MARK: Data flow

    private func flowCard(_ s: HealthSnapshot) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("How data moves", detail: "Hatch's database is the working record. GitHub and the notebook are where it lasts.")
                flowRow(from: "Database", to: "GitHub issues", symbol: "number",
                        lines: ["\(s.syncPending) waiting, \(s.syncFailed) failed",
                                s.syncLastOK.map { "Last synced \(Format.relative($0))" } ?? "Not synced yet"])
                flowRow(from: "Database", to: "Notebook", symbol: "book.closed",
                        lines: ["\(s.decisionsWaiting) decision\(s.decisionsWaiting == 1 ? "" : "s") waiting to be written, \(s.decisionsTotal) in all",
                                s.notebookExportedAt.map { "NOW.md and decisions checked \(Format.relative($0))" } ?? "Not written yet",
                                s.notebookPushedAt.map { "Last pushed \(Format.relative($0))" } ?? "Not pushed yet"])
                flowRow(from: "Notebook", to: "Database", symbol: "magnifyingglass",
                        lines: ["\(s.specItems) Spec item\(s.specItems == 1 ? "" : "s") indexed for search",
                                "\(s.decisionsTotal) decision\(s.decisionsTotal == 1 ? "" : "s") searchable; briefs get the 3 that match"])
                flowRow(from: "Notebook", to: "Clones", symbol: "doc.on.doc",
                        lines: [s.rulesState, "\(s.activeWorkspaces) agent worktree\(s.activeWorkspaces == 1 ? "" : "s") open, each with the rules placed"])
            }
        }
    }

    private func flowRow(from: String, to: String, symbol: String, lines: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).frame(width: 28, height: 28)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(from).fontWeight(.medium)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text(to).fontWeight(.medium)
                }
                ForEach(lines, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: Repositories

    private func reposCard(_ s: HealthSnapshot) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("Repositories", detail: "What is in each one and where its clone stands. Ahead and behind are against the last fetch.")
                ForEach(s.repos) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(r.role).fontWeight(.semibold)
                            Text(r.remote).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            Spacer()
                            if let path = r.probe?.path, r.probe?.exists == true {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                                    .buttonStyle(.link)
                            }
                        }
                        Text(r.holds).font(.callout).foregroundStyle(.secondary)
                        if let p = r.probe {
                            Text(cloneLine(p)).font(.callout).foregroundStyle(p.exists ? .secondary : Theme.critical)
                            if let c = p.recent.first {
                                Text("Last commit \(c.sha) “\(c.subject)” by \(c.author), \(Format.relative(c.date))")
                                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                            }
                        }
                    }
                    if r.id != s.repos.last?.id { Divider() }
                }
            }
        }
    }

    private func cloneLine(_ p: RepoProbe) -> String {
        guard p.exists else { return "No clone at \(hxAbbreviated(p.path))" }
        var parts = ["\(hxAbbreviated(p.path)) on \(p.branch ?? "?")"]
        if !p.matchesRemote { parts.append("points at another repository") }
        if p.dirtyFiles > 0 { parts.append("\(p.dirtyFiles) uncommitted file\(p.dirtyFiles == 1 ? "" : "s")") }
        if let a = p.ahead, a > 0 { parts.append("\(a) to push") }
        if let b = p.behind, b > 0 { parts.append("\(b) behind") }
        if p.ahead == 0 && p.behind == 0 && p.dirtyFiles == 0 { parts.append("in step") }
        return parts.joined(separator: " · ")
    }

    // MARK: Activity

    private func activityCard(_ s: HealthSnapshot) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 8) {
                cardTitle("Latest activity", detail: "Commits to the notebook, GitHub sync and decisions, newest first.")
                if s.activity.isEmpty { Text("Nothing yet.").foregroundStyle(.secondary) }
                ForEach(s.activity) { a in
                    HStack(spacing: 10) {
                        Text(a.source).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                        Text(a.text).lineLimit(1).truncationMode(.tail)
                        Spacer()
                        Text(Format.relative(a.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(a.failed ? Theme.critical : .primary)
                }
            }
        }
    }

    private func cardTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func run(_ action: HealthCheck.Action) {
        switch action {
        case .exportNotebook: state.exportNotebooks()
        case .syncNow: state.syncNow()
        case .placeRules(let rules, let dir): _ = try? RulesPlacer.place(rules: rules, into: dir)
        case .openSettings: state.navigate(to: .projects)
        }
        model.reloadSoon(state: state)
    }
}

// MARK: Model

struct HealthCheck: Identifiable {
    enum Level {
        case ok, attention, problem
        var symbol: String { self == .ok ? "checkmark.circle.fill" : self == .attention ? "exclamationmark.circle.fill" : "xmark.octagon.fill" }
        var color: Color { self == .ok ? Theme.finished : self == .attention ? Theme.you : Theme.critical }
    }
    enum Action {
        case exportNotebook, syncNow, openSettings
        case placeRules(String, String)
        var title: String {
            switch self {
            case .exportNotebook: "Save Now"
            case .syncNow: "Sync Now"
            case .placeRules: "Place Rules"
            case .openSettings: "Project Settings"
            }
        }
    }
    let id = UUID()
    var level: Level
    var title: String
    var detail: String?
    var action: Action?
}

struct HealthRepo: Identifiable {
    let id = UUID()
    var role: String
    var remote: String
    var holds: String
    var probe: RepoProbe?
}

struct HealthActivity: Identifiable {
    let id = UUID()
    var date: Date
    var source: String
    var text: String
    var failed = false
}

struct HealthSnapshot {
    var checks: [HealthCheck] = []
    var repos: [HealthRepo] = []
    var activity: [HealthActivity] = []
    var syncPending = 0, syncFailed = 0
    var syncLastOK: Date?
    var decisionsWaiting = 0, decisionsTotal = 0, specItems = 0, activeWorkspaces = 0
    var notebookExportedAt: Date?, notebookPushedAt: Date?
    var rulesState = ""
}

@MainActor
final class HealthModel: ObservableObject {
    @Published var snapshot: HealthSnapshot?
    @Published var loading = false
    private var pending: DispatchWorkItem?

    /// Changes come in bursts; reload once they settle.
    func reloadSoon(state: AppState) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in self?.load(state: state) } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func load(state: AppState) {
        guard let project = state.hxProject, !loading else { return }
        loading = true
        let store = state.store, summary = state.syncSummary, connected = Snapshots.demoMode || HXKeychain.read() != nil
        Task {
            let snap = await Task.detached { Self.build(store: store, project: project, summary: summary, connected: connected) }.value
            snapshot = snap
            loading = false
        }
    }

    nonisolated static func build(store: HatchStore, project: Project, summary: AppState.SyncSummary, connected: Bool) -> HealthSnapshot {
        var s = HealthSnapshot()
        let config = project.config
        let repos = (try? store.repos(projectId: project.id)) ?? []
        func repo(_ role: RepoRole) -> Repo? { repos.first { $0.role == role } }

        s.syncPending = summary.pending
        s.syncFailed = summary.failed
        s.syncLastOK = summary.lastOK
        s.decisionsWaiting = ((try? store.decisionRecords(projectId: project.id, pendingExport: true)) ?? []).count
        let decisions = (try? store.decisionRecords(projectId: project.id)) ?? []
        s.decisionsTotal = decisions.count
        s.specItems = ((try? store.specItems(projectId: project.id)) ?? []).count
        let workspaces = ((try? store.workspaces()) ?? []).filter { ws in ws.state == "active" && repos.contains { $0.id == ws.repoId } }
        s.activeWorkspaces = workspaces.count
        let nb = (try? store.notebookStatus(projectId: project.id)) ?? (exportedAt: nil, pushedAt: nil, error: nil)
        s.notebookExportedAt = nb.exportedAt
        s.notebookPushedAt = nb.pushedAt

        // Probes of each clone, read from git on this Mac.
        let integration = config?.integrationBranch ?? "hatch"
        let app = repo(.app), notebook = repo(.notebook), components = repo(.designSystem)
        let appProbe = app?.localPath.map { RepoProbe.run(path: $0, remote: app!.remote, branches: [integration, app!.defaultBranch]) }
        let nbProbe = notebook?.localPath.map { RepoProbe.run(path: $0, remote: notebook!.remote, commits: 8) }
        let compProbe = components?.localPath.map { RepoProbe.run(path: $0, remote: components!.remote) }

        // What the notebook holds, counted from its files.
        func count(_ sub: String) -> Int {
            guard let dir = notebook?.localPath else { return 0 }
            return ((try? FileManager.default.contentsOfDirectory(atPath: dir + "/" + sub)) ?? []).filter { $0.hasSuffix(".md") && $0 != "README.md" }.count
        }
        let rulesText = notebook?.localPath.flatMap { try? String(contentsOfFile: $0 + "/" + Notebook.rulesPath, encoding: .utf8) }
        let rulesLines = rulesText.map { $0.split(separator: "\n", omittingEmptySubsequences: false).count } ?? 0

        // Whether the rules are where agents look in the app's clone.
        var rulesOK = false
        if let dir = app?.localPath, appProbe?.exists == true {
            let agents = try? String(contentsOfFile: dir + "/AGENTS.md", encoding: .utf8)
            if let agents, agents.hasPrefix(Notebook.placedMarker) {
                rulesOK = true; s.rulesState = "Rules placed in \(hxAbbreviated(dir)) as AGENTS.md and CLAUDE.md, never committed"
            } else if agents != nil, ProcessGit().succeeds(["ls-files", "--error-unmatch", "AGENTS.md"], in: dir) {
                rulesOK = true; s.rulesState = "The app commits its own AGENTS.md; the notebook's rules go in each brief"
            } else if agents != nil {
                s.rulesState = "A hand-written AGENTS.md in \(hxAbbreviated(dir)) is kept; the notebook's copy is not placed"
            } else {
                s.rulesState = "No rules in \(hxAbbreviated(dir)) yet"
            }
        } else {
            s.rulesState = "No app clone on this Mac"
        }

        // Checks, worst first.
        var checks: [HealthCheck] = []
        checks.append(connected ? .init(level: .ok, title: "GitHub connected")
                                : .init(level: .problem, title: "GitHub is not connected", detail: "Connect it in Settings › GitHub."))
        if let p = appProbe {
            checks.append(p.exists && p.matchesRemote ? .init(level: .ok, title: "App clone found", detail: hxAbbreviated(p.path))
                          : .init(level: .problem, title: "App clone missing or wrong", detail: hxAbbreviated(p.path), action: .openSettings))
            checks.append(p.knownBranches[integration] == true ? .init(level: .ok, title: "Hatch's branch \(integration) exists")
                          : .init(level: .attention, title: "Hatch's branch \(integration) not found here", detail: "It is created when the project is added; fetch to see it."))
        } else {
            checks.append(.init(level: .problem, title: "No app repository", action: .openSettings))
        }
        if let p = nbProbe {
            checks.append(p.exists ? .init(level: .ok, title: "Notebook clone found", detail: hxAbbreviated(p.path))
                                   : .init(level: .problem, title: "Notebook clone missing", detail: hxAbbreviated(p.path), action: .openSettings))
            if let a = p.ahead, a > 0 { checks.append(.init(level: .attention, title: "\(a) notebook commit\(a == 1 ? "" : "s") not pushed", action: .exportNotebook)) }
            if p.dirtyFiles > 0 { checks.append(.init(level: .attention, title: "\(p.dirtyFiles) uncommitted file\(p.dirtyFiles == 1 ? "" : "s") in the notebook", detail: "Saved with the next export.", action: .exportNotebook)) }
        } else {
            checks.append(.init(level: .problem, title: "No notebook", detail: "Decisions stay only on this Mac until a notebook is set.", action: .openSettings))
        }
        if let error = nb.error { checks.append(.init(level: .problem, title: "The notebook could not be saved", detail: error, action: .exportNotebook)) }
        if s.decisionsWaiting > 0 { checks.append(.init(level: .attention, title: "\(s.decisionsWaiting) decision\(s.decisionsWaiting == 1 ? "" : "s") not in the notebook yet", action: .exportNotebook)) }
        if let rulesText, !rulesOK, let dir = app?.localPath, appProbe?.exists == true {
            checks.append(.init(level: .attention, title: "Agent rules are not in the app's clone", detail: s.rulesState, action: .placeRules(rulesText, dir)))
        } else if rulesOK {
            checks.append(.init(level: .ok, title: "Agent rules in place"))
        }
        if summary.failed > 0 { checks.append(.init(level: .problem, title: "\(summary.failed) GitHub change\(summary.failed == 1 ? "" : "s") failed to sync", action: .syncNow)) }
        if let c = compProbe, !c.exists { checks.append(.init(level: .attention, title: "Components clone missing", detail: hxAbbreviated(c.path), action: .openSettings)) }
        s.checks = checks.sorted { rank($0.level) > rank($1.level) }

        // Repositories and what each holds.
        if let app { s.repos.append(.init(role: "App", remote: app.remote,
                                          holds: "The code. \(appProbe?.ticketBranches.count ?? 0) ticket branch(es) here, \(workspaces.filter { $0.repoId == app.id }.count) agent worktree(s). Work reaches \(app.defaultBranch) through \(integration).",
                                          probe: appProbe)) }
        if let notebook { s.repos.append(.init(role: "Notebook", remote: notebook.remote,
                                               holds: "\(count(Notebook.decisionsDir)) decision files, \(count(Notebook.specDir)) Spec files, rules of \(rulesLines) lines, \(((try? FileManager.default.contentsOfDirectory(atPath: (notebook.localPath ?? "") + "/" + Notebook.specimensDir)) ?? []).filter { !$0.hasSuffix(".md") }.count) specimen folder(s), NOW.md.",
                                               probe: nbProbe)) }
        if let components { s.repos.append(.init(role: "Components", remote: components.remote, holds: "Colors, type and shared views the app and Proposals import.", probe: compProbe)) }
        if let tickets = config?.ticketsRepo, !tickets.isEmpty {
            let open = ((try? store.tickets(TicketFilter(projectId: project.id))) ?? []).filter { !$0.status.isTerminal }.count
            s.repos.append(.init(role: "Tickets", remote: tickets, holds: "GitHub issues: \(open) open for \(project.name), mirrored in Hatch's database. No clone is needed.", probe: nil))
        }

        // Activity: notebook commits, GitHub sync and decisions, merged.
        var activity: [HealthActivity] = (nbProbe?.recent ?? []).map { .init(date: $0.date, source: "Notebook", text: "\($0.sha) \($0.subject)") }
        for op in ((try? store.syncLog(limit: 12)) ?? []) {
            let ticket = op.ticketId.flatMap { try? store.ticket(id: $0) }
            activity.append(.init(date: op.doneAt ?? op.at, source: "GitHub",
                                  text: "\(op.op)\(ticket.map { " \($0.displayNumber)" } ?? "") · \(op.state)\(op.error.map { ": \($0)" } ?? "")",
                                  failed: op.state == "failed"))
        }
        for d in decisions.prefix(8) {
            activity.append(.init(date: d.at, source: "Decision", text: "\(d.ticketNumber) \(d.title.isEmpty ? d.summary : d.title)" + (d.filePath == nil ? " (not in the notebook yet)" : "")))
        }
        s.activity = Array(activity.sorted { $0.date > $1.date }.prefix(20))
        return s
    }

    nonisolated private static func rank(_ l: HealthCheck.Level) -> Int { l == .problem ? 2 : l == .attention ? 1 : 0 }
}
