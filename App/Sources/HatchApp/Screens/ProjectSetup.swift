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
        case github, project, tickets, code, design, branches, review
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .github: "GitHub"
            case .project: "Project"
            case .tickets: "Tickets"
            case .code: "App code"
            case .design: "Design system"
            case .branches: "Branches"
            case .review: "Review"
            }
        }
    }

    enum TicketsChoice { case useDefault, create, existing }

    @Published var step: Step = .github
    @Published var name = ""
    @Published var nameEdited = false
    @Published var keyOverride = ""

    @Published var ticketsChoice: TicketsChoice = .create
    @Published var newTicketsName = "hatch-tickets"
    @Published var existingTickets: String?
    @Published var makeDefault = true
    let defaultTickets: String?
    private let savedDefault: String?
    private var forwarders: [AnyCancellable] = []

    @Published var appRepo: String? { didSet { appRepoChanged(from: oldValue) } }
    @Published var localPath: String?
    @Published var clones: [String] = []
    @Published var searchingClones = false
    @Published var cloning = false

    @Published var designRepo: String?

    @Published var branches: [String] = []
    @Published var baseBranch = ""
    @Published var integrationBranch = "hatch"
    @Published var promotion: Promotion = .pullRequest
    @Published var maxAgents = 3

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
    var key: String {
        let typed = keyOverride.trimmingCharacters(in: .whitespaces).lowercased()
        return typed.isEmpty ? ProjectConfig.key(for: name, existing: existingKeys) : typed
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
        case .project: return appRepo != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .tickets: return ticketsRepo != nil
        case .code: return appRepo != nil && localPath != nil
        case .design: return true
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
                         GitHubRepoSummary(fullName: "tashda/echo-design-system", isPrivate: true),
                         GitHubRepoSummary(fullName: "tashda/hatch-tickets", isPrivate: true)]
        ticketsChoice = .create
        appRepo = "tashda/echo"
        localPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Development/echo").path
        clones = [localPath!]
        branches = ["main", "dev"]
        designRepo = "tashda/echo-design-system"
        self.step = step
    }

    private func appRepoChanged(from old: String?) {
        guard appRepo != old, let repo = appRepo else { return }
        if !nameEdited || name.isEmpty {
            let raw = repo.split(separator: "/").last.map(String.init) ?? repo
            name = raw.prefix(1).uppercased() + raw.dropFirst()
            nameEdited = false
        }
        baseBranch = appRepoSummary?.defaultBranch ?? "main"
        branches = []
        guard !demo else { return }
        localPath = nil
        clones = []
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

    /// Creates or checks the tickets repository and Hatch's branch on GitHub, then saves the project.
    func add(state: AppState, done: @escaping () -> Void) {
        guard let tickets = ticketsRepo, let app = appRepo, let localPath else { return }
        adding = true
        error = nil
        let create = ticketsChoice == .create
        let base = baseBranch, integration = integrationBranch.trimmingCharacters(in: .whitespaces)
        Task {
            let result = await Task.detached { () -> Result<Void, Error> in
                Result {
                    let client = HXGitHub.client()
                    let report = try client.prepareTicketsRepo(tickets, createIfMissing: create)
                    if report.isPublic { throw HXSetupError.publicTickets(tickets) }
                    try client.ensureBranch(app, name: integration, from: base)
                }
            }.value
            adding = false
            if case .failure(let e) = result {
                error = (e as? HXSetupError)?.description ?? GitHubAccountModel.describe(e)
                return
            }
            var repos = [RepoConfig(role: .app, remote: app, branch: base, localPath: localPath),
                         RepoConfig(role: .tickets, remote: tickets, branch: "main")]
            if let design = designRepo {
                repos.append(RepoConfig(role: .designSystem, remote: design,
                                        branch: account.repos.first { $0.fullName == design }?.defaultBranch ?? "main"))
            }
            var config = ProjectConfig(name: displayName, ticketsRepo: tickets, repos: repos, maxAgents: maxAgents,
                                       integrationBranch: integration)
            config.promotion = promotion
            // A default only inferred from another project becomes the saved default once it is used.
            let key = key, name = displayName
            let makeDefault = ticketsChoice == .useDefault ? savedDefault == nil : makeDefault
            let created: Project? = state.perform("Add project") {
                let project = try state.store.upsertProject(key: key, name: name, config: config)
                if makeDefault { try state.store.setSetting(hxDefaultTicketsSetting, tickets) }
                try config.save(to: URL(fileURLWithPath: localPath).appendingPathComponent(".hatch/project.json"))
                return project
            }
            if let created {
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
        case .code: codePage
        case .design: designPage
        case .branches: branchesPage
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
                    HXSetupRow("Repositories Hatch can see") { Text("\(account.repos.count)").foregroundStyle(.secondary) }
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
                          detail: "Choose its repository. The name is suggested from it, and you can change it.")
            HXSetupGroup {
                HXSetupRow("App repository") { appRepoPicker }
                HXSetupRow("Name") {
                    TextField("Name", text: Binding(get: { model.name }, set: { model.name = $0; model.nameEdited = true }),
                              prompt: Text(""))
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden()
                }
            }
            if !model.name.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("The key used in labels, \(Text("project:\(model.key)").font(.callout.monospaced())), is made from the name. Change it under Review › Advanced.")
                    .font(.callout).foregroundStyle(.secondary)
            }
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
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            }
            if model.ticketsChoice != .useDefault {
                Toggle("Make it the default for new projects", isOn: $model.makeDefault)
            }
            HXSetupExample("What it looks like on GitHub") {
                HXIssueSample(number: 151, title: "Toast spacing feels cramped", labels: ["type:proposal", "status:your-call", "project:\(model.key)"])
                HXIssueSample(number: 152, title: "Crash when a connection times out", labels: ["type:bug", "status:building", "project:\(model.key)"])
            }
        }
    }

    private var codePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HXSetupHeader(symbol: "chevron.left.forwardslash.chevron.right", tint: .blue, title: "The app's code",
                          detail: "The repository agents change, and your clone of it on this Mac. Hatch needs both.")
            HXSetupGroup {
                HXSetupRow("Repository") { appRepoPicker }
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
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                }
            }
            Text("Hatch looks for a clone in your usual code folders. You never edit the same files as an agent: each one works in its own copy.")
                .font(.callout).foregroundStyle(.secondary)
            HXSetupExample("What happens on this Mac") {
                let repo = model.appRepo?.split(separator: "/").last.map(String.init) ?? "app"
                VStack(alignment: .leading, spacing: 4) {
                    HXPathLine(path: hxAbbreviated(model.localPath ?? model.cloneDestination), note: "your clone, Hatch never edits it")
                    HXPathLine(path: "…/Hatch/worktrees/\(repo)-151", note: "Agent on #151, branch ticket/151-toast-spacing")
                    HXPathLine(path: "…/Hatch/worktrees/\(repo)-152", note: "Agent on #152")
                }
            }
        }
    }

    private var designPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HXSetupHeader(symbol: "paintpalette", tint: .pink, title: "Design system",
                          detail: "Where the app's colors, type and components are defined. Optional.")
            HXSetupGroup {
                HXRadioRow(selected: model.designRepo != nil, title: "A separate repository",
                           detail: "Proposals are built against it.") {
                    if model.designRepo == nil { model.designRepo = model.account.repos.first { $0.fullName.lowercased().contains("design") }?.fullName }
                } trailing: {
                    Picker("Repository", selection: $model.designRepo) {
                        Text("Choose…").tag(String?.none)
                        ForEach(model.account.repos.filter { $0.fullName != model.appRepo }) { Text($0.fullName).tag(String?.some($0.fullName)) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                HXRadioRow(selected: model.designRepo == nil, title: "No separate repository",
                           detail: "It lives inside the app, or there is none. Proposals build against the app's own code.") { model.designRepo = nil }
            }
            HXSetupExample("Why it matters") {
                Text("A Proposal shows options side by side. Built with your design system, they use your real colors and type, so what you choose is what ships.")
                    .foregroundStyle(.secondary)
            }
        }
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
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                }
                HXSetupRow("Hatch's branch") {
                    TextField("hatch", text: $model.integrationBranch).textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden()
                }
            }
            Text("When \(Text(model.integrationBranch).font(.body.monospaced())) passes CI").font(.headline)
            HXPromotionChoice(promotion: $model.promotion, base: model.baseBranch)
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
                if let d = model.designRepo { HXReviewRow(verb: "Uses", text: "\(d) as the design system") }
                HXReviewRow(verb: "Creates", text: "branch \(model.integrationBranch) from \(model.baseBranch), if missing")
                HXReviewRow(verb: "Writes", text: ".hatch/project.json in your clone, for you to commit")
            }
            DisclosureGroup("Advanced") {
                HXSetupGroup {
                    HXSetupRow("Key") {
                        TextField(ProjectConfig.key(for: model.name, existing: []), text: $model.keyOverride)
                            .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden()
                    }
                    HXSetupRow("Agents at once") {
                        Stepper("\(model.maxAgents)", value: $model.maxAgents, in: 1...8).fixedSize()
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var appRepoPicker: some View {
        Picker("App repository", selection: $model.appRepo) {
            Text(account.busy ? "Loading…" : "Choose…").tag(String?.none)
            ForEach(account.repos) { Text($0.fullName).tag(String?.some($0.fullName)) }
        }
        .labelsHidden().pickerStyle(.menu).fixedSize()
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
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint == .primary ? Color(nsColor: .windowBackgroundColor) : .white)
                .frame(width: 36, height: 36)
                .background(tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A grouped inset section, as in a grouped Form, for pages that are not a Form.
struct HXSetupGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, view in
                    if index > 0 { Divider().padding(.leading, 12) }
                    view
                }
            }
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct HXSetupRow<Value: View>: View {
    let title: String
    @ViewBuilder let value: Value
    init(_ title: String, @ViewBuilder value: () -> Value) { self.title = title; self.value = value() }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            value
        }
        .padding(.horizontal, 12).frame(minHeight: 40)
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
        .padding(.horizontal, 12).padding(.vertical, 10)
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

struct HXPromotionChoice: View {
    @Binding var promotion: Promotion
    let base: String

    var body: some View {
        HXSetupGroup {
            HXRadioRow(selected: promotion == .pullRequest, title: "Hatch opens a pull request, you merge it",
                       detail: "One pull request per batch on GitHub. Works with branch protection on \(base).",
                       recommended: true) { promotion = .pullRequest }
            HXRadioRow(selected: promotion == .automatic, title: "Hatch merges automatically",
                       detail: "Fastest. Good once you trust the CI.") { promotion = .automatic }
            HXRadioRow(selected: promotion == .manual, title: "Leave it on the branch",
                       detail: "You merge it into \(base) yourself, whenever you like.") { promotion = .manual }
        }
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
