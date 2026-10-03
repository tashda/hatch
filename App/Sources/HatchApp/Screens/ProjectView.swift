import SwiftUI
import AppKit
import HatchCore
import HatchSync

// Project settings (decisions L1, L2, M): a form that writes .hatch/project.json into the app repo and keeps the database in step.

struct HXRepoDraft: Identifiable {
    let id = UUID()
    var role: RepoRole
    var remote: String
    var branch: String
    var localPath: String
    var build: String
    var plans: String
}

struct HXAreaDraft: Identifiable {
    let id = UUID()
    var name: String
    var globs: String
    var prefix: String
}

struct HXDocDraft: Identifiable {
    let id = UUID()
    var path: String
}

func hxRoleName(_ role: RepoRole) -> String {
    switch role {
    case .app: return "App"
    case .designSystem: return "Design system"
    case .specimens: return "Specimens"
    case .tickets: return "Tickets"
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
        .sheet(isPresented: $showAdd) { AddProjectSheet() }
    }
}

struct ProjectForm: View {
    @EnvironmentObject var state: AppState
    let project: Project

    @State private var name = ""
    @State private var ticketsRepo = ""
    @State private var showRepositorySheet = false
    @StateObject private var account = GitHubAccountModel()
    @State private var maxAgents = 3
    @State private var integrationBranch = "hatch"
    @State private var threshold = 8
    @State private var repos: [HXRepoDraft] = []
    @State private var areas: [HXAreaDraft] = []
    @State private var docs: [HXDocDraft] = []
    @State private var message = ""
    @State private var showAdd = false
    @State private var loaded = false

    private var appLocalPath: String? {
        let path = repos.first { $0.role == .app }?.localPath ?? ""
        return path.isEmpty ? nil : path
    }

