import SwiftUI
import AppKit
import HatchCore
import HatchSync
import HatchGit

// Project settings (PS1): one page of cards, one per part of a project, each changed in place. The assistant adds a
// project; these cards edit it. Save writes the database and the notebook's project.json, never the app repository (PS13).

struct HXAreaDraft: Identifiable {
    let id = UUID()
    var name: String
    var globs: String
    var prefix: String
    /// Not edited on the page; kept so saving does not drop them.
    var testPlans: [String]? = nil
}

func hxRoleName(_ role: RepoRole) -> String {
    switch role {
    case .app: return "App"
    case .designSystem: return "Components"
    case .specimens: return "Specimens"
    case .tickets: return "Tickets"
    case .notebook: return "Notebook"
    }
}

struct ProjectView: View {
    @EnvironmentObject var state: AppState
    @State private var showAdd = false

    var body: some View {
        Group {
            if let project = state.hxProject {
                ProjectForm(project: project)
                    .id(project.id)
            } else {
                VStack(spacing: 12) {
                    HXEmpty(symbol: "gearshape", title: "No project yet", detail: "Add your first project to link its repositories.")
                    Button("Add project") { showAdd = true }
                }
            }
        }
        .sheet(isPresented: $showAdd) { ProjectSetupAssistant(store: state.store) }
    }
}

