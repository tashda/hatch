import SwiftUI
import AppKit
import Combine
import HatchCore
import HatchSync
import HatchGit

// The add-project assistant (design-review/add-project-concepts.html, concept A): one sheet, one step per part of a
// project, each explained once and filled in from the app repository so most steps are only Continue.

/// The setting that names the tickets repository new projects use unless told otherwise.
let hxDefaultTicketsSetting = "tickets.default"

@MainActor
final class ProjectSetupModel: ObservableObject {
    enum Step: Int, CaseIterable, Identifiable {
        case github, project, tickets, design, notebook, branches, agents, review
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .github: "GitHub"
            case .project: "Project"
            case .tickets: "Tickets"
            case .design: "Components"
            case .notebook: "Notebook"
            case .branches: "Branches"
            case .agents: "Agents"
            case .review: "Review"
            }
        }
    }

    enum TicketsChoice { case useDefault, create, existing }
    /// Components (decision CO2): use a folder Hatch found in the app, start them with draft tickets, use a separate
    /// repository (a package several apps share), or not now.
    enum DesignChoice { case found, start, separate, none }
    enum NotebookChoice { case create, existing }

    @Published var step: Step = .github
    @Published var name = ""
    @Published var nameEdited = false
    /// Follows the name until the owner types their own key.
    @Published var keyText = ""
    @Published var keyEdited = false

    @Published var ticketsChoice: TicketsChoice = .create
    @Published var newTicketsName = "hatch-tickets"
    @Published var existingTickets: String?
    @Published var makeDefault = true
    let defaultTickets: String?
    private let savedDefault: String?
    private var forwarders: [AnyCancellable] = []

    @Published var appRepo: String? { didSet { appRepoChanged(from: oldValue) } }
    @Published var localPath: String? { didSet { if localPath != oldValue { suggestBuild(); inspectRules(); scanComponents() } } }
    @Published var clones: [String] = []
    @Published var searchingClones = false
    @Published var cloning = false

    @Published var designChoice: DesignChoice = .start
    /// Set once the owner picks a choice, so a finished scan no longer changes it.
    @Published var designTouched = false
    @Published var componentsScan: ComponentsScan?
    @Published var scanningComponents = false
    /// The found folder to use, relative to the app's clone.
    @Published var foundPath: String?
    /// Where new components go; follows the project name until the owner types their own.
    @Published var startPath = ""
    @Published var startPathEdited = false
    /// With more than one set found: add a draft ticket to merge the others into the chosen one (CO9).
    @Published var mergeOthers = true
    @Published var designExisting: String? { didSet { if designExisting != oldValue { designPath = nil; findClone(of: designExisting) { [weak self] in self?.designPath = $0 } } } }
    /// The clone of a separate components repository on this Mac; agents building a ticket work in it too.
    @Published var designPath: String?

    @Published var notebookChoice: NotebookChoice = .create
    @Published var notebookNewName = ""
    @Published var notebookNameEdited = false
    @Published var notebookExisting: String?
    @Published var notebookPath: String?
    /// The app clone's own agent file, which becomes the notebook's rules: its line count, or nil when there is none.
    @Published var existingRulesLines: Int?
    @Published var appCommitsRules = false

    @Published var branches: [String] = []
    @Published var baseBranch = ""
    @Published var integrationBranch = "hatch"
    @Published var promotion: Promotion = .pullRequest
    @Published var useAgentDefaults = true
    @Published var maxAgents = ProjectSetupModel.defaultMaxAgents
    @Published var planThreshold = ProjectSetupModel.defaultPlanThreshold
    @Published var buildCommand = ""
    @Published var testCommand = ""
    /// What `buildCommand` was filled with from the clone, so the defaults can show it.
    @Published var suggestedBuild: String?
    static let defaultMaxAgents = 3
    static let defaultPlanThreshold = 8

    @Published var adding = false
    @Published var error: String?

    /// Snapshot runs: sample data, no network or disk.
    private var demo = false

    let account = GitHubAccountModel()
    let deviceFlow = GitHubDeviceFlow()
    private let existingKeys: [String]

    init(store: HatchStore) {
        let projects = (try? store.projects()) ?? []
        existingKeys = projects.map(\.key)
        let saved = (try? store.setting(hxDefaultTicketsSetting)) ?? nil
        savedDefault = saved
        // Without a saved default, the tickets repository an existing project uses is the obvious one to share.
        defaultTickets = saved ?? projects.compactMap { $0.config?.ticketsRepo }.first { !$0.isEmpty }
        if defaultTickets != nil { ticketsChoice = .useDefault; makeDefault = false }
        // The pages read the account and the sign-in through this model, so it republishes their changes.
        forwarders = [account.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
                      deviceFlow.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }]
    }

    var login: String? { account.user?.login }
    var connected: Bool { account.user != nil }
    var suggestedKey: String { ProjectConfig.key(for: name, existing: existingKeys) }
    var key: String {
        let typed = keyText.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? suggestedKey : ProjectConfig.key(for: typed, existing: existingKeys)
    }

    func setName(_ value: String, edited: Bool) {
        name = value
        nameEdited = edited
        if !keyEdited { keyText = name.trimmingCharacters(in: .whitespaces).isEmpty ? "" : suggestedKey }
    }
    var displayName: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? "Project" : name.trimmingCharacters(in: .whitespaces) }
    var privateRepos: [GitHubRepoSummary] { account.repos.filter(\.isPrivate) }
    var appRepoSummary: GitHubRepoSummary? { account.repos.first { $0.fullName == appRepo } }

    var ticketsRepo: String? {
        switch ticketsChoice {
        case .useDefault: return defaultTickets
        case .existing: return existingTickets
        case .create:
            let n = newTicketsName.trimmingCharacters(in: .whitespaces)
            guard let login, !n.isEmpty else { return nil }
            return "\(login)/\(n)"
        }
    }

    /// The clone folder offered when none is found: next to other code, named after the repository.
    /// Where a new repository goes: the app repository's owner, or the signed-in account.
    var newRepoOwner: String { appRepo?.split(separator: "/").first.map(String.init) ?? login ?? "you" }

    /// A separate components repository, the advanced choice.
    var designRepo: String? { designChoice == .separate ? designExisting : nil }

    /// Components inside the app: a folder found there, or the one the start ticket makes.
    var componentsConfig: ComponentsConfig? {
        switch designChoice {
        case .found:
            return componentsScan?.candidates.first { $0.path == foundPath }?.config
        case .start:
            let path = (startPathEdited ? startPath : ComponentsConfig.suggested(appName: displayName).path)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard !path.isEmpty else { return nil }
            return ComponentsConfig(path: path, product: (path as NSString).lastPathComponent)
        case .separate, .none:
            return nil
        }
    }

    /// The components folder chosen among those found, and the other sets beside it.
    var chosenCandidate: ComponentsCandidate? { designChoice == .found ? componentsScan?.candidates.first { $0.path == foundPath } : nil }
    var otherCandidates: [ComponentsCandidate] { (componentsScan?.candidates ?? []).filter { $0.path != chosenCandidate?.path } }

    /// Names with two values between the chosen set and the others (CO11).
    var clashes: [NameClash] {
        guard let chosen = chosenCandidate else { return [] }
        return ComponentConflicts.clashes(chosen: chosen, others: otherCandidates)
    }

    /// What the Add makes for the components, worked out off the main thread once the project exists.
    var componentTicketPlan: HXComponentTicketPlan {
        HXComponentTicketPlan(choice: designChoice, appName: displayName, config: componentsConfig, scan: componentsScan,
                              chosen: chosenCandidate, others: designChoice == .found && mergeOthers ? otherCandidates : [], clashes: clashes)
    }

    func chooseDesign(_ choice: DesignChoice) {
        designChoice = choice
        designTouched = true
    }

    /// Reads the app's clone for components and typed-in values. A finished scan picks the likely choice until the
    /// owner picks one: use what was found, else start them.
    private func scanComponents() {
        guard let path = localPath, !demo else { return }
        scanningComponents = true
        Task {
            let scan = await Task.detached { ComponentsScanner.scan(appRoot: path) }.value
            guard localPath == path else { return }
            componentsScan = scan
            scanningComponents = false
            if foundPath == nil || !scan.candidates.contains(where: { $0.path == foundPath }) { foundPath = scan.candidates.first?.path }
            if !designTouched { designChoice = scan.candidates.isEmpty ? .start : .found }
        }
    }

    var notebookRepo: String? {
        switch notebookChoice {
        case .existing: return notebookExisting
        case .create:
            let n = notebookNewName.trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? nil : "\(newRepoOwner)/\(n)"
        }
    }

    /// A folder next to the app's clone, for the other repositories of the project.
    func siblingFolder(for repo: String) -> String {
        let parent = URL(fileURLWithPath: localPath ?? cloneDestination).deletingLastPathComponent()
        return parent.appendingPathComponent(repo.split(separator: "/").last.map(String.init) ?? repo).path
    }

    var cloneDestination: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let parent = ["Development", "Developer", "Projects", "Code"].map { home.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) } ?? home.appendingPathComponent("Development")
        let repoName = appRepo?.split(separator: "/").last.map(String.init) ?? "app"
        return parent.appendingPathComponent(repoName).path
    }

    func canContinue(_ step: Step) -> Bool {
        switch step {
        case .github: return connected
        case .project: return appRepo != nil && localPath != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .tickets: return ticketsRepo != nil
        case .design: return designChoice == .none || designRepo != nil || componentsConfig != nil
        case .notebook: return notebookRepo != nil
        case .agents: return true
        case .branches: return !baseBranch.isEmpty && !integrationBranch.trimmingCharacters(in: .whitespaces).isEmpty
                                && integrationBranch != baseBranch
        case .review: return !adding
        }
    }

    func isDone(_ s: Step) -> Bool { s.rawValue < step.rawValue || (s == .github && connected) }

    /// Steps can be visited out of order only backwards, or forwards over steps that are already complete.
    func canOpen(_ s: Step) -> Bool {
        s.rawValue <= step.rawValue || Step.allCases.filter { $0.rawValue < s.rawValue }.allSatisfy(canContinue)
    }

    func next() {
        guard let n = Step(rawValue: step.rawValue + 1) else { return }
        step = n
    }

    func back() {
        guard let p = Step(rawValue: step.rawValue - 1) else { return }
        step = p
    }

    func start() {
        account.refresh()
    }

    /// Called when the account check finishes: a connected account skips the GitHub step.
    func accountChanged() {
        if connected && step == .github { step = .project }
    }

    /// Fills every step with sample data for the snapshot harness and opens `step`.
    func fillDemo(step: Step) {
        demo = true
        account.user = GitHubUser(login: "tashda", name: "Kenneth Berg")
        account.repos = [GitHubRepoSummary(fullName: "tashda/echo", isPrivate: true, defaultBranch: "dev"),
                         GitHubRepoSummary(fullName: "tashda/hatch-tickets", isPrivate: true)]
        ticketsChoice = .create
        appRepo = "tashda/echo"
        localPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Development/echo").path
        clones = [localPath!]
        branches = ["main", "dev"]
        var tokens = ComponentCatalog()
        ComponentReader.read("public extension Color {\n static let surface = Color.secondary\n static let accent = Color.blue\n}\npublic enum Spacing { public static let m: CGFloat = 12 }\npublic struct Card: View { }\n",
                             file: "Tokens.swift", requirePublic: true, into: &tokens)
        componentsScan = ComponentsScan(candidates: [ComponentsCandidate(path: "Packages/EchoDesignSystem", isPackage: true, product: "EchoDesignSystem", catalog: tokens)],
                                        typed: [.color: 57, .font: 186, .size: 559], typedFiles: [], swiftFiles: 2566)
        foundPath = "Packages/EchoDesignSystem"
        designChoice = .found
        existingRulesLines = 474
        self.step = step
    }

    private func appRepoChanged(from old: String?) {
        guard appRepo != old, let repo = appRepo else { return }
        if !nameEdited || name.isEmpty {
            let raw = repo.split(separator: "/").last.map(String.init) ?? repo
            setName(raw.prefix(1).uppercased() + raw.dropFirst(), edited: false)
        }
        if !notebookNameEdited { notebookNewName = Notebook.suggestedName(appRepo: repo) }
        baseBranch = appRepoSummary?.defaultBranch ?? "main"
        branches = []
        guard !demo else { return }
        localPath = nil
        clones = []
        componentsScan = nil
        foundPath = nil
        loadBranches(repo)
        findClones(repo)
    }

    private func loadBranches(_ repo: String) {
        Task {
            let names = await Task.detached { (try? HXGitHub.client().listBranches(repo)) ?? [] }.value
            guard appRepo == repo else { return }
            branches = names
            if !names.contains(baseBranch), let first = names.first { baseBranch = first }
        }
    }

    private func findClones(_ repo: String) {
        searchingClones = true
        Task {
            let found = await Task.detached { LocalClones.find(repo) }.value
            guard appRepo == repo else { return }
            clones = found
            if localPath == nil { localPath = found.first }
            searchingClones = false
        }
    }

    /// Looks for a clone of `repo` in the usual code folders and reports the first one found.
    func findClone(of repo: String?, found: @escaping (String?) -> Void) {
        guard let repo, !demo else { return }
        Task {
            let paths = await Task.detached { LocalClones.find(repo) }.value
            found(paths.first)
        }
    }

    /// Whether the app's clone has its own agent file to carry into the notebook, or commits one.
    private func inspectRules() {
        guard let path = localPath, !demo else { return }
        Task {
            let (text, committed) = await Task.detached { () -> (String?, Bool) in
                (RulesPlacer.existingRules(in: path), ProcessGit().succeeds(["ls-files", "--error-unmatch", "AGENTS.md"], in: path))
            }.value
            existingRulesLines = text.map { $0.split(separator: "\n", omittingEmptySubsequences: false).count }
            appCommitsRules = committed
        }
    }

    private func suggestBuild() {
        guard let path = localPath else { suggestedBuild = nil; return }
        let suggestion = demo ? "xcodebuild -project Echo.xcodeproj -scheme Echo build" : BuildCommand.suggest(in: path)
        if buildCommand.isEmpty || buildCommand == suggestedBuild { buildCommand = suggestion ?? "" }
        suggestedBuild = suggestion
    }

    /// The values the project is saved with: the defaults, or what the owner typed.
    var effectiveAgents: (max: Int, threshold: Int, build: String?, test: String?) {
        if useAgentDefaults { return (Self.defaultMaxAgents, Self.defaultPlanThreshold, suggestedBuild, nil) }
        let b = buildCommand.trimmingCharacters(in: .whitespaces), t = testCommand.trimmingCharacters(in: .whitespaces)
        return (maxAgents, planThreshold, b.isEmpty ? nil : b, t.isEmpty ? nil : t)
    }

    func clone() {
        guard let repo = appRepo else { return }
        let destination = cloneDestination
        cloning = true
        error = nil
        Task {
            let result = await Task.detached { () -> Result<Void, Error> in
                Result { try LocalClones.clone(repo, to: destination, token: HXKeychain.read()) }
            }.value
            cloning = false
            switch result {
            case .success: localPath = destination; clones = [destination]
            case .failure(let e): error = "Could not clone \(repo): \(e)"
            }
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let config = (try? String(contentsOf: url.appendingPathComponent(".git/config"), encoding: .utf8)) ?? ""
        if let repo = appRepo, !LocalClones.configPoints(config, at: repo) {
            error = "\(url.path) is not a clone of \(repo). Choose the folder that holds its .git."
            return
        }
        error = nil
        localPath = url.path
    }

    /// Sets the project up on GitHub and this Mac, then saves it: the tickets repository, Hatch's branch, the
    /// components and notebook repositories (created and cloned when needed), the notebook's first files, and the
    /// rules placed into the app's clone.
    func add(state: AppState, done: @escaping () -> Void) {
        guard let tickets = ticketsRepo, let app = appRepo, let appPath = localPath, let notebook = notebookRepo else { return }
        adding = true
        error = nil
        let createTickets = ticketsChoice == .create
        let base = baseBranch, integration = integrationBranch.trimmingCharacters(in: .whitespaces)
        let design = designRepo, components = componentsConfig
        let designFolder = designPath ?? design.map(siblingFolder(for:))
        let componentPlan = componentTicketPlan
        let createNotebook = notebookChoice == .create
        let notebookFolder = notebookPath ?? siblingFolder(for: notebook)
        let login = login, name = displayName, promotion = promotion, agents = effectiveAgents
        let knownBranches = Dictionary(account.repos.map { ($0.fullName, $0.defaultBranch) }, uniquingKeysWith: { a, _ in a })
        Task {
            let result = await Task.detached { () -> Result<(ProjectConfig, RulesPlacer.Outcome), Error> in
                Result {
                    let client = HXGitHub.client()
                    let token = HXKeychain.read()
                    func ensureRepo(_ full: String, description: String, isPrivate: Bool) throws -> (branch: String, created: Bool) {
                        if let found = try client.repository(full) { return (found.defaultBranch, false) }
                        let parts = full.split(separator: "/").map(String.init)
                        let made = try client.createRepository(name: parts[1], description: description, isPrivate: isPrivate,
                                                               organization: parts[0].lowercased() == login?.lowercased() ? nil : parts[0])
                        return (made.defaultBranch, true)
                    }
                    func ensureClone(_ full: String, at folder: String) throws {
                        guard !FileManager.default.fileExists(atPath: folder + "/.git") else { return }
                        try LocalClones.clone(full, to: folder, token: token)
                    }

                    let report = try client.prepareTicketsRepo(tickets, createIfMissing: createTickets)
                    if report.isPublic { throw HXSetupError.publicTickets(tickets) }
                    try client.ensureBranch(app, name: integration, from: base)

                    var repos = [RepoConfig(role: .app, remote: app, branch: base, localPath: appPath,
                                            buildCommand: agents.build, testCommand: agents.test),
                                 RepoConfig(role: .tickets, remote: tickets, branch: "main")]
                    if let design, let designFolder {
                        try ensureClone(design, at: designFolder)
                        repos.append(RepoConfig(role: .designSystem, remote: design, branch: knownBranches[design] ?? "main", localPath: designFolder))
                    }
                    let nb = createNotebook
                        ? try ensureRepo(notebook, description: "What is decided about \(name) and how work on it is done.", isPrivate: true)
                        : (branch: knownBranches[notebook] ?? "main", created: false)
                    try ensureClone(notebook, at: notebookFolder)
                    repos.append(RepoConfig(role: .notebook, remote: notebook, branch: nb.branch, localPath: notebookFolder))

                    var config = ProjectConfig(name: name, ticketsRepo: tickets, repos: repos, maxAgents: agents.max,
                                               integrationBranch: integration, planApprovalFileThreshold: agents.threshold)
                    config.promotion = promotion
                    config.components = components
                    let files = Notebook.scaffold(config: config, notebookRepo: notebook, rules: RulesPlacer.existingRules(in: appPath))
                    // A repository GitHub just made has its own one-line README; the notebook's replaces it.
                    if nb.created, let readme = files["README.md"] { try NotebookWriter.write(["README.md": readme], in: notebookFolder) }
                    try NotebookWriter.writeMissing(files, in: notebookFolder)
                    // Folders on this Mac are not shared, so the notebook's copy of the settings has none.
                    var shared = config
                    shared.repos = shared.repos.map { var r = $0; r.localPath = nil; return r }
                    try shared.save(to: URL(fileURLWithPath: notebookFolder).appendingPathComponent(Notebook.configPath))
                    if try NotebookWriter.commit("Start the \(name) notebook", in: notebookFolder) {
                        try NotebookWriter.push(in: notebookFolder, token: token)
                    }
                    let rules = (try? String(contentsOfFile: notebookFolder + "/" + Notebook.rulesPath, encoding: .utf8)) ?? ""
                    let placed = try RulesPlacer.place(rules: rules, into: appPath)
                    return (config, placed)
                }
            }.value
            adding = false
            let config: ProjectConfig
            switch result {
            case .failure(let e):
                error = (e as? HXSetupError)?.description ?? (e as? GitError)?.description ?? GitHubAccountModel.describe(e)
                return
            case .success(let value):
                config = value.0
                if case .keptLocalFile(let file) = value.1 {
                    state.errorMessage = "Your \(file) in \(hxAbbreviated(appPath)) was left as it is. Its rules are now in the notebook; delete the file there and Hatch places the notebook's copy."
                }
            }
            // A default only inferred from another project becomes the saved default once it is used.
            let key = key
            let makeDefault = ticketsChoice == .useDefault ? savedDefault == nil : makeDefault
            let created: Project? = state.perform("Add project") {
                let project = try state.store.upsertProject(key: key, name: name, config: config)
                if makeDefault { try state.store.setSetting(hxDefaultTicketsSetting, tickets) }
                return project
            }
            if let created {
                // Drafts, so the owner reads them before any agent touches the app (decisions CO3, CO9 to CO11).
                let drafts = await Task.detached { componentPlan.drafts(appRoot: appPath) }.value
                if !drafts.isEmpty { state.addComponentTickets(projectId: created.id, drafts: drafts) }
                state.selectedProjectKey = created.key
                state.navigate(to: .desk)
                done()
            }
        }
    }
}

