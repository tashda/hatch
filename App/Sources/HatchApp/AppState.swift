import SwiftUI
import HatchCore
import HatchSync
import HatchAPI
import HatchGit
import HatchAgent
import HatchImport

/// The one object every screen reads. It wraps the store (the only place state changes, decision S3), re-publishes after every
/// change, and holds navigation and panel state. Screens never write SQL; they call store methods inside `perform`.
@MainActor
final class AppState: ObservableObject {
    enum SnapshotPresentation { case settings, palette, addProject, repositorySelector, agentCard }

    let store: HatchStore
    let paths: AppPaths
    private var stageServer: StageServer?
    private var syncTimer: Timer?
    @Published private(set) var syncing = false
    private var syncDebounce: DispatchWorkItem?
    private var notebookDirty: Set<Int> = []
    private var notebookDebounce: DispatchWorkItem?

    @Published var route: Route = .desk
    @Published private(set) var backStack: [Route] = []
    @Published private(set) var forwardStack: [Route] = []
    /// A card the current page asks the Iris inspector to show at its top (the Desk's decision brief).
    @Published var inspectorTop: AnyView?
    @Published var selectedProjectKey: String? {        // nil means "All projects" (decision B2, B3)
        didSet { if selectedProjectKey != oldValue { refreshDecisionCount() } }
    }
    @Published var selectedTicketId: Int?
    @Published var revision = 0                          // bumped after any change so views reload
    @Published var errorMessage: String?
    /// Hatch check results from New ticket, shown in the Iris inspector while that page is open.
    @Published var hatchCheck: HatchCheckState?
    @Published var showSidebar = UserDefaults.standard.object(forKey: "hatch.showSidebar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showSidebar, forKey: "hatch.showSidebar") }
    }
    @Published var showAskPanel = UserDefaults.standard.bool(forKey: "hatch.showAskPanel") {
        didSet { UserDefaults.standard.set(showAskPanel, forKey: "hatch.showAskPanel") }
    }
    /// Closing resets the scope, so ⌘K and the toolbar's Search always open on Tickets.
    @Published var showPalette = false {
        didSet { if !showPalette { paletteScope = .tickets } }
    }
    @Published var paletteScope: PaletteScope = .tickets
    @Published var showAddProject = false
    /// The Settings page to show when the Settings window opens next (or now, if it is open).
    @Published var settingsPage: SettingsPage?
    @Published var searchText = ""
    /// A title for New ticket to start with (⌘Return in the palette); the composer takes it once.
    @Published var composerTitle: String?
    /// Tickets opened most recently, newest first, for the palette's Recent group.
    @Published private(set) var recentTicketIds: [Int] = UserDefaults.standard.array(forKey: "hatch.recentTickets") as? [Int] ?? []
    @Published var syncSummary = SyncSummary()
    /// Set when writing or pushing a notebook failed; the footer shows it until the next export works.
    @Published var notebookProblem: String?
    /// Agents the launcher is running now, for the footer, the ticket and the Agents page.
    @Published var agentRuns: [AgentRunInfo] = []
    @Published var agentsPaused = false
    var launcher: AgentLauncher?
    var launchTimer: Timer?
    @Published private(set) var exportingNotebooks = false
    /// Snapshot harness only: selects each ticket subview without changing the normal navigation model.
    @Published var snapshotTicketTab: TicketTab?
    @Published var snapshotPresentation: SnapshotPresentation?
    /// Snapshot harness only: which add-project step to show.
    @Published var snapshotSetupStep = 0
    /// How many decisions wait for the owner: the one number the Desk row, the toolbar button and the Dock show (DC12).
    @Published private(set) var decisionCount = 0
    /// The Decide session, when open (decisions DC1 to DC7). `area` limits it, as the Components page does (DC9).
    @Published var decideSession: DecideRequest?
    private var countTimer: Timer?

    struct DecideRequest: Identifiable, Equatable {
        let id = UUID()
        var area: String? = nil
    }

    struct SyncSummary: Equatable {
        var pending = 0
        var failed = 0
        var lastOK: Date?
        var message: String?
    }

    init(store: HatchStore, paths: AppPaths) {
        self.store = store
        self.paths = paths
        refreshSyncSummary()
        refreshDecisionCount()
    }

    static func live() -> AppState {
        let paths = AppPaths.default
        do {
            let store = try HatchStore(path: paths.database.path)
            return AppState(store: store, paths: paths)
        } catch {
            // The app must still open so the owner sees the message; fall back to a throwaway in-memory store.
            let store = try! HatchStore.inMemory()
            let state = AppState(store: store, paths: paths)
            state.errorMessage = "Could not open the Hatch database: \(error)"
            return state
        }
    }