struct ProjectForm: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    let project: Project

    @StateObject private var account = GitHubAccountModel()
    @State private var name = ""
    @State private var ticketsRepo: String?
    @State private var ticketsIsDefault = false
    @State private var appRepo: String?
    @State private var appPath: String?
    @State private var baseBranch = "main"
    @State private var branches: [String] = []
    /// Where the components are (decision CO1): inside the app, a separate repository, or none yet.
    @State private var componentsMode: HXComponentsMode = .none
    @State private var componentsFolder = ""
    @State private var componentsProduct: String?
    /// Folders in the app's clone that look like components, for the folder menu.
    @State private var componentCandidates: [ComponentsCandidate] = []
    @State private var componentsRepo: String?
    @State private var componentsPath: String?
    @State private var notebookRepo: String?
    @State private var notebookPath: String?
    @State private var integrationBranch = "hatch"
    @State private var promotion: Promotion = .pullRequest
    @State private var maxAgents = ProjectSetupModel.defaultMaxAgents
    @State private var threshold = ProjectSetupModel.defaultPlanThreshold
    @State private var buildCommand = ""
    @State private var testCommand = ""
    /// What the app's clone suggests for the build, so a new clone can replace it but never a command the owner typed.
    @State private var suggestedBuild: String?
    @State private var areas: [HXAreaDraft] = []
    /// Roles whose clone is being looked for on this Mac.
    @State private var searching: Set<RepoRole> = []
    @State private var editingArea: HXAreaDraft?
    @State private var showAdd = false
    @State private var loaded = false
    @State private var message = ""
    @State private var problem = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !githubReady && !account.busy { githubNotice }
                projectCard
                ticketsCard
                codeCard
                componentsCard
                notebookCard
                branchesCard
                agentsCard
                areasCard
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .onAppear {
            if !loaded { load(); loaded = true }
            if Snapshots.demoMode { fillDemoAccount() } else { account.refresh(); loadBranches(); suggestBuild(fill: false); scanComponents() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hxGitHubAccountChanged)) { _ in
            if !Snapshots.demoMode { account.refresh() }
        }
        .sheet(isPresented: $showAdd) { ProjectSetupAssistant(store: state.store) }
        .sheet(item: $editingArea) { draft in
            HXAreaEditSheet(draft: draft) { saved in
                if let index = areas.firstIndex(where: { $0.id == saved.id }) { areas[index] = saved } else { areas.append(saved) }
            }
        }
    }

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? project.name : trimmed
    }

    private var header: some View {
        HStack(spacing: 14) {
            ProjectTile(name: displayName, key: project.key, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName).font(.title2.weight(.semibold))
                Text("Project settings").foregroundStyle(.secondary)
            }
            Spacer()
            Button { showAdd = true } label: { Label("Add project", systemImage: "plus") }
                .buttonStyle(.glass)
        }
        .padding(.bottom, 6)
    }

    private var githubNotice: some View {
        HStack(spacing: 10) {
            Label("GitHub is not connected, so repositories can't be changed here.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.you)
            Spacer()
            Button("Connect in Settings…") {
                state.settingsPage = .github
                openWindow(id: "settings")
            }
        }
        .padding(12)
        .background(Theme.youBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Cards

    private var projectCard: some View {
        HXSettingsCard(symbol: "square.stack.3d.up", tint: HX.projectTint(project.key), title: "Project",
                       summary: "Its name, and the key in its labels",
                       info: "The name shows across Hatch. The key marks this project's tickets on GitHub with the label project:\(project.key).",
                       footnote: Text("The key is used in labels such as \(Text("project:\(project.key)").font(.callout.monospaced())), so it stays as it is: changing it would leave this project's tickets on GitHub behind.")) {
            HXSetupRow("Name") {
                TextField("Name", text: $name, prompt: Text(project.name))
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden()
            }
            HXSetupRow("Key") {
                Text(project.key).font(.body.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private var ticketsLocked: Bool { ticketsRepo != nil && state.hasTickets(projectId: project.id) }

    private var ticketsCard: some View {
        HXSettingsCard(symbol: "number", tint: .indigo, title: "Tickets",
                       summary: ticketsRepo.map { "Issues in \($0)" } ?? "Issues in a private repository",
                       info: "A private GitHub repository. Each ticket is an issue, and its type and status are labels. Several projects can share one.",
                       footnote: ticketsLocked ? Text("This project already has tickets in it, so the repository stays.") : nil) {
            HXSetupRow("Repository") {
                if ticketsLocked {
                    Label(ticketsRepo ?? "", systemImage: "lock.fill").foregroundStyle(.secondary)
                } else {
                    repoPicker("Tickets repository", selection: $ticketsRepo, from: privateRepos)
                }
            }
            HXSetupRow("Default for new projects") {
                Toggle("Default for new projects", isOn: $ticketsIsDefault)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(ticketsRepo == nil)
            }
        }
    }

    private var codeCard: some View {
        HXSettingsCard(symbol: "chevron.left.forwardslash.chevron.right", tint: .blue, title: "App code",
                       summary: appPath.map { "\(hxAbbreviated($0)) · on \(baseBranch)" } ?? "Not on this Mac yet",
                       info: "The repository agents change, and your clone of it on this Mac. Hatch needs both. You never edit the same files as an agent: each one works in its own copy.") {
            HXSetupRow("Repository") {
                repoPicker("App repository", selection: Binding(get: { appRepo }, set: { changeRepo(.app, to: $0) }), from: allRepos)
            }
            folderRow(.app, repo: appRepo, path: $appPath)
            HXSetupRow("Base branch") {
                if branches.isEmpty {
                    TextField("Base branch", text: $baseBranch, prompt: Text("main"))
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden().font(.body.monospaced())
                } else {
                    Picker("Base branch", selection: $baseBranch) {
                        if !branches.contains(baseBranch) { Text(baseBranch).tag(baseBranch) }
                        ForEach(branches, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
        }
    }

    private var componentsSummary: String {
        switch componentsMode {
        case .inApp: return componentsFolder.isEmpty ? "Choose the folder" : "\(componentsFolder) in the app"
        case .separate: return componentsRepo ?? "Choose the repository"
        case .none: return "None yet: start them on the Components page"
        }
    }

    private var componentsCard: some View {
        HXSettingsCard(symbol: "paintpalette", tint: .pink, title: "Components", summary: componentsSummary,
                       info: "Named colors, type, sizes and shared views. They live inside the app, usually as a local package; a separate repository is for a package several apps share. Proposals built with them use your real colors and type.") {
            HXSetupRow("Where") {
                Picker("Where", selection: $componentsMode) {
                    Text("In the app").tag(HXComponentsMode.inApp)
                    Text("Separate repository").tag(HXComponentsMode.separate)
                    Text("None").tag(HXComponentsMode.none)
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            if componentsMode == .inApp {
                HXSetupRow("Folder") {
                    HStack(spacing: 6) {
                        TextField("Packages/AppComponents", text: Binding(get: { componentsFolder }, set: { setComponentsFolder($0) }))
                            .textFieldStyle(.plain).font(.body.monospaced()).multilineTextAlignment(.trailing).labelsHidden()
                        if !componentCandidates.isEmpty {
                            Menu {
                                ForEach(componentCandidates, id: \.path) { c in
                                    Button("\(c.path) · \(c.summary)") { setComponentsFolder(c.path) }
                                }
                            } label: { Image(systemName: "chevron.up.chevron.down") }
                            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                            .help("Folders in the app that look like components")
                        }
                    }
                }
                HXSetupRow("Import") {
                    Text(componentsProduct.map { "import \($0)" } ?? "Not a package: Proposals cannot import it")
                        .font(componentsProduct == nil ? .body : .body.monospaced()).foregroundStyle(.secondary)
                }
            } else if componentsMode == .separate {
                HXSetupRow("Repository") {
                    repoPicker("Components repository", selection: Binding(get: { componentsRepo }, set: { changeRepo(.designSystem, to: $0) }),
                               from: allRepos.filter { $0.fullName != appRepo }, none: "None")
                }
                if componentsRepo != nil {
                    folderRow(.designSystem, repo: componentsRepo, path: $componentsPath)
                }
            }
        }
    }

    /// A found folder brings its library name; a typed one is taken to be a package named after its folder.
    private func setComponentsFolder(_ path: String) {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        componentsFolder = path
        if let c = componentCandidates.first(where: { $0.path == trimmed }) { componentsProduct = c.isPackage ? c.product : nil }
        else { componentsProduct = trimmed.isEmpty ? nil : (trimmed as NSString).lastPathComponent }
    }

    private func scanComponents() {
        guard let path = appPath, !Snapshots.demoMode else { return }
        Task {
            let scan = await Task.detached { ComponentsScanner.scan(appRoot: path) }.value
            if appPath == path { componentCandidates = scan.candidates }
        }
    }

    private var notebookCard: some View {
        HXSettingsCard(symbol: "book.closed", tint: .orange, title: "Notebook",
                       summary: "Decisions, Spec and agent rules as plain files",
                       info: "Where \(displayName)'s decisions, Spec, agent rules and Proposal options live, as plain files. With it, anyone can pick the project up later, with any agent, even without Hatch.",
                       footnote: Text(notebookPath == nil
                                      ? "Choose the notebook's folder on this Mac so these settings are kept in it, not only in Hatch."
                                      : "Save also writes these settings to \(Text("project.json").font(.callout.monospaced())) in the notebook and commits it. Folders on this Mac are left out.")) {
            HXSetupRow("Repository") {
                repoPicker("Notebook repository", selection: Binding(get: { notebookRepo }, set: { changeRepo(.notebook, to: $0) }),
                           from: privateRepos.filter { $0.fullName != appRepo })
            }
            folderRow(.notebook, repo: notebookRepo, path: $notebookPath)
        }
    }

    private var branchesCard: some View {
        let base = baseBranch.isEmpty ? "main" : baseBranch
        let branch = integrationBranch.trimmingCharacters(in: .whitespaces).isEmpty ? "hatch" : integrationBranch
        return HXSettingsCard(symbol: "arrow.triangle.branch", tint: .green, title: "Branches",
                              summary: "ticket → \(branch) → " + (promotion == .manual ? "you merge into \(base)" : promotion == .automatic ? "merged into \(base)" : "pull request into \(base)"),
                              info: "Hatch has its own branch. Approved tickets merge into it, and nothing reaches your base branch without CI passing on it.") {
            HXBranchFlow(integration: branch, base: base, promotion: promotion)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            HXSetupRow("Hatch's branch") {
                TextField("Hatch's branch", text: $integrationBranch, prompt: Text("hatch"))
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden().font(.body.monospaced())
            }
            Text("When \(Text(branch).font(.callout.monospaced())) passes CI")
                .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 2)
            HXPromotionChoice(promotion: $promotion, base: base)
        }
    }

    private var agentsCard: some View {
        let build = buildCommand.trimmingCharacters(in: .whitespaces)
        var notes = "Before a ticket comes to you, its agent runs the build in its own copy of the app. Only the tests of the area it changed belong here; the full suite runs in CI."
        if state.hxSetting("max_agents") != nil { notes += " The number of agents set in Settings overrides this one." }
        return HXSettingsCard(symbol: "cpu", tint: .teal, title: "Agents",
                              summary: "Up to \(maxAgents) at once · " + (build.isEmpty ? "no build before review" : "builds before review"),
                              info: "How many work at once, when they ask you first, and how their work is built before you see it.",
                              footnote: Text(notes)) {
            HXSetupRow("Agents at once") {
                Stepper("\(maxAgents)", value: $maxAgents, in: 1...12).monospacedDigit().fixedSize()
            }
            HXSetupRow("Ask before plans that touch more than") {
                Stepper("\(threshold) files", value: $threshold, in: 1...100).monospacedDigit().fixedSize()
            }
            HXSetupRow("Build before review") {
                TextField("Build command", text: $buildCommand, prompt: Text("None"))
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden().font(.callout.monospaced())
            }
            HXSetupRow("Tests before review") {
                TextField("Test command", text: $testCommand, prompt: Text("None, CI runs them"))
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden().font(.callout.monospaced())
            }
        }
    }

    private var areasCard: some View {
        HXSettingsCard(symbol: "square.grid.2x2", tint: .purple, title: "Areas",
                       summary: areas.isEmpty ? "None yet" : "\(areas.count) \(areas.count == 1 ? "area" : "areas")",
                       info: "An area maps part of the code to a name and a Spec prefix, so agents read only what a ticket touches.",
                       footnote: Text("Notes for agents about an area go in the notebook, in \(Text("rules/areas/").font(.callout.monospaced())).")) {
            if areas.isEmpty {
                Text("No areas yet. Re-scan finds them in the app's folder.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .padding(.horizontal, 12)
            }
            ForEach(areas) { area in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area.name.isEmpty ? "Untitled" : area.name)
                        Text(area.globs.isEmpty ? "No paths" : area.globs)
                            .font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if !area.prefix.isEmpty {
                        Text(area.prefix).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    Button { editingArea = area } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless).help("Edit this area")
                    Button { areas.removeAll { $0.id == area.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove this area")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { editingArea = area }
            }
        } accessory: {
            HStack(spacing: 8) {
                Button("Re-scan") { rescan() }
                    .disabled(appPath == nil)
                    .help(appPath == nil ? "Choose the app's folder on this Mac first." : "Look for new folders and add them as areas.")
                Button { editingArea = HXAreaDraft(name: "", globs: "", prefix: "") } label: { Label("Add area", systemImage: "plus") }
                    .labelStyle(.iconOnly).help("Add an area")
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }

    // MARK: Rows

    private var githubReady: Bool { account.user != nil }
    private var allRepos: [GitHubRepoSummary] { account.repos }
    private var privateRepos: [GitHubRepoSummary] { account.repos.filter(\.isPrivate) }

    /// A repository chosen from GitHub, never typed. The current one stays listed even when the account can't see it.
    private func repoPicker(_ title: String, selection: Binding<String?>, from list: [GitHubRepoSummary], none: String? = nil) -> some View {
        Picker(title, selection: selection) {
            if let none { Text(none).tag(String?.none) } else if selection.wrappedValue == nil { Text("Choose…").tag(String?.none) }
            if let current = selection.wrappedValue, !list.contains(where: { $0.fullName == current }) {
                Text(githubReady ? "\(current) (not available)" : current).tag(String?.some(current))
            }
            ForEach(list) { repo in
                Text(repo.isPrivate ? repo.fullName : "\(repo.fullName) (public)").tag(String?.some(repo.fullName))
            }
        }
        .labelsHidden().fixedSize()
        .disabled(!githubReady)
    }

    /// The clone of `repo` on this Mac: found automatically when the repository changes, or chosen and checked.
    private func folderRow(_ role: RepoRole, repo: String?, path: Binding<String?>) -> some View {
        HXSetupRow("On this Mac") {
            if repo == nil {
                Text("Choose the repository first").foregroundStyle(.tertiary)
            } else if searching.contains(role) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Looking for a clone…").foregroundStyle(.secondary)
                }
            } else if let current = path.wrappedValue {
                HStack(spacing: 8) {
                    Label(hxAbbreviated(current), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.finished).lineLimit(1).truncationMode(.middle)
                    Button("Change…") { chooseFolder(for: role, repo: repo, path: path) }
                }
            } else {
                HStack(spacing: 8) {
                    Text("No clone found").foregroundStyle(.secondary)
                    Button("Choose…") { chooseFolder(for: role, repo: repo, path: path) }
                }
            }
        }
    }

    /// Save floats over the bottom of the page, so it is always in reach.
    private var saveBar: some View {
        HStack(spacing: 10) {
            if !message.isEmpty {
                Text(message).font(.callout)
                    .foregroundStyle(problem ? Theme.critical : .secondary)
                    .lineLimit(2).frame(maxWidth: 420, alignment: .trailing)
                    .transition(.opacity)
            }
            Button("Revert") { load() }
                .buttonStyle(.glass)
            Button { save() } label: { Label("Save", systemImage: "checkmark") }
                .buttonStyle(.glassProminent)
                .keyboardShortcut("s", modifiers: .command)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fixedSize()
        .glassEffect(.regular, in: Capsule())
        .padding(.bottom, 14)
        .padding(.trailing, 28)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: Repositories and folders

    private func changeRepo(_ role: RepoRole, to repo: String?) {
        switch role {
        case .app:
            guard repo != appRepo else { return }
            appRepo = repo; appPath = nil; branches = []
            baseBranch = account.repos.first { $0.fullName == repo }?.defaultBranch ?? "main"
            loadBranches()
            findClone(of: repo, role: .app) { appPath = $0; suggestBuild(fill: true); scanComponents() }
        case .designSystem:
            guard repo != componentsRepo else { return }
            componentsRepo = repo; componentsPath = nil
            findClone(of: repo, role: .designSystem) { componentsPath = $0 }
        case .notebook:
            guard repo != notebookRepo else { return }
            notebookRepo = repo; notebookPath = nil
            findClone(of: repo, role: .notebook) { notebookPath = $0 }
        case .tickets, .specimens:
            break
        }
    }

    private func findClone(of repo: String?, role: RepoRole, found: @escaping (String?) -> Void) {
        guard let repo, !Snapshots.demoMode else { return }
        searching.insert(role)
        Task {
            let paths = await Task.detached { LocalClones.find(repo) }.value
            searching.remove(role)
            found(paths.first)
        }
    }

    private func chooseFolder(for role: RepoRole, repo: String?, path: Binding<String?>) {
        guard let repo else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        if let current = path.wrappedValue { panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let config = (try? String(contentsOf: url.appendingPathComponent(".git/config"), encoding: .utf8)) ?? ""
        guard LocalClones.configPoints(config, at: repo) else {
            show("\(hxAbbreviated(url.path)) is not a clone of \(repo). Choose the folder that holds its .git.", problem: true)
            return
        }
        message = ""
        path.wrappedValue = url.path
        if role == .app { suggestBuild(fill: true); scanComponents() }
    }

    private func loadBranches() {
        guard let repo = appRepo, !Snapshots.demoMode else { return }
        Task {
            let names = await Task.detached { (try? HXGitHub.client().listBranches(repo)) ?? [] }.value
            guard appRepo == repo else { return }
            branches = names
            if !names.isEmpty && !names.contains(baseBranch), let first = names.first { baseBranch = first }
        }
    }

    /// Reads the build command the app's clone suggests. `fill` replaces the command only while it is empty or
    /// still the previous suggestion, so a command the owner typed is kept.
    private func suggestBuild(fill: Bool) {
        guard let path = appPath, !Snapshots.demoMode else { return }
        Task {
            let suggestion = await Task.detached { BuildCommand.suggest(in: path) }.value
            guard appPath == path else { return }
            if fill, buildCommand.trimmingCharacters(in: .whitespaces).isEmpty || buildCommand == suggestedBuild {
                buildCommand = suggestion ?? ""
            }
            suggestedBuild = suggestion
        }
    }

    private func rescan() {
        guard let path = appPath else { return }
        let found = HXAreasAdapter.suggestAreas(repoPath: path)
        let existing = Set(areas.map { $0.name.lowercased() })
        var added = 0
        for a in found where !existing.contains(a.name.lowercased()) {
            areas.append(HXAreaDraft(name: a.name, globs: a.paths.joined(separator: ", "), prefix: a.specPrefix ?? "", testPlans: a.testPlans))
            added += 1
        }
        show(added == 0 ? "No new areas found." : "Added \(added) \(added == 1 ? "area" : "areas"). Review them, then Save.")
    }

    // MARK: Loading and saving

    /// The settings as saved, or, for a project from before settings were stored, its repositories in the database.
    private var savedConfig: ProjectConfig {
        if let config = project.config { return config }
        let rows = (try? state.store.repos(projectId: project.id)) ?? []
        return ProjectConfig(name: project.name, ticketsRepo: rows.first { $0.role == .tickets }?.remote ?? "",
                             repos: rows.map { RepoConfig(role: $0.role, remote: $0.remote, branch: $0.defaultBranch, localPath: $0.localPath,
                                                          buildCommand: $0.buildCommand, testPlans: $0.testPlans) })
    }

    private func load() {
        let config = savedConfig
        name = project.name
        ticketsRepo = config.ticketsRepo.isEmpty ? nil : config.ticketsRepo
        ticketsIsDefault = ticketsRepo != nil && ((try? state.store.setting(hxDefaultTicketsSetting)) ?? nil) == ticketsRepo
        let app = config.repo(.app)
        appRepo = app?.remote
        appPath = app?.localPath
        baseBranch = app?.branch ?? "main"
        buildCommand = app?.buildCommand ?? ""
        testCommand = app?.testCommand ?? ""
        componentsRepo = config.repo(.designSystem)?.remote
        componentsPath = config.repo(.designSystem)?.localPath
        componentsFolder = config.components?.path ?? ""
        componentsProduct = config.components?.product
        componentsMode = config.components != nil ? .inApp : (componentsRepo != nil ? .separate : .none)
        notebookRepo = config.repo(.notebook)?.remote
        notebookPath = config.repo(.notebook)?.localPath
        integrationBranch = config.integrationBranch
        promotion = config.promotionMode
        maxAgents = config.maxAgents
        threshold = config.planApprovalFileThreshold
        areas = config.areas.map { a in
            HXAreaDraft(name: a.name, globs: a.paths.joined(separator: ", "), prefix: a.specPrefix ?? "", testPlans: a.testPlans)
        }
        message = ""
        problem = false
    }

    private func splitList(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func trimmed(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    /// The saved settings with the page's edits applied. Everything the page does not show, such as docs, the
    /// specimens repository or test plans, is kept as it was.
    private func makeConfig() -> ProjectConfig {
        var config = savedConfig
        config.name = displayName
        config.ticketsRepo = ticketsRepo ?? ""
        let defaults = Dictionary(account.repos.map { ($0.fullName, $0.defaultBranch) }, uniquingKeysWith: { a, _ in a })

        func set(_ role: RepoRole, remote: String?, branch: String? = nil, path: String?, change: (inout RepoConfig) -> Void = { _ in }) {
            guard let remote else { config.repos.removeAll { $0.role == role }; return }
            if let index = config.repos.firstIndex(where: { $0.role == role }) {
                if config.repos[index].remote != remote { config.repos[index].branch = defaults[remote] ?? "main" }
                config.repos[index].remote = remote
                config.repos[index].localPath = path
                if let branch { config.repos[index].branch = branch }
                change(&config.repos[index])
            } else {
                var repo = RepoConfig(role: role, remote: remote, branch: branch ?? defaults[remote] ?? "main", localPath: path)
                change(&repo)
                config.repos.append(repo)
            }
        }
        set(.tickets, remote: ticketsRepo, path: nil)
        set(.app, remote: appRepo, branch: trimmed(baseBranch) ?? "main", path: appPath) { repo in
            repo.buildCommand = trimmed(buildCommand)
            repo.testCommand = trimmed(testCommand)
        }
        set(.designSystem, remote: componentsMode == .separate ? componentsRepo : nil, path: componentsPath)
        let folder = componentsFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        config.components = componentsMode == .inApp && !folder.isEmpty ? ComponentsConfig(path: folder, product: componentsProduct) : nil
        set(.notebook, remote: notebookRepo, path: notebookPath)

        config.integrationBranch = trimmed(integrationBranch) ?? "hatch"
        config.promotion = promotion
        config.maxAgents = maxAgents
        config.planApprovalFileThreshold = threshold
        config.areas = areas.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map { a in
            AreaConfig(name: a.name, paths: splitList(a.globs), specPrefix: trimmed(a.prefix), testPlans: a.testPlans)
        }
        return config
    }

    /// What has to be fixed before Save can work, named so the owner knows where to look.
    private var missing: String? {
        if ticketsRepo == nil { return "Choose a tickets repository." }
        if appRepo == nil { return "Choose the app's repository." }
        let branch = trimmed(integrationBranch) ?? "hatch"
        if branch == trimmed(baseBranch) { return "Hatch's branch must differ from the base branch, \(baseBranch)." }
        return nil
    }

    private func save() {
        if let missing { show(missing, problem: true); return }
        let config = makeConfig()
        let tickets = ticketsRepo
        let makeDefault = ticketsIsDefault
        guard state.saveProject(key: project.key, name: displayName, config: config, notebook: { outcome in
            switch outcome {
            case .committed: show("Saved, and committed to the notebook.")
            case .unchanged: show("Saved.")
            case .noNotebook: show("Saved in Hatch. Choose the notebook's folder to keep the settings there too.")
            case .failed(let reason): show("Saved in Hatch, but the notebook could not be updated: \(reason)", problem: true)
            }
        }) != nil else { return }
        // The default tickets repository is a setting of its own, shared by every project.
        let saved = (try? state.store.setting(hxDefaultTicketsSetting)) ?? nil
        if makeDefault, let tickets, saved != tickets {
            state.perform("Save the default tickets repository") { try state.store.setSetting(hxDefaultTicketsSetting, tickets) }
        } else if !makeDefault, let saved, saved == tickets {
            state.perform("Save the default tickets repository") { try state.store.removeSetting(hxDefaultTicketsSetting) }
        }
    }

    private func show(_ text: String, problem: Bool = false) {
        withAnimation { message = text; self.problem = problem }
    }

    /// Snapshot runs: the repositories the demo account can see, so the pickers show real choices without the network.
    private func fillDemoAccount() {
        account.user = GitHubUser(login: "acme", name: "Acme")
        account.repos = [GitHubRepoSummary(fullName: "acme/hatch-tickets", isPrivate: true),
                         GitHubRepoSummary(fullName: "acme/app", isPrivate: true),
                         GitHubRepoSummary(fullName: "acme/design-system", isPrivate: true),
                         GitHubRepoSummary(fullName: "acme/app-notebook", isPrivate: true),
                         GitHubRepoSummary(fullName: "acme/public-site", isPrivate: false)]
        branches = ["main", "dev"]
    }
}

/// One part of a project in Project settings: a tinted tile, its name, an ⓘ that explains it as the assistant does,
/// a line with its current value, then its rows, edited in place.
struct HXSettingsCard<Content: View, Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let summary: String
    let info: String
    var footnote: Text?
    @ViewBuilder let content: Content
    @ViewBuilder let accessory: Accessory
    @State private var showInfo = false

    init(symbol: String, tint: Color, title: String, summary: String, info: String, footnote: Text? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol; self.tint = tint; self.title = title; self.summary = summary; self.info = info
        self.footnote = footnote; self.content = content(); self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                HXIconTile(symbol: symbol, tint: tint, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(title).font(.headline)
                        Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("About \(title.lowercased())")
                            .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                                Text(info)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: 280, alignment: .leading)
                                    .padding(14)
                            }
                    }
                    Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                accessory
            }
            .padding(12)
            Group(subviews: content) { subviews in
                ForEach(subviews) { view in
                    Divider().padding(.leading, 12)
                    view
                }
            }
            if let footnote {
                Divider().padding(.leading, 12)
                footnote
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hatchMark("HXSettingsCard")
    }
}

extension HXSettingsCard where Accessory == EmptyView {
    init(symbol: String, tint: Color, title: String, summary: String, info: String, footnote: Text? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(symbol: symbol, tint: tint, title: title, summary: summary, info: info, footnote: footnote,
                  content: content) { EmptyView() }
    }
}

/// The first thing a new owner sees: one button. GitHub, repositories and the folder are all handled in the setup sheet.
struct WelcomeView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 34)).foregroundStyle(.tertiary)
                Text("Let's set up a project").font(.title2.weight(.semibold))
            }
            Button("Set up a project") { state.showAddProject = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Add or edit one area. Three fields, in their own small sheet instead of rows of text fields on the page.
struct HXAreaEditSheet: View {
    @State var draft: HXAreaDraft
    let onSave: (HXAreaDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.name.isEmpty ? "New Area" : "Edit Area")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 4)
            Form {
                Section {
                    LabeledContent("Name") { TextField("Connections", text: $draft.name).labelsHidden().multilineTextAlignment(.trailing) }
                    LabeledContent("Paths") { TextField("Sources/Connections/**", text: $draft.globs).labelsHidden().multilineTextAlignment(.trailing) }
                    LabeledContent("Spec prefix") { TextField("CONN", text: $draft.prefix).labelsHidden().multilineTextAlignment(.trailing) }
                } footer: {
                    Text("Separate several paths with commas.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 20)
        }
        .frame(width: 480)
    }
}

/// Where a project's components are, as Project settings offers it.
enum HXComponentsMode: Hashable { case inApp, separate, none }
