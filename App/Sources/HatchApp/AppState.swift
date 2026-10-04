import SwiftUI
import HatchCore
import HatchSync
import HatchAPI

/// The one object every screen reads. It wraps the store (the only place state changes, decision S3), re-publishes after every
/// change, and holds navigation and panel state. Screens never write SQL; they call store methods inside `perform`.
@MainActor
final class AppState: ObservableObject {
    enum SnapshotPresentation { case settings, palette, addProject, repositorySelector }

    let store: HatchStore
    let paths: AppPaths
    private var stageServer: StageServer?
    private var syncTimer: Timer?
    private var syncing = false
    private var syncDebounce: DispatchWorkItem?

    @Published var route: Route = .desk
    @Published private(set) var backStack: [Route] = []
    @Published private(set) var forwardStack: [Route] = []
    /// A card the current page asks the Iris inspector to show at its top (the Desk's decision brief).
    @Published var inspectorTop: AnyView?
    @Published var selectedProjectKey: String?          // nil means "All projects" (decision B2, B3)
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
    @Published var showPalette = false
    @Published var showAddProject = false
    @Published var searchText = ""
    @Published var syncSummary = SyncSummary()
    /// Snapshot harness only: selects each ticket subview without changing the normal navigation model.
    @Published var snapshotTicketTab: TicketTab?
    @Published var snapshotPresentation: SnapshotPresentation?
    /// Snapshot harness only: which add-project step to show.
    @Published var snapshotSetupStep = 0

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
        let targets: [(repo: String, projectId: Int)] = projects.compactMap { p in
            guard let repo = p.config?.ticketsRepo, !repo.isEmpty else { return nil }
            return (repo, p.id)
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
                    } catch {
                        message = "\(target.repo): \(error)"
                    }
                }
                return (message == nil, message)
            }.value
            syncing = false
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

    func stopServices() {
        syncTimer?.invalidate(); syncTimer = nil
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
        let configURL = config.repo(.app)?.localPath.map {
            URL(fileURLWithPath: $0).appendingPathComponent(".hatch/project.json")
        }
        return perform("Save repositories") {
            try store.upsertProject(key: project.key, name: project.name, config: config)
            if let configURL { try config.save(to: configURL) }
            return true
        } ?? false
    }

    /// Tickets waiting for the owner, for the Dock badge and the sidebar (decision B6).
    var yourTurnCount: Int { ((try? store.countByTurn(projectId: projectFilterId)) ?? [:])[.you] ?? 0 }

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
        NSApp?.dockTile.badgeLabel = yourTurnCount > 0 ? String(yourTurnCount) : nil
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
        guard destination != route else { return }
        backStack.append(route)
        forwardStack.removeAll()
        route = destination
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