enum HXSetupError: Error, CustomStringConvertible {
    case publicTickets(String)
    var description: String {
        switch self {
        case .publicTickets(let r): "\(r) is public. Tickets need a private repository, so they are not visible to everyone."
        }
    }
}

struct ProjectSetupAssistant: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ProjectSetupModel
    @State private var showOtherDesignOptions = false

    init(store: HatchStore, demoStep: ProjectSetupModel.Step? = nil) {
        let model = ProjectSetupModel(store: store)
        if let demoStep { model.fillDemo(step: demoStep) }
        _model = StateObject(wrappedValue: model)
    }

    private var account: GitHubAccountModel { model.account }
    private var deviceFlow: GitHubDeviceFlow { model.deviceFlow }

    var body: some View {
        HStack(spacing: 0) {
            stepList
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    page
                        .padding(.horizontal, 28)
                        .padding(.top, 26)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.critical)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28).padding(.bottom, 8)
                }
                Divider()
                footer
            }
        }
        .frame(width: 800, height: 580)
        .onAppear { if !Snapshots.demoMode { model.start() } }
        .onChange(of: account.user) { model.accountChanged() }
        .onReceive(NotificationCenter.default.publisher(for: .hxGitHubAccountChanged)) { _ in account.refresh() }
        // Coming back from GitHub after adding repositories to Hatch's installation.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if model.connected && !Snapshots.demoMode { account.refresh() }
        }
    }

    // MARK: Frame

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Add project").font(.headline).padding(.horizontal, 10).padding(.bottom, 10)
            ForEach(ProjectSetupModel.Step.allCases) { s in
                Button { if model.canOpen(s) { model.step = s } } label: {
                    HStack(spacing: 9) {
                        ZStack {
                            Circle().fill(s == model.step ? Color.accentColor : model.isDone(s) ? Theme.finished : Color.secondary.opacity(0.15))
                            if model.isDone(s) && s != model.step {
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            } else {
                                Text("\(s.rawValue + 1)").font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(s == model.step ? .white : .secondary)
                            }
                        }
                        .frame(width: 20, height: 20)
                        Text(s.title).fontWeight(s == model.step ? .semibold : .regular)
                            .foregroundStyle(model.canOpen(s) ? .primary : .tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(s == model.step ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.top, 20)
        .frame(width: 196)
        .background(.background.secondary)
    }

    private var footer: some View {
        HStack {
            if model.step.rawValue > (model.connected ? 1 : 0) {
                Button("Back") { model.back() }
            }
            Spacer()
            Button("Cancel") { deviceFlow.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            if model.step == .review {
                Button(model.adding ? "Adding…" : "Add \(model.displayName)") { model.add(state: state) { dismiss() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue(.review))
            } else {
                Button("Continue") { model.next() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue(model.step))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder private var page: some View {
        switch model.step {
        case .github: githubPage
        case .project: projectPage
        case .tickets: ticketsPage
        case .design: designPage
        case .notebook: notebookPage
        case .branches: branchesPage
        case .agents: agentsPage
        case .review: reviewPage
        }
    }

    // MARK: Steps

    private var githubPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HXSetupHeader(symbol: "person.crop.circle", tint: .primary, title: "Connect GitHub",
                          detail: "Only once. Every project uses this account. Hatch sees the repositories its GitHub App is installed on.")
            HXSetupGroup {
                if let user = account.user {
                    HXSetupRow("Account") {
                        Label(user.name.map { "\(user.login) · \($0)" } ?? user.login, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.finished)
                    }
                    HXSetupRow("Repositories Hatch can see") {
                        HStack(spacing: 10) {
                            Text("\(account.repos.count)").foregroundStyle(.secondary)
                            Button("Choose on GitHub…") { NSWorkspace.shared.open(account.manageRepositoriesURL) }
                        }
                    }
                } else if let code = deviceFlow.userCode {
                    VStack(spacing: 8) {
                        Text("Enter this code on GitHub").foregroundStyle(.secondary)
                        Text(code).font(.title.monospaced().weight(.semibold)).textSelection(.enabled)
                        HStack {
                            if let url = deviceFlow.verificationURL { Button("Open GitHub Again") { NSWorkspace.shared.open(url) } }
                            Button("Cancel") { deviceFlow.cancel() }
                        }
                        ProgressView().controlSize(.small)
                    }
                    .frame(maxWidth: .infinity).padding(18)
                } else {
                    VStack(spacing: 10) {
                        Text("Hatch needs your permission to read and write issues and branches.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if account.busy || deviceFlow.busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Connect with GitHub") { deviceFlow.start { _ in account.refresh() } }
                                .buttonStyle(.borderedProminent)
                        }
                        if let e = deviceFlow.error ?? account.error { Text(e).foregroundStyle(Theme.critical).font(.callout) }
                    }
                    .frame(maxWidth: .infinity).padding(18)
                }
            }
        }
    }

    private var projectPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HXSetupHeader(symbol: "square.stack.3d.up", tint: HX.projectTint(model.key), title: "Which app is this project for?",
                          detail: "Choose its repository. Hatch finds your clone of it on this Mac, and suggests the name from it.")
            HXSetupGroup {
                HXSetupRow("App repository") { appRepoPicker }
                HXSetupRow("On this Mac") {
                    if model.appRepo == nil {
                        Text("Choose the repository first").foregroundStyle(.tertiary)
                    } else if model.searchingClones || model.cloning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(model.cloning ? "Cloning…" : "Looking for a clone…").foregroundStyle(.secondary)
                        }
                    } else if let path = model.localPath {
                        HStack(spacing: 8) {
                            Label(hxAbbreviated(path), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.finished)
                            Button("Change…") { model.chooseFolder() }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Button("Clone to \(hxAbbreviated(model.cloneDestination))") { model.clone() }
                            Button("Choose…") { model.chooseFolder() }
                        }
                    }
                }
                if model.clones.count > 1 {
                    HXSetupRow("Other clones") {
                        Picker("Clone", selection: Binding(get: { model.localPath }, set: { model.localPath = $0 })) {
                            ForEach(model.clones, id: \.self) { Text(hxAbbreviated($0)).tag(String?.some($0)) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                HXSetupRow("Name") {
                    TextField("Name", text: Binding(get: { model.name }, set: { model.setName($0, edited: true) }), prompt: Text(""))
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden()
                }
                HXSetupRow("Key") {
                    TextField("Key", text: Binding(get: { model.keyText }, set: { model.keyText = $0; model.keyEdited = !$0.isEmpty }),
                              prompt: Text(""))
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden()
                        .font(.body.monospaced())
                }
            }
            if !model.name.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("The key marks this project's tickets with the label \(Text("project:\(model.key)").font(.callout.monospaced())). It is suggested from the name.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("You never edit the same files as an agent: each one works in its own copy of your clone.")
                .font(.callout).foregroundStyle(.secondary)
            missingRepositoryButton
        }
    }

    private var ticketsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HXSetupHeader(symbol: "number", tint: .indigo, title: "Where tickets live",
                          detail: "A private GitHub repository. Each ticket is an issue, and its type and status are labels. Several projects can share one.")
            HXSetupGroup {
                if let def = model.defaultTickets {
                    HXRadioRow(selected: model.ticketsChoice == .useDefault, title: "Use the default: \(def)",
                               detail: "Shared with your other projects.", recommended: true) { model.ticketsChoice = .useDefault }
                }
                HXRadioRow(selected: model.ticketsChoice == .create, title: "Create a new tickets repository",
                           detail: "Private. Hatch adds its labels.", recommended: model.defaultTickets == nil) { model.ticketsChoice = .create } trailing: {
                    HStack(spacing: 2) {
                        Text("\(model.login ?? "you")/").foregroundStyle(.secondary)
                        TextField("Name", text: $model.newTicketsName).textFieldStyle(.plain).frame(width: 130).labelsHidden()
                    }
                }
                HXRadioRow(selected: model.ticketsChoice == .existing, title: "Use an existing private repository",
                           detail: "Its issues become tickets.") { model.ticketsChoice = .existing } trailing: {
                    Picker("Repository", selection: Binding(get: { model.existingTickets },
                                                            set: { model.existingTickets = $0; model.ticketsChoice = .existing })) {
                        Text("Choose…").tag(String?.none)
                        ForEach(model.privateRepos) { Text($0.fullName).tag(String?.some($0.fullName)) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            if model.ticketsChoice != .useDefault {
                Toggle("Make it the default for new projects", isOn: $model.makeDefault)
            }
            missingRepositoryButton
            HXSetupExample("What it looks like on GitHub") {
                HXIssueSample(number: 151, title: "Toast spacing feels cramped", labels: ["type:proposal", "status:your-call", "project:\(model.key)"])
                HXIssueSample(number: 152, title: "Crash when a connection times out", labels: ["type:bug", "status:building", "project:\(model.key)"])
            }
        }
    }

    private var designPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HXSetupHeader(symbol: "paintpalette", tint: .pink, title: "Components",
                          detail: "Named colors, type, sizes and shared views that every screen uses. They live inside the app, usually as a local package, so the app gets no new dependency.")
            HXSetupGroup {
                let candidates = model.componentsScan?.candidates ?? []
                if model.scanningComponents {
                    HXSetupRow("Looking") {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Reading \(model.displayName)'s code…").foregroundStyle(.secondary)
                        }
                    }
                } else if model.designChoice == .found, let set = model.chosenCandidate {
                    HXSetupRow("Found") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(set.path).font(.callout.monospaced())
                            Text(set.summary).foregroundStyle(.secondary)
                        }
                    }
                    Text("\(model.displayName) already has components. Hatch will use them and ask Proposals and agents to reuse them."
                         + (set.isPackage ? "" : " It is a folder, not a package, so Proposals cannot import it yet."))
                        .foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 10)
                    if !model.otherCandidates.isEmpty {
                        HXSetupRow("Also found") {
                            Text(model.otherCandidates.map(\.path).joined(separator: ", ")).font(.callout.monospaced()).foregroundStyle(.secondary)
                        }
                        Text(model.clashes.isEmpty
                             ? "Hatch adds a draft ticket to merge them in."
                             : "Hatch adds a draft ticket to merge them in, and a question about the \(model.clashes.count) name\(model.clashes.count == 1 ? "" : "s") with two values, for you to decide.")
                            .foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 10)
                    }
                } else if model.designChoice == .start {
                    HXSetupRow("Found") {
                        Text(candidates.isEmpty ? "No components yet" : "Not enough to count as components").foregroundStyle(.secondary)
                    }
                    Text(startDetail).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 10)
                    HXSetupRow("Folder") {
                        TextField("Folder", text: Binding(get: { model.startPathEdited ? model.startPath : ComponentsConfig.suggested(appName: model.displayName).path },
                                                          set: { model.startPath = $0; model.startPathEdited = true }))
                            .textFieldStyle(.plain).font(.callout.monospaced()).multilineTextAlignment(.trailing).frame(width: 240).labelsHidden()
                    }
                }
                DisclosureGroup("Other options", isExpanded: $showOtherDesignOptions) {
                    VStack(spacing: 0) {
                        if model.designChoice != .start {
                            HXRadioRow(selected: false, title: "Have Hatch start new components",
                                       detail: "Adds draft tickets for a new package, even though some already exist.") { model.chooseDesign(.start) }
                        }
                        if model.designChoice != .found, let first = candidates.first {
                            HXRadioRow(selected: false, title: "Use \(first.path)", detail: first.summary) { model.foundPath = first.path; model.chooseDesign(.found) }
                        }
                        if model.designChoice == .found, candidates.count > 1 {
                            HXSetupRow("Use a different folder") {
                                Picker("Folder", selection: Binding(get: { model.foundPath }, set: { model.foundPath = $0; model.chooseDesign(.found) })) {
                                    ForEach(candidates, id: \.path) { Text($0.path).tag(String?.some($0.path)) }
                                }
                                .labelsHidden().pickerStyle(.menu).fixedSize()
                            }
                            HXSetupRow("Merge the others") {
                                Toggle("Add a ticket to merge them in", isOn: $model.mergeOthers).toggleStyle(.checkbox)
                            }
                        }
                        HXRadioRow(selected: model.designChoice == .separate, title: "A separate repository",
                                   detail: "For a package several apps share. The app imports it by version.") { model.chooseDesign(.separate) } trailing: {
                            Picker("Repository", selection: Binding(get: { model.designExisting },
                                                                    set: { model.designExisting = $0; model.chooseDesign(.separate) })) {
                                Text("Choose…").tag(String?.none)
                                ForEach(model.account.repos.filter { $0.fullName != model.appRepo }) { Text($0.fullName).tag(String?.some($0.fullName)) }
                            }
                            .labelsHidden().fixedSize()
                        }
                        HXRadioRow(selected: model.designChoice == .none, title: "Not now",
                                   detail: "Proposals use plain SwiftUI and only look roughly like the app. You can start them later on the Components page.") { model.chooseDesign(.none) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                if let repo = model.designRepo {
                    HXSetupRow("On this Mac") {
                        Text(model.designPath.map(hxAbbreviated) ?? "Hatch clones it to \(hxAbbreviated(model.siblingFolder(for: repo)))")
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            HXSetupExample("Why it matters") {
                Text("Components are one shared place for your colors, fonts and spacing. Proposals are drawn with them, so an option looks like your app and what you pick is what ships. Agents reuse the names instead of typing values into each screen.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var foundDetail: String {
        guard let c = model.componentsScan?.candidates.first(where: { $0.path == model.foundPath }) ?? model.componentsScan?.candidates.first else { return "" }
        return c.summary + (c.isPackage ? "." : ". A folder in the app, not a package yet, so Proposals cannot import it until it moves into one.")
    }

    private var startDetail: String {
        let base = "Hatch will create one shared place for your colors, fonts and spacing and add draft tickets for it."
        guard let scan = model.componentsScan, let typed = scan.typedSummary, !scan.isSmall else {
            return base + " Nothing changes until you submit them."
        }
        return base + " The app types \(typed) straight into views today; a question lets you decide which close values become one, then a ticket per kind moves them over. Nothing changes until you submit them."
    }

    private var notebookPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HXSetupHeader(symbol: "book.closed", tint: .orange, title: "Notebook",
                          detail: "Where \(model.displayName)'s decisions, Spec, agent rules and Proposal options live, as plain files. With it, anyone can pick the project up later, with any agent, even without Hatch.")
            HXSetupGroup {
                HXRadioRow(selected: model.notebookChoice == .create, title: "Hatch creates it", detail: "Private. Hatch writes its first files.",
                           recommended: true) { model.notebookChoice = .create } trailing: {
                    HStack(spacing: 2) {
                        Text("\(model.newRepoOwner)/").foregroundStyle(.secondary)
                        TextField("Name", text: Binding(get: { model.notebookNewName },
                                                        set: { model.notebookNewName = $0; model.notebookNameEdited = true; model.notebookChoice = .create }))
                            .textFieldStyle(.plain).frame(width: 170).labelsHidden()
                    }
                }
                HXRadioRow(selected: model.notebookChoice == .existing, title: "Use an existing repository",
                           detail: "Hatch adds the files that are missing.") { model.notebookChoice = .existing } trailing: {
                    Picker("Repository", selection: Binding(get: { model.notebookExisting },
                                                            set: { model.notebookExisting = $0; model.notebookChoice = .existing
                                                                   model.notebookPath = nil
                                                                   model.findClone(of: $0) { model.notebookPath = $0 } })) {
                        Text("Choose…").tag(String?.none)
                        ForEach(model.privateRepos.filter { $0.fullName != model.appRepo }) { Text($0.fullName).tag(String?.some($0.fullName)) }
                    }
                    .labelsHidden().fixedSize()
                }
                if let repo = model.notebookRepo {
                    HXSetupRow("On this Mac") {
                        Text(model.notebookPath.map(hxAbbreviated) ?? "Hatch clones it to \(hxAbbreviated(model.siblingFolder(for: repo)))")
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                HXSetupRow("Rules for agents") {
                    Text(rulesSummary).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }
            HXSetupExample("What is in it") {
                VStack(alignment: .leading, spacing: 4) {
                    HXPathLine(path: "NOW.md", note: "where things stand, refreshed by Hatch")
                    HXPathLine(path: "WORKFLOW.md", note: "how work flows, with or without Hatch")
                    HXPathLine(path: "rules/AGENTS.md", note: "how code is written; placed in your clone, never committed there")
                    HXPathLine(path: "spec/", note: "what the app does, by area")
                    HXPathLine(path: "decisions/", note: "every decision, its options and why")
                    HXPathLine(path: "specimens/", note: "the code of each Proposal's options")
                }
            }
        }
    }

    private var rulesSummary: String {
        if model.appCommitsRules { return "The app commits its own AGENTS.md. Hatch leaves it and adds the notebook's rules to each brief." }
        if let lines = model.existingRulesLines { return "Your AGENTS.md (\(lines) lines) becomes the notebook's rules" }
        return "A short starter file for you to fill in"
    }

    private var branchesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HXSetupHeader(symbol: "arrow.triangle.branch", tint: .green, title: "How work reaches your code",
                          detail: "Hatch has its own branch. Nothing reaches your base branch without CI passing on it.")
            HXBranchFlow(integration: model.integrationBranch, base: model.baseBranch.isEmpty ? "dev" : model.baseBranch, promotion: model.promotion)
            HXSetupGroup {
                HXSetupRow("Base branch") {
                    if model.branches.isEmpty {
                        TextField("Base branch", text: $model.baseBranch).textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden()
                    } else {
                        Picker("Base branch", selection: $model.baseBranch) {
                            ForEach(model.branches, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                HXSetupRow("Hatch's branch") {
                    TextField("hatch", text: $model.integrationBranch).textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden()
                }
            }
            Text("When \(Text(model.integrationBranch).font(.body.monospaced())) passes CI").font(.headline)
            HXSetupGroup { HXPromotionChoice(promotion: $model.promotion, base: model.baseBranch) }
        }
    }

    private var reviewPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HXSetupHeader(symbol: "checkmark.seal", tint: HX.projectTint(model.key), title: "Ready to add \(model.displayName)",
                          detail: "Hatch does these things when you click Add.")
            HXSetupGroup {
                HXReviewRow(verb: model.ticketsChoice == .create ? "Creates" : "Uses",
                            text: "\(model.ticketsRepo ?? "") for tickets" + (model.makeDefault && model.ticketsChoice != .useDefault ? ", the new default" : ""))
                HXReviewRow(verb: "Uses", text: "\(model.appRepo ?? "") at \(hxAbbreviated(model.localPath ?? ""))")
                if let d = model.designRepo {
                    HXReviewRow(verb: "Uses", text: "\(d) for components")
                } else if let c = model.componentsConfig {
                    HXReviewRow(verb: model.designChoice == .start ? "Adds" : "Uses",
                                text: model.designChoice == .start
                                    ? "draft tickets to start the components in \(c.path)"
                                      + (model.componentsScan?.candidates.isEmpty == false ? ", beside the \(model.componentsScan!.candidates.count) set(s) already in the app" : "")
                                    : "\(c.path) as the components")
                    if model.designChoice == .found {
                        if !model.clashes.isEmpty {
                            HXReviewRow(verb: "Adds", text: "1 question: \(model.clashes.count) name\(model.clashes.count == 1 ? "" : "s") with two values")
                        }
                        if model.mergeOthers && !model.otherCandidates.isEmpty {
                            HXReviewRow(verb: "Adds", text: "\(model.otherCandidates.count) draft ticket\(model.otherCandidates.count == 1 ? "" : "s") to merge the other set\(model.otherCandidates.count == 1 ? "" : "s") in")
                        }
                    }
                }
                if let n = model.notebookRepo {
                    HXReviewRow(verb: model.notebookChoice == .create ? "Creates" : "Uses",
                                text: "\(n) as the notebook, with its first files")
                }
                HXReviewRow(verb: "Creates", text: "branch \(model.integrationBranch) from \(model.baseBranch), if missing")
                HXReviewRow(verb: "Places", text: model.appCommitsRules ? "nothing in your clone: the app has its own AGENTS.md"
                                                                         : "AGENTS.md and CLAUDE.md in your clone, never committed")
                HXReviewRow(verb: "Uses", text: "up to \(model.effectiveAgents.max) agents at once" +
                            (model.effectiveAgents.build == nil ? ", with no build before review" : ", each building its work before review"))
            }
        }
    }

    private var agentsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HXSetupHeader(symbol: "cpu", tint: .teal, title: "How agents work",
                          detail: "How many work at once, when they ask you first, and how their work is built before you see it.")
            HXSetupGroup {
                HXRadioRow(selected: model.useAgentDefaults, title: "Use the defaults",
                           detail: "Good for most projects. You can change them later in Project settings.", recommended: true) {
                    model.useAgentDefaults = true
                }
                HXRadioRow(selected: !model.useAgentDefaults, title: "Customize", detail: "Set each value yourself.") {
                    model.useAgentDefaults = false
                }
            }
            HXSetupGroup {
                HXSetupRow("Agents at once") {
                    if model.useAgentDefaults {
                        Text("\(ProjectSetupModel.defaultMaxAgents)").foregroundStyle(.secondary)
                    } else {
                        Stepper("\(model.maxAgents)", value: $model.maxAgents, in: 1...12).fixedSize()
                    }
                }
                HXSetupRow("Ask before plans that touch more than") {
                    if model.useAgentDefaults {
                        Text("\(ProjectSetupModel.defaultPlanThreshold) files").foregroundStyle(.secondary)
                    } else {
                        Stepper("\(model.planThreshold) files", value: $model.planThreshold, in: 1...100).fixedSize()
                    }
                }
                HXSetupRow("Build before review") {
                    if model.useAgentDefaults {
                        Text(model.suggestedBuild ?? "None found").font(.callout.monospaced()).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        TextField("Build command", text: $model.buildCommand, prompt: Text(""))
                            .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden().font(.callout.monospaced())
                    }
                }
                HXSetupRow("Tests before review") {
                    if model.useAgentDefaults {
                        Text("None, CI runs them").foregroundStyle(.secondary)
                    } else {
                        TextField("Test command", text: $model.testCommand, prompt: Text(""))
                            .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden().font(.callout.monospaced())
                    }
                }
            }
            Text("Before a ticket comes to you, its agent runs the build in its own copy of the app. Only the tests of the area it changed belong here; the full suite runs in CI.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Hatch sees only the repositories chosen for its GitHub App. The list refreshes when you come back to Hatch.
    private var missingRepositoryButton: some View {
        Button("A repository is missing? Choose it on GitHub…") { NSWorkspace.shared.open(account.manageRepositoriesURL) }
            .buttonStyle(.link)
    }

    private var appRepoPicker: some View {
        Picker("App repository", selection: $model.appRepo) {
            Text(account.busy ? "Loading…" : "Choose…").tag(String?.none)
            ForEach(account.repos) { Text($0.fullName).tag(String?.some($0.fullName)) }
        }
        .labelsHidden().fixedSize()
    }
}

func hxAbbreviated(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

// MARK: Pieces shared with Project settings

struct HXSetupHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            HXIconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The tinted symbol tile that marks each part of a project, in the assistant's headers and on the settings cards.
struct HXIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.47, weight: .medium))
            .foregroundStyle(tint == .primary ? Color(nsColor: .windowBackgroundColor) : .white)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

/// A grouped inset section: a real grouped Form, so rows, separators and pickers look and behave as in System
/// Settings (a picker shows its value and the round chevron button that highlights on hover).
struct HXSetupGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        Form { Section { content } }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            // A grouped Form keeps a 20pt margin around its section that content margins do not remove; take it
            // back so the section lines up with the text above and below it.
            .padding(-20)
    }
}

/// One row: the label on the left, the value or control on the right, drawn by the Form.
struct HXSetupRow<Value: View>: View {
    let title: String
    @ViewBuilder let value: Value
    init(_ title: String, @ViewBuilder value: () -> Value) { self.title = title; self.value = value() }

    var body: some View {
        LabeledContent(title) { value }
    }
}

struct HXRadioRow<Trailing: View>: View {
    let selected: Bool
    let title: String
    let detail: String
    var recommended = false
    let action: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: action) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(title).fontWeight(.medium)
                            if recommended {
                                Text("Recommended").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                            }
                        }
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing
        }
        .padding(.vertical, 3)
    }
}

extension HXRadioRow where Trailing == EmptyView {
    init(selected: Bool, title: String, detail: String, recommended: Bool = false, action: @escaping () -> Void) {
        self.init(selected: selected, title: title, detail: detail, recommended: recommended, action: action) { EmptyView() }
    }
}

struct HXSetupExample<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) { self.label = label; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

private struct HXIssueSample: View {
    let number: Int
    let title: String
    let labels: [String]
    var body: some View {
        HStack(spacing: 8) {
            Text("#\(number)").foregroundStyle(.secondary).monospacedDigit()
            Text(title)
            ForEach(labels, id: \.self) { l in
                Text(l).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            }
        }
        .lineLimit(1)
    }
}

private struct HXPathLine: View {
    let path: String
    let note: String
    var body: some View {
        HStack(spacing: 8) {
            Text(path).font(.callout.monospaced())
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}

private struct HXReviewRow: View {
    let verb: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Text(verb).font(.caption.weight(.semibold))
                .foregroundStyle(verb == "Uses" ? Theme.finished : Theme.you)
                .frame(width: 58, alignment: .center).padding(.vertical, 2)
                .background(verb == "Uses" ? Theme.finishedBackground : Theme.youBackground, in: RoundedRectangle(cornerRadius: 5))
            Text(text).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 12).frame(minHeight: 38)
    }
}

/// ticket/151 → hatch → base, with the last arrow labelled by how Hatch promotes.
struct HXBranchFlow: View {
    let integration: String
    let base: String
    let promotion: Promotion

    var body: some View {
        HStack(spacing: 0) {
            node("ticket/151-…", tint: .secondary)
            arrow(top: "approved", bottom: " ")
            node(integration.isEmpty ? "hatch" : integration, tint: Theme.finished)
            arrow(top: "CI passes", bottom: promotion.short)
            node(base, tint: .accentColor)
        }
        .font(.callout.monospaced())
    }

    private func node(_ text: String, tint: Color) -> some View {
        Text(text).foregroundStyle(tint == .secondary ? .primary : tint)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.6)))
    }

    private func arrow(top: String, bottom: String) -> some View {
        VStack(spacing: 2) {
            Text(top).font(.caption).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Text(bottom).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 96)
    }
}