    /// Starts the local API the Stage talks to (decision S3) and the notification bridge. Safe to call more than once.
    func startServices() {
        NotificationCenterBridge.shared.start(state: self)
        startSync()
        // Sync and agents change things outside this window, so the count is read again every few seconds too.
        if countTimer == nil {
            countTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshDecisionCount() }
            }
        }
        startLauncher()
        guard stageServer == nil else { return }
        let server = StageServer(store: store, paths: HatchPaths(home: paths.root))
        server.events = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        do {
            try server.start()
            stageServer = server
        } catch {
            errorMessage = "Could not start the Stage connection: \(error)"
        }
    }

    /// Pushes queued changes to the tickets repository of every project and pulls what changed there. Off the main thread;
    /// the sidebar footer shows the result (decision B5). Runs on a timer, shortly after a change, and from the Go menu.
    func startSync() {
        guard syncTimer == nil else { return }
        syncNow()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
    }

    func syncNow() {
        guard !syncing else { return }
        let targets: [(repo: String, projectId: Int, ci: (remote: String, ref: String)?)] = projects.compactMap { p in
            guard let repo = p.config?.ticketsRepo, !repo.isEmpty else { return nil }
            // CI on the integration branch is read only while something merged waits for it (decision I6).
            let merged = !((try? store.tickets(TicketFilter(projectId: p.id, statuses: [.merged]))) ?? []).isEmpty
            let ci = merged ? p.config?.repo(.app).map { ($0.remote, p.config?.integrationBranch ?? "hatch") } : nil
            return (repo, p.id, ci)
        }
        guard !targets.isEmpty else { return }
        syncing = true
        let store = store
        Task {
            let outcome = await Task.detached { () -> (ok: Bool, message: String?) in
                guard HXKeychain.read() != nil else {
                    return (false, "Not connected to GitHub. Add a token in Settings.")
                }
                let engine = SyncEngine(store: store, tracker: HXGitHub.client())
                var message: String?
                for target in targets {
                    do {
                        _ = try engine.pushPending(repo: target.repo)
                        _ = try engine.pull(repo: target.repo, projectId: target.projectId)
                        if let ci = target.ci { try engine.checkCI(projectId: target.projectId, repo: ci.remote, ref: ci.ref) }
                    } catch {
                        message = "\(target.repo): \(error)"
                    }
                }
                return (message == nil, message)
            }.value
            syncing = false
            scheduleNotebookExport()
            if outcome.ok { syncSummary.lastOK = Date() }
            syncSummary.message = outcome.message
            refreshSyncSummary()
        }
    }

    /// Called after a change: sync a few seconds later, once, however many changes came in.
    private func scheduleSync() {
        syncDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in self?.syncNow() } }
        syncDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    /// Notebook writes are batched: at most one export every few seconds, however many changes come in. A pending
    /// export is not pushed back, so steady changes cannot postpone it forever.
    private func scheduleNotebookExport() {
        guard notebookDebounce == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.notebookDebounce = nil
                self?.exportNotebooks()
            }
        }
        notebookDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// Brings every project's notebook in step with the database: Spec indexed from it, decision files written or
    /// imported, NOW.md refreshed, one commit and a push. Local git and file work only, no model, so it costs no tokens.
    func exportNotebooks() {
        guard !exportingNotebooks, Snapshots.folder == nil, !Snapshots.demoMode else { return }
        let projects = projects.filter { $0.config?.repo(.notebook)?.localPath != nil }
        guard !projects.isEmpty else { return }
        exportingNotebooks = true
        notebookDirty.removeAll()
        let store = store
        Task {
            let problem = await Task.detached { () -> String? in
                let token = HXKeychain.read()
                var problems: [String] = []
                for project in projects {
                    do {
                        try SpecIndexer.indexNotebook(project: project, store: store)
                        try NotebookExport.run(store: store, projectId: project.id, token: token)
                        if let error = try store.notebookError(projectId: project.id) { problems.append("\(project.name): \(error)") }
                    } catch {
                        problems.append("\(project.name) notebook: \(error)")
                    }
                }
                return problems.isEmpty ? nil : problems.joined(separator: " · ")
            }.value
            exportingNotebooks = false
            notebookProblem = problem
        }
    }

    func stopServices() {
        syncTimer?.invalidate(); syncTimer = nil
        launchTimer?.invalidate(); launchTimer = nil
        stageServer?.stop()
        stageServer = nil
    }

    // MARK: Data helpers used by many screens

    var projects: [Project] { (try? store.projects()) ?? [] }

    var selectedProject: Project? {
        guard let key = selectedProjectKey else { return nil }
        return projects.first { $0.key == key }
    }

    /// Project filter for queries: nil when "All projects" is selected.
    var projectFilterId: Int? { selectedProject?.id }

    func project(id: Int) -> Project? { projects.first { $0.id == id } }
    func hasTickets(projectId: Int) -> Bool { (try? store.hasTickets(projectId: projectId)) ?? false }

    /// Apply repository choices without silently saving unrelated edits in the Project form.
    @discardableResult
    func saveRepositoryAssignments(projectId: Int, _ assignments: HXRepositoryAssignments) -> Bool {
        guard let project = project(id: projectId) else { return false }
        var config = project.config ?? ProjectConfig(name: project.name, ticketsRepo: "")
        assignments.apply(to: &config)
        return saveProject(key: project.key, name: project.name, config: config, label: "Save repositories") != nil
    }

    /// What became of the notebook's copy of a project's settings.
    enum NotebookSave: Equatable {
        case committed, unchanged, noNotebook
        case failed(String)
    }

    /// Saves a project's settings in Hatch, then as `project.json` in its notebook, never in the app repository (PS13).
    /// The notebook's copy leaves out the folders on this Mac, since they are not shared. The file is written and
    /// committed off the main thread; the push follows with the batched notebook export.
    @discardableResult
    func saveProject(key: String, name: String, config: ProjectConfig, label: String = "Save project",
                     notebook: @escaping @MainActor (NotebookSave) -> Void = { _ in }) -> Project? {
        guard let project = perform(label, { try store.upsertProject(key: key, name: name, config: config) }) else { return nil }
        guard let folder = config.repo(.notebook)?.localPath, !folder.isEmpty else {
            notebook(.noNotebook)
            return project
        }
        var shared = config
        shared.repos = shared.repos.map { var repo = $0; repo.localPath = nil; return repo }
        let projectId = project.id
        Task {
            let result = await Task.detached { () -> Result<Bool, Error> in
                Result {
                    try shared.save(to: URL(fileURLWithPath: folder).appendingPathComponent(Notebook.configPath))
                    return try NotebookWriter.commit("Update project settings", in: folder)
                }
            }.value
            switch result {
            case .success(let committed):
                if committed { notebookChanged(projectId: projectId) }
                notebook(committed ? .committed : .unchanged)
            case .failure(let error):
                notebook(.failed((error as? GitError)?.description ?? "\(error)"))
            }
        }
        return project
    }

    /// Tickets waiting for the owner, for the Dock badge and the sidebar (decision B6).
    var yourTurnCount: Int { ((try? store.countByTurn(projectId: projectFilterId)) ?? [:])[.you] ?? 0 }

    /// Called after anything is written to a project's notebook clone: Hatch commits and pushes it in the background.
    func notebookChanged(projectId: Int) {
        notebookDirty.insert(projectId)
        scheduleNotebookExport()
    }

    // MARK: Changing things

    /// Runs a store change, refreshes every view, and turns an error into a message the owner can read.
    @discardableResult
    func perform<T>(_ label: String = "", _ work: () throws -> T) -> T? {
        do {
            let result = try work()
            refresh()
            return result
        } catch {
            errorMessage = label.isEmpty ? "\(error)" : "\(label): \(error)"
            return nil
        }
    }

    func refresh() {
        revision += 1
        refreshSyncSummary()
        if syncSummary.pending > 0, syncTimer != nil { scheduleSync() }
        // Every change may move a ticket or record a decision: refresh the notebooks shortly after the last one.
        if syncTimer != nil { scheduleNotebookExport() }
        refreshDecisionCount()
    }

    /// Reads the decision count and puts it on the Dock icon.
    func refreshDecisionCount() {
        let n = store.pendingDecisionCount(projectId: projectFilterId)
        if n != decisionCount { decisionCount = n }
        NSApp?.dockTile.badgeLabel = n > 0 ? String(n) : nil
    }

    /// Opens a Decide session over everything waiting, or only one area's decisions.
    func openDecide(area: String? = nil) {
        showPalette = false
        decideSession = DecideRequest(area: area)
    }

    func refreshSyncSummary() {
        let counts = (try? store.syncCounts()) ?? (pending: 0, failed: 0)
        syncSummary.pending = counts.pending
        syncSummary.failed = counts.failed
    }

    func open(_ ticket: Ticket) {
        selectedTicketId = ticket.id
        navigate(to: .ticket(ticket.id))
    }

    /// Every page change goes through here, so Back and Forward always return to where you were.
    func navigate(to destination: Route) {
        if case .ticket(let id) = destination { noteRecent(id) }
        guard destination != route else { return }
        backStack.append(route)
        forwardStack.removeAll()
        route = destination
    }

    /// Opens the palette on a scope; the same shortcut again closes it, as Spotlight does.
    func openPalette(_ scope: PaletteScope = .tickets) {
        if showPalette && paletteScope == scope { showPalette = false; return }
        paletteScope = scope
        showPalette = true
    }

    private func noteRecent(_ id: Int) {
        recentTicketIds = Array(([id] + recentTicketIds.filter { $0 != id }).prefix(12))
        UserDefaults.standard.set(recentTicketIds, forKey: "hatch.recentTickets")
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var backTitle: String? { backStack.last?.title }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(route)
        route = previous
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(route)
        route = next
    }
}

/// Where Hatch keeps its files (database, token, caches). Overridable with HATCH_HOME for tests and the CLI.
struct AppPaths {
    let root: URL
    var database: URL { root.appendingPathComponent("hatch.sqlite") }
    var workspaces: URL { root.appendingPathComponent("workspaces", isDirectory: true) }

    static var `default`: AppPaths {
        if let override = ProcessInfo.processInfo.environment["HATCH_HOME"] { return AppPaths(root: URL(fileURLWithPath: override)) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return AppPaths(root: base.appendingPathComponent("Hatch", isDirectory: true))
    }
}