    private var configURL: URL? {
        guard let path = appLocalPath else { return nil }
        return URL(fileURLWithPath: path).appendingPathComponent(".hatch/project.json")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topRow
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .floatingCard()
                generalSection
                reposSection
                areasSection
                docsSection
                saveRow
            }
            .padding(3)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
        .environment(\.hxCardOnGray, true)
        .onAppear {
            if !Snapshots.demoMode { account.refresh() }
            if !loaded { load(); loaded = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hxGitHubAccountChanged)) { _ in
            account.refresh()
        }
        .sheet(isPresented: $showAdd) { AddProjectSheet() }
        .sheet(isPresented: $showRepositorySheet) {
            HXRepositorySelectionSheet(account: account, projectName: project.name,
                                       initial: selectedRepositoryNames,
                                       ticketsLocked: state.hasTickets(projectId: project.id)) { assignments in
                let saved = state.saveRepositoryAssignments(projectId: project.id, assignments)
                if saved {
                    ticketsRepo = assignments.tickets.fullName
                    updateRepo(.app, with: assignments.project)
                    updateRepo(.designSystem, with: assignments.design)
                    message = "Repositories saved."
                }
                return saved
            }
        }
    }

    // MARK: Sections

    private var topRow: some View {
        HStack(alignment: .top) {
            HXHeader(title: "Project: \(project.name)", subtitle: configURL.map { "Config in repo: \($0.path)" } ?? "Config in repo: .hatch/project.json (set the app repo's local path to write it)")
            Spacer()
            Button { showAdd = true } label: { Label("Add project", systemImage: "plus") }.buttonStyle(.glass)
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General").font(.headline)
            HXCard {
                VStack(alignment: .leading, spacing: 8) {
                    labeled("Name") { TextField("Name", text: $name).textFieldStyle(.roundedBorder) }
                    labeled("Tickets repo") {
                        Text(ticketsRepo.isEmpty ? "Not selected" : ticketsRepo)
                            .foregroundStyle(ticketsRepo.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                    labeled("Integration branch") { TextField("hatch", text: $integrationBranch).textFieldStyle(.roundedBorder) }
                    labeled("Max agents") { Stepper(value: $maxAgents, in: 1...12) { Text("\(maxAgents)") } }
                    labeled("Plan approval above") { Stepper(value: $threshold, in: 1...100) { Text("\(threshold) files") } }
                    if state.hxSetting("max_agents") != nil {
                        Text("A value set in Settings overrides Max agents.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).frame(width: 150, alignment: .leading).foregroundStyle(.secondary)
            content()
        }
    }

    private var reposSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Repositories").font(.headline)
                Spacer()
                Button("Choose GitHub repositories…") { showRepositorySheet = true }
                    .buttonStyle(.glass)
                if !repos.contains(where: { $0.role == .specimens }) {
                    Button { addRepo() } label: { Label("Add specimens repo", systemImage: "plus") }
                        .buttonStyle(.glass)
                }
            }
            HXCard {
                VStack(alignment: .leading, spacing: 12) {
                    if repos.isEmpty { Text("No repositories yet.").foregroundStyle(.secondary) }
                    ForEach($repos.filter { $0.wrappedValue.role != .tickets }) { $repo in repoRow($repo) }
                }
            }
        }
    }

    private func repoRow(_ repo: Binding<HXRepoDraft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(hxRoleName(repo.wrappedValue.role))
                    .frame(width: 140, alignment: .leading)
                Text(repo.wrappedValue.remote.isEmpty ? "Not selected" : repo.wrappedValue.remote)
                    .foregroundStyle(repo.wrappedValue.remote.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if repo.wrappedValue.role == .specimens {
                    HXRepoPickerMenu(account: account) { pick in
                        repo.wrappedValue.remote = pick.fullName
                        repo.wrappedValue.branch = pick.defaultBranch
                    }
                }
                TextField("Branch", text: repo.branch).textFieldStyle(.roundedBorder).frame(width: 90)
                Button { removeRepo(repo.wrappedValue.id) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
            }
            HStack {
                TextField("Local path", text: repo.localPath).textFieldStyle(.roundedBorder)
                Button("Choose...") { chooseFolder(repo) }
            }
            HStack {
                TextField("Build command", text: repo.build).textFieldStyle(.roundedBorder)
                TextField("Test plans (comma separated)", text: repo.plans).textFieldStyle(.roundedBorder)
            }
            Divider()
        }
    }

    private var areasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Areas").font(.headline)
                Spacer()
                Button("Re-scan areas") { rescan() }
                    .disabled(appLocalPath == nil)
                    .help(appLocalPath == nil ? "Set the app repository's local path first." : "Look for new folders and add them as areas.")
                Button { areas.append(HXAreaDraft(name: "", globs: "", prefix: "")) } label: { Label("Add area", systemImage: "plus") }
            }
            HXCard {
                VStack(alignment: .leading, spacing: 8) {
                    if areas.isEmpty { Text("No areas yet. An area index saves the most tokens per ticket.").foregroundStyle(.secondary) }
                    ForEach($areas) { $area in areaRow($area) }
                }
            }
        }
    }

    private func areaRow(_ area: Binding<HXAreaDraft>) -> some View {
        HStack {
            TextField("Name", text: area.name).textFieldStyle(.roundedBorder).frame(width: 150)
            TextField("Globs (comma separated)", text: area.globs).textFieldStyle(.roundedBorder)
            TextField("Spec prefix", text: area.prefix).textFieldStyle(.roundedBorder).frame(width: 90)
            Button { areas.removeAll { $0.id == area.wrappedValue.id } } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
        }
    }

    private var docsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Docs for agents").font(.headline)
                Spacer()
                Button { docs.append(HXDocDraft(path: "")) } label: { Label("Add doc", systemImage: "plus") }
            }
            HXCard {
                VStack(alignment: .leading, spacing: 6) {
                    if docs.isEmpty { Text("No docs listed.").foregroundStyle(.secondary) }
                    ForEach($docs) { $doc in
                        HStack {
                            TextField("CLAUDE.md", text: $doc.path).textFieldStyle(.roundedBorder)
                            Button { docs.removeAll { $0.id == doc.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private var saveRow: some View {
        HStack {
            Button { save() } label: { Label("Save", systemImage: "checkmark") }.buttonStyle(.glassProminent)
            Button("Revert") { load() }
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
        }
    }

    // MARK: Loading and saving

    private func load() {
        let config = project.config
        name = project.name
        ticketsRepo = config?.ticketsRepo ?? ""
        maxAgents = config?.maxAgents ?? 3
        integrationBranch = config?.integrationBranch ?? "hatch"
        threshold = config?.planApprovalFileThreshold ?? 8
        var list: [RepoConfig] = config?.repos ?? []
        if list.isEmpty {
            let rows = (try? state.store.repos(projectId: project.id)) ?? []
            list = rows.map { RepoConfig(role: $0.role, remote: $0.remote, branch: $0.defaultBranch, localPath: $0.localPath, buildCommand: $0.buildCommand, testPlans: $0.testPlans) }
        }
        repos = list.map { r in
            HXRepoDraft(role: r.role, remote: r.remote, branch: r.branch, localPath: r.localPath ?? "",
                        build: r.buildCommand ?? "", plans: (r.testPlans ?? []).joined(separator: ", "))
        }
        areas = (config?.areas ?? []).map { a in
            HXAreaDraft(name: a.name, globs: a.paths.joined(separator: ", "), prefix: a.specPrefix ?? "")
        }
        docs = (config?.docs ?? []).map { HXDocDraft(path: $0) }
        message = ""
    }

    private func splitList(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func makeConfig() -> ProjectConfig {
        let repoConfigs: [RepoConfig] = repos.filter { !$0.remote.isEmpty }.map { r in
            RepoConfig(role: r.role, remote: r.remote, branch: r.branch.isEmpty ? "main" : r.branch,
                       localPath: r.localPath.isEmpty ? nil : r.localPath,
                       buildCommand: r.build.isEmpty ? nil : r.build,
                       testPlans: splitList(r.plans))
        }
        let areaConfigs: [AreaConfig] = areas.filter { !$0.name.isEmpty }.map { a in
            AreaConfig(name: a.name, paths: splitList(a.globs), specPrefix: a.prefix.isEmpty ? nil : a.prefix)
        }
        return ProjectConfig(name: name, ticketsRepo: ticketsRepo, repos: repoConfigs, areas: areaConfigs,
                             docs: docs.map { $0.path }.filter { !$0.isEmpty }, maxAgents: maxAgents,
                             integrationBranch: integrationBranch.isEmpty ? "hatch" : integrationBranch,
                             planApprovalFileThreshold: threshold)
    }

    private func save() {
        let config = makeConfig()
        let url = configURL
        let key = project.key
        let projectName = name.isEmpty ? project.name : name
        let result: Bool? = state.perform("Save project") {
            try state.store.upsertProject(key: key, name: projectName, config: config)
            if let url { try config.save(to: url) }
            return url != nil
        }
        if let wrote = result {
            message = wrote ? "Saved, and written to .hatch/project.json." : "Saved. Set the app repo's local path to also write .hatch/project.json."
        }
    }

    private func addRepo() {
        guard !repos.contains(where: { $0.role == .specimens }) else { return }
        repos.append(HXRepoDraft(role: .specimens, remote: "", branch: "main", localPath: "", build: "", plans: ""))
    }

    private var selectedRepositoryNames: [RepoRole: String] {
        var names: [RepoRole: String] = [:]
        if !ticketsRepo.isEmpty { names[.tickets] = ticketsRepo }
        for role in [RepoRole.app, .designSystem] {
            if let remote = repos.first(where: { $0.role == role })?.remote, !remote.isEmpty { names[role] = remote }
        }
        return names
    }

    private func updateRepo(_ role: RepoRole, with selected: GitHubRepoSummary?) {
        if let index = repos.firstIndex(where: { $0.role == role }) {
            if let selected {
                if repos[index].remote != selected.fullName { repos[index].localPath = "" }
                repos[index].remote = selected.fullName
                repos[index].branch = selected.defaultBranch
            } else {
                repos.remove(at: index)
            }
        } else if let selected {
            repos.append(HXRepoDraft(role: role, remote: selected.fullName,
                                     branch: selected.defaultBranch, localPath: "", build: "", plans: ""))
        }
    }

    private func removeRepo(_ id: UUID) { repos.removeAll { $0.id == id } }

    private func chooseFolder(_ repo: Binding<HXRepoDraft>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { repo.wrappedValue.localPath = url.path }
    }

    private func rescan() {
        guard let path = appLocalPath else { return }
        let found = HXAreasAdapter.suggestAreas(repoPath: path)
        let existing = Set(areas.map { $0.name.lowercased() })
        var added = 0
        for a in found where !existing.contains(a.name.lowercased()) {
            areas.append(HXAreaDraft(name: a.name, globs: a.paths.joined(separator: ", "), prefix: a.specPrefix ?? ""))
            added += 1
        }
        message = added == 0 ? "No new areas found." : "Added \(added) area(s). Review them, then Save."
    }
}

/// The add-project flow: a key, a name, the tickets repo and the app repo.
struct AddProjectSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var name = ""
    @State private var ticketsRepo = ""
    @State private var appRemote = ""
    @State private var designRemote = ""
    @State private var appPath = ""
    @State private var branch = "dev"
    @State private var designBranch = "main"
    @State private var showRepositorySheet = false
    @StateObject private var account = GitHubAccountModel()

    private var canAdd: Bool {
        !ticketsRepo.isEmpty && !key.trimmingCharacters(in: .whitespaces).isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add project").font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 10)

            Form {
                Section("Project") {
                    LabeledContent("Name") {
                        TextField("Project name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    }
                    LabeledContent("Key") {
                        TextField("For labels, such as echo", text: $key)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    }
                }
                Section {
                    LabeledContent("Tickets", value: ticketsRepo.isEmpty ? "Not selected" : ticketsRepo)
                    LabeledContent("Project", value: appRemote.isEmpty ? "Not selected" : appRemote)
                    LabeledContent("Design", value: designRemote.isEmpty ? "Not selected" : designRemote)
                    HStack {
                        Spacer()
                        Button("Choose repositories…") { showRepositorySheet = true }
                    }
                } header: {
                    Text("GitHub repositories")
                } footer: {
                    Text("Tickets must use a private repository. Choose from repositories available to Hatch.")
                }
                Section("Local checkout") {
                    LabeledContent("App folder") {
                        HStack {
                            Text(appPath.isEmpty ? "Not selected" : appPath)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Button("Choose…") { choose() }
                        }
                    }
                    LabeledContent("Base branch") {
                        TextField("dev", text: $branch)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 500)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { add() }.buttonStyle(.glassProminent).disabled(!canAdd)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
        }
        .frame(width: 600)
        .onAppear { if !Snapshots.demoMode { account.refresh() } }
        .sheet(isPresented: $showRepositorySheet) {
            HXRepositorySelectionSheet(account: account, projectName: name.isEmpty ? "this project" : name,
                                       initial: selectedRepositoryNames) { assignments in
                ticketsRepo = assignments.tickets.fullName
                appRemote = assignments.project?.fullName ?? ""
                branch = assignments.project?.defaultBranch ?? "dev"
                designRemote = assignments.design?.fullName ?? ""
                designBranch = assignments.design?.defaultBranch ?? "main"
                return true
            }
        }
    }

    private var selectedRepositoryNames: [RepoRole: String] {
        var names: [RepoRole: String] = [:]
        if !ticketsRepo.isEmpty { names[.tickets] = ticketsRepo }
        if !appRemote.isEmpty { names[.app] = appRemote }
        if !designRemote.isEmpty { names[.designSystem] = designRemote }
        return names
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { appPath = url.path }
    }

    private func add() {
        let cleanKey = key.trimmingCharacters(in: .whitespaces).lowercased()
        var repos: [RepoConfig] = []
        if !appRemote.isEmpty {
            repos.append(RepoConfig(role: .app, remote: appRemote, branch: branch.isEmpty ? "dev" : branch, localPath: appPath.isEmpty ? nil : appPath))
        }
        if !designRemote.isEmpty {
            repos.append(RepoConfig(role: .designSystem, remote: designRemote, branch: designBranch))
        }
        if !ticketsRepo.isEmpty {
            repos.append(RepoConfig(role: .tickets, remote: ticketsRepo, branch: "main"))
        }
        let config = ProjectConfig(name: name, ticketsRepo: ticketsRepo, repos: repos)
        let created: Project? = state.perform("Add project") {
            try state.store.upsertProject(key: cleanKey, name: name, config: config)
        }
        if let created {
            state.selectedProjectKey = created.key
            state.navigate(to: .projects)
            dismiss()
        }
    }
}