/// The three ways Hatch's branch reaches the base branch. Only the rows, so the container groups them:
/// an `HXSetupGroup` in the assistant, the Branches card in Project settings.
struct HXPromotionChoice: View {
    @Binding var promotion: Promotion
    let base: String

    var body: some View {
        HXRadioRow(selected: promotion == .pullRequest, title: "Hatch opens a pull request, you merge it",
                   detail: "One pull request per batch on GitHub. Works with branch protection on \(base).",
                   recommended: true) { promotion = .pullRequest }
        HXRadioRow(selected: promotion == .automatic, title: "Hatch merges automatically",
                   detail: "Fastest. Good once you trust the CI.") { promotion = .automatic }
        HXRadioRow(selected: promotion == .manual, title: "Leave it on the branch",
                   detail: "You merge it into \(base) yourself, whenever you like.") { promotion = .manual }
    }
}

extension Promotion {
    var short: String {
        switch self {
        case .pullRequest: "pull request"
        case .automatic: "merged"
        case .manual: "you merge"
        }
    }
}

/// The component tickets setup adds once the project exists (decisions CO3, CO9 to CO11). Kept as plain values so
/// the usage counts for the Question can be read off the main thread.
struct HXComponentTicketPlan: Sendable {
    let choice: ProjectSetupModel.DesignChoice
    let appName: String
    let config: ComponentsConfig?
    let scan: ComponentsScan?
    let chosen: ComponentsCandidate?
    let others: [ComponentsCandidate]
    let clashes: [NameClash]

    func drafts(appRoot: String) -> [ComponentsSetup.Draft] {
        switch choice {
        case .start:
            guard let config else { return [] }
            return ComponentsSetup.drafts(appName: appName, config: config, scan: scan, existing: scan?.candidates.map(\.path) ?? [])
        case .found:
            guard let chosen else { return [] }
            let usage = clashes.isEmpty ? [:] : ComponentConflicts.usage(of: clashes.map(\.name), appRoot: appRoot)
            let question = ComponentsSetup.clashQuestion(clashes, chosen: chosen, usage: usage)
            return [question].compactMap { $0 } + others.map { ComponentsSetup.mergeDraft(into: chosen, from: $0) }
        case .separate, .none:
            return []
        }
    }
}
