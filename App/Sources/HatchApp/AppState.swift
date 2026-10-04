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
    enum SnapshotPresentation { case settings, palette, addProject, repositorySelector, agentCard, markup, menuBar }

    let store: HatchStore
    let paths: AppPaths
    private var stageServer: StageServer?
    private var syncTimer: Timer?
    /// Looks every hour whether the daily backup and clean-up are due; separate from sync, which may be off.
    private var maintenanceTimer: Timer?
    /// True once services run; the timer may be off (Only when I ask) while changes still sync after a few seconds.
    private var syncStarted = false
    @Published private(set) var syncing = false
    private var syncDebounce: DispatchWorkItem?
    private var notebookDirty: Set<Int> = []
    private var notebookDebounce: DispatchWorkItem?

    /// Where the main window is, with its Back and Forward. Settings and ticket windows keep their own history.
    /// The page is remembered as it changes, so "When Hatch opens: The last page" can return to it (Settings › General).
    @Published private(set) var history = PageHistory<Route>(start: .desk) {
        didSet { if history.current != oldValue.current { rememberPlace() } }
    }
    var route: Route {
        get { history.current }
        set { history.replaceCurrent(with: newValue) }
    }
    /// A card the current page asks the Iris inspector to show at its top (the Desk's decision brief).
    @Published var inspectorTop: AnyView?
    @Published var selectedProjectKey: String? {        // nil means "All projects" (decision B2, B3)
        didSet { rememberProject(); updateWaitingCount(); if selectedProjectKey != oldValue { refreshDecisionCount() } }
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
    /// Settings › General: Hatch's item in the menu bar, on by default. Snapshot runs never add it to the real menu bar.
    @Published var showMenuBarItem = Snapshots.folder == nil
    /// Settings › General: whether the Dock icon shows how many tickets wait for you.
    var dockBadgeShown = true
    /// Tickets waiting for the owner, counted once per change for the Dock badge and the menu bar item.
    @Published private(set) var waitingCount = 0
    /// Today's tokens against the daily limits on Settings › Usage; above the pause limit no new work starts.
    @Published var usageLevel: UsageLimits.Level = .fine
    var launcher: AgentLauncher?
    var launchTimer: Timer?
    /// The daily backup and clean-up (Settings › Storage): when it last ran, and whether it is running now.
    var storageMaintainedAt: Date?
    var maintainingStorage = false
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
            let state = AppState(store: store, paths: paths)
            state.applyLaunchPreferences()
            return state
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
        // A ticket from any app (WF-C2); not while taking snapshots or showing demo data.
        if Snapshots.folder == nil, !Snapshots.demoMode {
            QuickCapture.shared.start(state: self)
            #if DEBUG
            // `--show-quick-capture ["text"]` opens the bar at launch, to look at it without pressing the key.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--show-quick-capture") {
                let text = i + 1 < args.count && !args[i + 1].hasPrefix("-") ? args[i + 1] : ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { QuickCapture.shared.show(prefill: text) }
            }
            if let i = args.firstIndex(of: "--quick-capture-markup"), i + 1 < args.count, let data = FileManager.default.contents(atPath: args[i + 1]) {
                QuickCapture.shared.draft.shots = [PendingShot(name: "shot.png", data: data)]
                QuickCapture.shared.draft.openMarkupOnShow = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { QuickCapture.shared.show() }
            }
            #endif
        }
        maintainStorageIfDue()
        if maintenanceTimer == nil {
            maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.maintainStorageIfDue() }
            }
        }
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
        guard !syncStarted else { return }
        syncStarted = true
        syncNow()
        restartSyncTimer()
    }

    /// The `sync_interval` setting: seconds between checks of GitHub, 0 for only when the owner asks. Default a minute.
    static let syncIntervalSetting = "sync_interval"

    var syncInterval: Int {
        hxSetting(Self.syncIntervalSetting).flatMap(Int.init) ?? 60
    }

    /// Starts the timer again with the saved interval, after Settings › GitHub changes it.
    func restartSyncTimer() {
        syncTimer?.invalidate(); syncTimer = nil
        guard syncStarted, syncInterval > 0 else { return }
        syncTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(syncInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
    }

    func syncNow() {
        guard !syncing else { return }
        let targets: [(repo: String, projectId: Int, branch: String, ci: (remote: String, ref: String)?)] = projects.compactMap { p in
            guard let repo = p.config?.ticketsRepo, !repo.isEmpty else { return nil }
            // CI on the integration branch is read only while something merged waits for it (decision I6).
            let merged = !((try? store.tickets(TicketFilter(projectId: p.id, statuses: [.merged]))) ?? []).isEmpty
            let ci = merged ? p.config?.repo(.app).map { ($0.remote, p.config?.integrationBranch ?? "hatch") } : nil
            return (repo, p.id, p.config?.repo(.tickets)?.branch ?? "main", ci)
        }
        guard !targets.isEmpty else { return }
        syncing = true
        let store = store, root = paths.root
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
                        // Screenshots go to the tickets repo once their issue exists; their comments go out right after (M3).
                        if try engine.uploadAttachments(repo: target.repo, projectId: target.projectId, root: root, branch: target.branch) > 0 {
                            _ = try engine.pushPending(repo: target.repo)
                        }
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
        syncStarted = false
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

    /// Counts the waiting tickets and shows them on the Dock icon, unless Settings › General turned the badge off.
    func updateWaitingCount() {
        let count = yourTurnCount
        if waitingCount != count { waitingCount = count }
    }

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
        if syncSummary.pending > 0, syncStarted { scheduleSync() }
        // Every change may move a ticket or record a decision: refresh the notebooks shortly after the last one.
        if syncStarted { scheduleNotebookExport() }
        updateWaitingCount()
        refreshDecisionCount()
    }

    /// Reads the decision count and puts it on the Dock icon.
    func refreshDecisionCount() {
        let n = store.pendingDecisionCount(projectId: projectFilterId)
        if n != decisionCount { decisionCount = n }
        NSApp?.dockTile.badgeLabel = dockBadgeShown && n > 0 ? String(n) : nil
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
        history.visit(destination)
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

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
    var backTitle: String? { history.backPage?.title }

    func goBack() { history.goBack() }
    func goForward() { history.goForward() }
}

/// Where Hatch keeps its files (database, token, caches). Overridable with HATCH_HOME for tests and the CLI.
struct AppPaths: Sendable {
    let root: URL
    var database: URL { root.appendingPathComponent("hatch.sqlite") }
    var workspaces: URL { root.appendingPathComponent("workspaces", isDirectory: true) }
    /// Agent run logs, one JSON Lines file per run (AgentLauncher).
    var runs: URL { root.appendingPathComponent("runs", isDirectory: true) }
    /// Daily or weekly copies of the database (Settings › Storage).
    var backups: URL { root.appendingPathComponent("backups", isDirectory: true) }
    /// Local copies of screenshots added to tickets, by ticket id.
    var attachments: URL { root.appendingPathComponent("attachments", isDirectory: true) }

    static var `default`: AppPaths {
        if let override = ProcessInfo.processInfo.environment["HATCH_HOME"] { return AppPaths(root: URL(fileURLWithPath: override)) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return AppPaths(root: base.appendingPathComponent("Hatch", isDirectory: true))
    }
}
