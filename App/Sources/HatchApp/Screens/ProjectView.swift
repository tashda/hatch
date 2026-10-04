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
    @State private var editingArea: HXAreaDraft?
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
        // A native grouped form in the page's panel, as in Echo's Settings: each group is a rounded inset
        // section, rows are label on the left and value on the right.
        Form {
            identitySection
            repositoriesSection
            foldersSection
            agentsSection
            areasSection
            docsSection
            advancedSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .onAppear {
            if !Snapshots.demoMode { account.refresh() }
            if !loaded { load(); loaded = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hxGitHubAccountChanged)) { _ in
            account.refresh()
        }
        .sheet(isPresented: $showAdd) { AddProjectSheet() }
        .sheet(item: $editingArea) { draft in
            HXAreaEditSheet(draft: draft) { saved in
                if let index = areas.firstIndex(where: { $0.id == saved.id }) { areas[index] = saved } else { areas.append(saved) }
            }
        }
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

    /// Who this is: the tile, an editable name, and where the config file lives.
    private var identitySection: some View {
        Section {
            HStack(spacing: 14) {
                ProjectTile(name: name.isEmpty ? project.name : name, key: project.key, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Name", text: $name)
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                    Text(configURL.map { $0.path } ?? "Choose the app's folder on this Mac to write .hatch/project.json")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                Button { showAdd = true } label: { Label("Add Project", systemImage: "plus") }
                    .buttonStyle(.glass)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Repositories: chosen from GitHub, never typed

    private var githubReady: Bool { account.user != nil || Snapshots.demoMode }

    private var choices: [GitHubRepoSummary] {
        if Snapshots.demoMode {
            return [GitHubRepoSummary(fullName: "acme/hatch-tickets", isPrivate: true),
                    GitHubRepoSummary(fullName: "acme/app", isPrivate: true),
                    GitHubRepoSummary(fullName: "acme/design-system", isPrivate: true),
                    GitHubRepoSummary(fullName: "acme/specimens", isPrivate: true),
                    GitHubRepoSummary(fullName: "acme/public-site", isPrivate: false)]
        }
        return account.repos
    }

    private func current(_ role: RepoRole) -> String? {
        if role == .tickets { return ticketsRepo.isEmpty ? nil : ticketsRepo }
        let remote = repos.first { $0.role == role }?.remote ?? ""
        return remote.isEmpty ? nil : remote
    }

    private func summary(_ name: String?) -> GitHubRepoSummary? {
        guard let name else { return nil }
        return choices.first { $0.fullName == name } ?? GitHubRepoSummary(fullName: name, isPrivate: true)
    }

    /// One pick from the menu. Tickets, App and Design go through the same save as before; Specimens edits the draft.
    private func pick(_ role: RepoRole, _ name: String?) {
        guard name != current(role) else { return }
        if role == .specimens {
            if let name, let repo = summary(name) {
                if let index = repos.firstIndex(where: { $0.role == .specimens }) {
                    repos[index].remote = repo.fullName; repos[index].branch = repo.defaultBranch
                } else {
                    repos.append(HXRepoDraft(role: .specimens, remote: repo.fullName, branch: repo.defaultBranch, localPath: "", build: "", plans: ""))
                }
            } else {
                repos.removeAll { $0.role == .specimens }
            }
            return
        }
        guard let tickets = summary(role == .tickets ? name : current(.tickets)), tickets.isPrivate else {
            message = "Tickets need a private repository."
            return
        }
        let assignments = HXRepositoryAssignments(
            tickets: tickets,
            project: summary(role == .app ? name : current(.app)),
            design: summary(role == .designSystem ? name : current(.designSystem)))
        if state.saveRepositoryAssignments(projectId: project.id, assignments) {
            ticketsRepo = assignments.tickets.fullName
            updateRepo(.app, with: assignments.project)
            updateRepo(.designSystem, with: assignments.design)
            message = "Repositories saved."
        }
    }

    private func repoRow(_ role: RepoRole, _ title: String, _ detail: String) -> some View {
        LabeledContent {
            if role == .tickets && state.hasTickets(projectId: project.id) {
                Label(current(role) ?? "Not selected", systemImage: "lock.fill").foregroundStyle(.secondary)
            } else {
                Picker(title, selection: Binding<String?>(get: { current(role) }, set: { pick(role, $0) })) {
                    if role != .tickets || current(role) == nil { Text(role == .tickets ? "Choose…" : "None").tag(String?.none) }
                    if let name = current(role), !choices.contains(where: { $0.fullName == name }) {
                        Text("\(name) (unavailable)").tag(String?.some(name))
                    }
                    ForEach(role == .tickets ? choices.filter { $0.isPrivate } : choices, id: \.fullName) { repo in
                        Text(repo.isPrivate ? repo.fullName : "\(repo.fullName) (public)").tag(String?.some(repo.fullName))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var repositoriesSection: some View {
        Section {
            if githubReady {
                repoRow(.tickets, "Tickets", "Issues and attachments")
                repoRow(.app, "App", "Source code and Specs")
                repoRow(.designSystem, "Design System", "Design assets")
                repoRow(.specimens, "Specimens", "Sample material for design rounds")
            } else {
                LabeledContent {
                    Button("Connect GitHub…") { showRepositorySheet = true }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GitHub is not connected")
                        Text("Repositories are chosen from your account.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("GitHub Repositories")
                Spacer()
                if githubReady && !Snapshots.demoMode {
                    Button { account.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).help("Reload the list from GitHub")
                }
            }
        } footer: {
            Text("Only repositories your GitHub account can reach appear here. Each branch follows the repository's default.")
        }
    }

    /// Where each repository lives on this Mac: the one thing that has to be picked from the file system.
    private var foldersSection: some View {
        Section {
            ForEach($repos.filter { $0.wrappedValue.role != .tickets && !$0.wrappedValue.remote.isEmpty }) { $repo in
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(repo.localPath.isEmpty ? "Not set" : repo.localPath)
                            .foregroundStyle(repo.localPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        Button("Choose…") { chooseFolder($repo) }
                    }
                } label: { Text(hxRoleName(repo.role)) }
            }
        } header: {
            Text("On This Mac")
        } footer: {
            Text("Agents work in these folders. Choose the clone of each repository.")
        }
    }

    private var agentsSection: some View {
        Section {
            LabeledContent("Agents at once") {
                HStack(spacing: 8) {
                    Text("\(maxAgents)").monospacedDigit()
                    Stepper("Agents at once", value: $maxAgents, in: 1...12).labelsHidden()
                }
            }
            LabeledContent("Ask before plans above") {
                HStack(spacing: 8) {
                    Text("\(threshold) files").monospacedDigit()
                    Stepper("Plan approval threshold", value: $threshold, in: 1...100).labelsHidden()
                }
            }
        } header: {
            Text("Agents")
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text("A plan that touches more files than this waits for your approval before an agent starts.")
                if state.hxSetting("max_agents") != nil {
                    Text("A value set in Settings overrides the number of agents.")
                }
            }
        }
    }

    // MARK: Areas and docs: lists, not rows of fields

    private var areasSection: some View {
        Section {
            if areas.isEmpty {
                Text("No areas yet. Re-scan finds them from the app's folders.").foregroundStyle(.secondary)
            }
            ForEach(areas) { area in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area.name.isEmpty ? "Untitled" : area.name)
                        Text(area.globs.isEmpty ? "No paths" : area.globs)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
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
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { editingArea = area }
            }
        } header: {
            HStack {
                Text("Areas")
                Spacer()
                Button("Re-scan") { rescan() }
                    .buttonStyle(.borderless)
                    .disabled(appLocalPath == nil)
                    .help(appLocalPath == nil ? "Choose the app's folder on this Mac first." : "Look for new folders and add them as areas.")
                Button { editingArea = HXAreaDraft(name: "", globs: "", prefix: "") } label: { Label("Add Area", systemImage: "plus") }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Add an area")
            }
        } footer: {
            Text("An area maps part of the code to a name and a Spec prefix, so agents read only what a ticket touches.")
        }
    }

    private var docsSection: some View {
        Section {
            if docs.isEmpty { Text("No docs listed.").foregroundStyle(.secondary) }
            ForEach(docs) { doc in
                HStack {
                    Label(doc.path, systemImage: "doc.text").lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { docs.removeAll { $0.id == doc.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove this doc")
                }
            }
        } header: {
            HStack {
                Text("Docs for Agents")
                Spacer()
                Button { addDoc() } label: { Label("Add Doc", systemImage: "plus") }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .disabled(appLocalPath == nil)
                    .help(appLocalPath == nil ? "Choose the app's folder on this Mac first." : "Pick a file in the app repository")
            }
        } footer: {
            Text("Files every agent reads first, such as CLAUDE.md.")
        }
    }

    /// Everything you rarely touch, folded away.
    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced") {
                LabeledContent("Merge into branch") {
                    TextField("hatch", text: $integrationBranch).labelsHidden().multilineTextAlignment(.trailing)
                }
                ForEach($repos.filter { $0.wrappedValue.role != .tickets && !$0.wrappedValue.remote.isEmpty }) { $repo in
                    LabeledContent("\(hxRoleName(repo.role)) build") {
                        TextField("swift build", text: $repo.build).labelsHidden().multilineTextAlignment(.trailing)
                    }
                    LabeledContent("\(hxRoleName(repo.role)) test plans") {
                        TextField("Comma separated", text: $repo.plans).labelsHidden().multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private func addDoc() {
        guard let base = appLocalPath else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: base)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            var path = url.path
            if path.hasPrefix(base + "/") { path = String(path.dropFirst(base.count + 1)) }
            if !docs.contains(where: { $0.path == path }) { docs.append(HXDocDraft(path: path)) }
        }
    }

    /// Save and Revert float over the bottom of the form, so they are always in reach.
    private var saveBar: some View {
        HStack(spacing: 10) {
            if !message.isEmpty {
                Text(message).font(.callout).foregroundStyle(.secondary).transition(.opacity)
            }
            Spacer()
            Button("Revert") { load() }
                .buttonStyle(.glass)
            Button { save() } label: { Label("Save", systemImage: "checkmark") }
                .buttonStyle(.glassProminent)
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

/// The first thing a new owner sees: what a project is made of, and one button to set it up.
struct WelcomeView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 34)).foregroundStyle(.tertiary)
                Text("Let's set up a project").font(.title2.weight(.semibold))
                Text("Hatch keeps a project's tickets in a private GitHub repository and lets agents work in the app's folder on this Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            VStack(alignment: .leading, spacing: 12) {
                step(1, "Connect GitHub", "Hatch lists the repositories your account can see.")
                step(2, "Choose repositories", "A private one for tickets; the app and design system if you have them.")
                step(3, "Choose the app's folder", "The local checkout agents build and test in.")
            }
            .frame(maxWidth: 420, alignment: .leading)
            Button("Set up a project") { state.showAddProject = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
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
