import SwiftUI
import AppKit
import HatchCore
import HatchSync

// Settings, GitHub (design-review/settings-pages.html, "GitHub: much more to see"). One grouped Form: who is connected,
// what Hatch may do on GitHub and what is missing, how sync is doing, and every repository Hatch uses with its role.
// GitHub is asked off the main thread once each time the page appears, and again for the account and permissions when
// Hatch becomes active (the owner may be back from granting a permission on GitHub).

struct GitHubSettingsPage: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var account = GitHubAccountModel()
    @StateObject private var deviceFlow = GitHubDeviceFlow()
    @State private var syncInterval = 60
    @State private var defaultTickets: String?
    /// Tickets repositories added here that no project uses yet, kept in the `tickets_repos` setting.
    @State private var extraTickets: [String] = []
    /// CI on each project's integration branch, by "remote@branch", as `HXCIAdapter.status` words it. nil while asking.
    @State private var ci: [String: String?] = [:]
    @State private var adding = false
    @State private var confirmingDisconnect = false
    @State private var loaded = false

    static let ticketsReposSetting = "tickets_repos"

    /// Seconds between checks of GitHub; 0 is only when the owner asks.
    static let intervals: [(seconds: Int, title: String)] = [(60, "Minute"), (300, "5 minutes"), (900, "15 minutes"), (0, "Only when I ask")]

    var body: some View {
        Form {
            accountSection
            if connected { accessSection }
            syncSection
            ticketsSection
            projectsSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if loaded && !Snapshots.demoMode { account.refresh(details: true) }
        }
        .onChange(of: account.user?.login) { _, login in
            if login != nil && !Snapshots.demoMode { checkRepositories() }
        }
        .onChange(of: syncInterval) { _, seconds in
            guard loaded, !Snapshots.demoMode else { return }
            state.hxSaveSetting(AppState.syncIntervalSetting, String(seconds))
            state.restartSyncTimer()
        }
        .sheet(isPresented: $adding) {
            AddTicketsRepoSheet(account: account, existing: ticketsRepos.map(\.name), isFirst: ticketsRepos.isEmpty) { name, makeDefault in
                added(name, makeDefault: makeDefault)
            }
        }
        .confirmationDialog("Disconnect GitHub?", isPresented: $confirmingDisconnect) {
            Button("Disconnect", role: .destructive) {
                account.signOut()
                account.labelChecks = [:]
                ci = [:]
            }
        } message: {
            Text("Hatch stops syncing tickets until you connect again. Nothing changes on GitHub.")
        }
    }

    private var connected: Bool { account.user != nil }

    // MARK: Account

    private var accountSection: some View {
        Section {
            if let user = account.user {
                HStack(spacing: 14) {
                    GitHubAvatar(user: user)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name ?? user.login).font(.title3.weight(.semibold))
                        Text("@\(user.login)").foregroundStyle(.secondary)
                        Text("Connected through the Hatch GitHub App").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("Manage on GitHub…") { NSWorkspace.shared.open(account.manageRepositoriesURL) }
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 14) {
                    GitHubAvatar(user: nil)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.busy ? "Checking GitHub…" : "Not connected").font(.title3.weight(.semibold))
                        if let error = account.error {
                            Text(error).foregroundStyle(Theme.critical).lineLimit(2)
                        } else {
                            Text("Connect to sync tickets and see your repositories.").foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    if account.busy && !deviceFlow.busy {
                        ProgressView().controlSize(.small)
                    } else if deviceFlow.busy {
                        Button("Cancel") { deviceFlow.cancel() }
                    } else {
                        Button("Connect with GitHub") { deviceFlow.start { _ in account.refresh(details: true) } }
                            .buttonStyle(.glassProminent)
                    }
                }
                .padding(.vertical, 4)
                if let code = deviceFlow.userCode {
                    LabeledContent {
                        Text(code).font(.title3.monospaced().weight(.semibold)).foregroundStyle(.primary).textSelection(.enabled)
                    } label: {
                        Text("Code to enter on GitHub")
                        if let message = deviceFlow.message { Text(message) }
                    }
                }
            }
        } footer: {
            if let error = deviceFlow.error {
                Text(error).foregroundStyle(Theme.critical)
            } else if connected == false, let url = deviceFlow.verificationURL {
                HStack(alignment: .firstTextBaseline) {
                    Text("GitHub opened in your browser.")
                    Spacer()
                    Button("Open GitHub") { NSWorkspace.shared.open(url) }.buttonStyle(.link)
                }
            }
        }
    }

    // MARK: Access

    private var accessSection: some View {
        Section {
            LabeledContent {
                if let installation = account.installation {
                    if installation.allRepositories { Text("All repositories") }
                    else if let n = account.repositoryCount { Text("\(n) selected") }
                    else if account.busy { ProgressView().controlSize(.small) }
                    else { Text("Selected repositories") }
                } else if account.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Not installed").foregroundStyle(Theme.critical)
                }
            } label: {
                Text("Repositories Hatch can see")
                if let installation = account.installation {
                    Text(installation.account.isEmpty ? "The Hatch app is installed" : "Installed on \(installation.account)")
                } else if !account.busy {
                    Text("Install the Hatch GitHub App to give it repositories").foregroundStyle(Theme.critical)
                }
            }
            if let permissions = account.installation?.permissions {
                ForEach(GitHubPermissionNeed.all) { need in
                    PermissionRow(need: need, permissions: permissions)
                }
            }
        } header: {
            Text("Access")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                Text(missingPermissions == 0
                     ? "Hatch has every permission it needs."
                     : "Missing permissions are granted on GitHub; Hatch checks again when you come back.")
                Spacer(minLength: 16)
                Button("Fix on GitHub…") { NSWorkspace.shared.open(account.manageRepositoriesURL) }.buttonStyle(.link)
            }
        }
    }

    private var missingPermissions: Int {
        guard let permissions = account.installation?.permissions else { return 0 }
        return GitHubPermissionNeed.all.filter { !$0.optional && !$0.isMet(in: permissions) }.count
    }

    // MARK: Sync

    private var syncSection: some View {
        Section {
            LabeledContent {
                if state.syncing {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Syncing…") }
                } else {
                    Text(state.syncSummary.lastOK.map { $0.formatted(.relative(presentation: .named)).capitalizedFirst } ?? "Not yet")
                }
            } label: {
                Text("Last sync")
                if let message = state.syncSummary.message, !message.isEmpty {
                    Text(message).foregroundStyle(Theme.critical).lineLimit(2)
                }
            }
            LabeledContent("Waiting · failed") {
                Text("\(state.syncSummary.pending) · \(state.syncSummary.failed)")
                    .foregroundStyle(state.syncSummary.failed > 0 ? Theme.critical : .secondary)
            }
            Picker("Check GitHub every", selection: $syncInterval) {
                ForEach(Self.intervals, id: \.seconds) { Text($0.title).tag($0.seconds) }
                if !Self.intervals.contains(where: { $0.seconds == syncInterval }) {
                    Text("\(syncInterval) seconds").tag(syncInterval)
                }
            }
            LabeledContent {
                if let limit = account.rateLimit {
                    Text("\(limit.remaining.formatted()) of \(limit.limit.formatted())")
                        .foregroundStyle(limit.remaining * 10 < limit.limit ? Theme.critical : .secondary)
                } else if connected && account.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Text(connected ? "Unknown" : "Not connected")
                }
            } label: {
                Text("API calls left this hour")
                if let limit = account.rateLimit {
                    Text("Back to \(limit.limit.formatted()) at \(limit.reset.formatted(date: .omitted, time: .shortened))")
                }
            }
        } header: {
            HStack {
                Text("Sync")
                Spacer()
                Button("Sync Now") { state.syncNow() }
                    .buttonStyle(.link)
                    .disabled(state.syncing || !connected)
            }
        } footer: {
            Text("Your changes go to GitHub within seconds; this sets how often Hatch looks for changes made there.")
        }
    }

    // MARK: Tickets repositories

    private struct TicketsRepo: Identifiable {
        let name: String
        let isDefault: Bool
        let projects: [String]
        let isPrivate: Bool?
        var id: String { name.lowercased() }
    }

    /// Every tickets repository in use or saved: the default first, then by name.
    private var ticketsRepos: [TicketsRepo] {
        var names: [String] = []
        func add(_ name: String?) {
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
            names.append(name)
        }
        for project in state.projects { add(ticketsRepo(of: project)) }
        extraTickets.forEach { add($0) }
        names.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        if let defaultTickets {
            names.removeAll { $0.caseInsensitiveCompare(defaultTickets) == .orderedSame }
            names.insert(defaultTickets, at: 0)
        }
        return names.map { name in
            TicketsRepo(name: name, isDefault: name.caseInsensitiveCompare(defaultTickets ?? "") == .orderedSame,
                        projects: state.projects.filter { ticketsRepo(of: $0)?.caseInsensitiveCompare(name) == .orderedSame }.map(\.name),
                        isPrivate: privacy(of: name))
        }
    }

    private var ticketsSection: some View {
        Section {
            if ticketsRepos.isEmpty {
                Text("No tickets repository yet.").foregroundStyle(.secondary)
            }
            ForEach(ticketsRepos) { repo in
                LabeledContent {
                    Text(repo.projects.isEmpty ? "Not used" : repo.projects.joined(separator: ", "))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            RepoName(name: repo.name, isPrivate: repo.isPrivate)
                            if repo.isDefault { PlainChip(text: "Default") }
                        }
                        labelsLine(account.labelChecks[repo.name])
                    }
                }
                .contextMenu {
                    Button("Make Default") { makeDefault(repo.name) }.disabled(repo.isDefault)
                    Button("Repair Labels") { account.repairLabels(repo.name) }.disabled(!connected)
                    if repo.projects.isEmpty && !repo.isDefault {
                        Divider()
                        Button("Remove from List") { removeExtra(repo.name) }
                    }
                }
            }
        } header: {
            HStack {
                Text("Tickets repositories")
                Spacer()
                Button("Add…") { adding = true }
                    .buttonStyle(.link)
                    .disabled(!connected)
            }
        } footer: {
            Text("A tickets repository can be shared by several projects; new projects use the default.")
        }
    }

    @ViewBuilder private func labelsLine(_ check: GitHubAccountModel.LabelCheck?) -> some View {
        switch check {
        case .checking?: Subtitle(text: "Checking labels…", busy: true)
        case .repairing?: Subtitle(text: "Adding Hatch's labels…", busy: true)
        case .present?: Subtitle(text: "Labels all present")
        case .missing(let n)?: Subtitle(text: n == 1 ? "1 label missing; Control-click to repair" : "\(n) labels missing; Control-click to repair",
                                        critical: true)
        case .failed(let message)?: Subtitle(text: message, critical: true)
        case nil: EmptyView()
        }
    }

    // MARK: Project repositories

    private struct ProjectRepo: Identifiable {
        let remote: String
        let role: RepoRole
        var uses: [(project: Project, branch: String)]
        var id: String { role.rawValue + "|" + remote.lowercased() }
    }

    /// One row per repository and role that any project uses: the app, the notebook and separate components.
    private var projectRepos: [ProjectRepo] {
        var out: [ProjectRepo] = []
        for project in orderedProjects {
            for role in [RepoRole.app, .notebook, .designSystem] {
                guard let r = repo(of: project, role: role) else { continue }
                if let i = out.firstIndex(where: { $0.role == role && $0.remote.caseInsensitiveCompare(r.remote) == .orderedSame }) {
                    out[i].uses.append((project, r.branch))
                } else {
                    out.append(ProjectRepo(remote: r.remote, role: role, uses: [(project, r.branch)]))
                }
            }
        }
        return out
    }

    private var projectsSection: some View {
        Section {
            let repos = projectRepos
            if repos.isEmpty {
                Text("No project repositories yet. Choose them in Project settings.").foregroundStyle(.secondary)
            }
            ForEach(repos) { repo in
                LabeledContent {
                    Text(repo.uses.count == 1 ? "\(repo.uses[0].project.name) · \(repo.uses[0].branch)"
                                              : repo.uses.map(\.project.name).joined(separator: ", "))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            RepoName(name: repo.remote, isPrivate: privacy(of: repo.remote))
                            PlainChip(text: roleTitle(repo.role))
                        }
                        projectRepoLine(repo)
                    }
                }
            }
        } header: {
            Text("Project repositories")
        } footer: {
            if connected {
                HStack {
                    Spacer()
                    Button("Disconnect…", role: .destructive) { confirmingDisconnect = true }
                        .foregroundStyle(Theme.critical)
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder private func projectRepoLine(_ repo: ProjectRepo) -> some View {
        switch repo.role {
        case .app:
            if connected, let project = repo.uses.first?.project {
                let branch = integrationBranch(of: project)
                ciLine(branch: branch, status: ci["\(repo.remote)@\(branch)"])
            }
        case .notebook:
            if let project = repo.uses.first?.project {
                let status = (try? state.store.notebookStatus(projectId: project.id)) ?? (exportedAt: nil, pushedAt: nil, error: nil)
                if let error = status.error {
                    Subtitle(text: error, critical: true)
                } else {
                    Subtitle(text: status.pushedAt.map { "Pushed \($0.formatted(.relative(presentation: .named)))" } ?? "Not pushed yet")
                }
            }
        default:
            EmptyView()
        }
    }

    /// "CI on hatch ✓ passing": nothing until asked, a spinner while asking, red when failing or unreadable.
    @ViewBuilder private func ciLine(branch: String, status: String??) -> some View {
        switch status {
        case nil: EmptyView()
        case .some(nil): Subtitle(text: "Checking CI on \(branch)…", busy: true)
        case .some(.some(let text)):
            if text.hasPrefix("passing") {
                HStack(spacing: 4) {
                    Text("CI on \(branch)")
                    Image(systemName: "checkmark").foregroundStyle(Theme.finished)
                    Text("passing")
                }
                .font(.callout).foregroundStyle(.secondary)
            } else if text.hasPrefix("failing") {
                Subtitle(text: "CI on \(branch) \(text)", critical: true)
            } else {
                Subtitle(text: "CI on \(branch) \(text)")
            }
        }
    }

    // MARK: Data

    private var orderedProjects: [Project] {
        state.projects.sorted { lhs, rhs in
            if lhs.key == state.selectedProjectKey { return true }
            if rhs.key == state.selectedProjectKey { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func ticketsRepo(of project: Project) -> String? {
        let name = project.config?.ticketsRepo ?? (try? state.store.repo(projectId: project.id, role: .tickets))?.remote
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func repo(of project: Project, role: RepoRole) -> (remote: String, branch: String)? {
        if let config = project.config {
            guard let r = config.repo(role), !r.remote.isEmpty else { return nil }
            return (r.remote, r.branch)
        }
        guard let r = (try? state.store.repo(projectId: project.id, role: role)) ?? nil, !r.remote.isEmpty else { return nil }
        return (r.remote, r.defaultBranch)
    }

    private func integrationBranch(of project: Project) -> String { project.config?.integrationBranch ?? "hatch" }

    /// Private or public as GitHub lists it; nil when the account cannot see the repository (or is not connected).
    private func privacy(of name: String) -> Bool? {
        account.repos.first { $0.fullName.caseInsensitiveCompare(name) == .orderedSame }?.isPrivate
    }

    private func roleTitle(_ role: RepoRole) -> String {
        switch role {
        case .app: "App"
        case .notebook: "Notebook"
        case .designSystem: "Components"
        case .specimens: "Specimens"
        case .tickets: "Tickets"
        }
    }

    // MARK: Loading and changes

    private func load() {
        syncInterval = state.syncInterval
        defaultTickets = state.hxSetting(hxDefaultTicketsSetting)
        extraTickets = state.hxSetting(Self.ticketsReposSetting)
            .flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
        if Snapshots.demoMode {
            if !Snapshots.githubDisconnected {
                account.loadDemo()
                extraTickets = ["acme/client-tickets"]
                state.syncSummary.lastOK = Date().addingTimeInterval(-17 * 60)
                for repo in projectRepos where repo.role == .app {
                    if let project = repo.uses.first?.project { ci["\(repo.remote)@\(integrationBranch(of: project))"] = .some("passing") }
                }
            }
        } else {
            account.refresh(details: true)
        }
        loaded = true
    }

    /// Labels of each tickets repository and CI of each app repository, once per appearance, off the main thread.
    private func checkRepositories() {
        account.checkLabels(ticketsRepos.map(\.name))
        for repo in projectRepos where repo.role == .app {
            guard let project = repo.uses.first?.project else { continue }
            let branch = integrationBranch(of: project), remote = repo.remote, key = "\(remote)@\(branch)"
            ci[key] = .some(nil)
            Task {
                let text = await Task.detached { HXCIAdapter.status(remote: remote, ref: branch) }.value
                ci[key] = .some(text)
            }
        }
    }

    private func makeDefault(_ name: String) {
        defaultTickets = name
        guard !Snapshots.demoMode else { return }
        state.hxSaveSetting(hxDefaultTicketsSetting, name)
    }

    private func added(_ name: String, makeDefault isDefault: Bool) {
        if !extraTickets.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            extraTickets.append(name)
            saveExtras()
        }
        if isDefault { makeDefault(name) }
        account.checkLabels([name])
    }

    private func removeExtra(_ name: String) {
        extraTickets.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        saveExtras()
    }

    private func saveExtras() {
        guard !Snapshots.demoMode, let data = try? JSONEncoder().encode(extraTickets) else { return }
        state.hxSaveSetting(Self.ticketsReposSetting, String(decoding: data, as: UTF8.self))
    }
}

// MARK: Rows

/// A permission Hatch needs: what it is for, and ✓ or ✗ with what GitHub granted.
private struct PermissionRow: View {
    let need: GitHubPermissionNeed
    let permissions: [String: String]

    var body: some View {
        let granted = need.granted(in: permissions)
        let met = need.isMet(in: permissions)
        LabeledContent {
            HStack(spacing: 4) {
                if met {
                    Image(systemName: "checkmark").foregroundStyle(Theme.finished)
                } else if need.optional {
                    Image(systemName: "minus").foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "xmark").foregroundStyle(Theme.critical)
                }
                Text(value(granted: granted, met: met))
            }
            .accessibilityElement(children: .combine)
        } label: {
            Text(need.title)
            Text(need.reason)
        }
        .hatchMark("PermissionRow")
    }

    private func value(granted: GitHubAccess, met: Bool) -> String {
        switch granted {
        case .write: "read and write"
        case .read: met ? "read" : "read only"
        case .none: need.optional ? "not granted" : "missing"
        }
    }
}

/// A repository's name with a lock when it is private.
struct RepoName: View {
    let name: String
    let isPrivate: Bool?

    var body: some View {
        HStack(spacing: 4) {
            if isPrivate == true {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Private")
            }
            Text(name).lineLimit(1).truncationMode(.middle)
        }
        .hatchMark("RepoName")
    }
}

/// A row's second line: secondary, red for a problem, with a small spinner while something is asked.
struct Subtitle: View {
    let text: String
    var critical = false
    var busy = false

    var body: some View {
        HStack(spacing: 5) {
            if busy { ProgressView().controlSize(.mini) }
            Text(text).lineLimit(2)
        }
        .font(.callout)
        .foregroundStyle(critical ? Theme.critical : .secondary)
        .hatchMark("Subtitle")
    }
}

/// GitHub's picture for the account, round; initials until it loads or when there is none.
struct GitHubAvatar: View {
    let user: GitHubUser?
    var size: CGFloat = 54

    var body: some View {
        Group {
            if let url = user?.avatarURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .hatchMark("GitHubAvatar")
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                if let user {
                    Text(initials(user)).font(.system(size: size * 0.38, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "person.fill").font(.system(size: size * 0.42)).foregroundStyle(.tertiary)
                }
            }
    }

    private func initials(_ user: GitHubUser) -> String {
        let words = (user.name ?? "").split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return (letters.isEmpty ? String(user.login.prefix(1)) : letters).uppercased()
    }
}

// MARK: Add sheet

/// Adds a tickets repository: one of the account's private repositories, or a new private one. Hatch adds its labels.
private struct AddTicketsRepoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account: GitHubAccountModel
    let existing: [String]
    let isFirst: Bool
    let onAdded: (String, Bool) -> Void

    @State private var choice: String?
    @State private var newName = ""
    @State private var makeDefault = false
    @State private var working = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    private static let newTag = "\u{1}new"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add a Tickets Repository").font(.title3.weight(.semibold))
                Text("Tickets are GitHub issues, so the repository is private.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 20)
            Form {
                Section {
                    Picker("Repository", selection: $choice) {
                        Text("Choose…").tag(String?.none)
                        ForEach(candidates) { repo in Text(repo.fullName).tag(String?.some(repo.fullName)) }
                        Divider()
                        Text("New private repository…").tag(String?.some(Self.newTag))
                    }
                    if choice == Self.newTag {
                        TextField("Name", text: $newName, prompt: Text("owner/name"))
                            .focused($nameFocused)
                    }
                    Toggle("Make it the default", isOn: $makeDefault)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(Theme.critical)
                    } else {
                        Text(choice == Self.newTag ? "Hatch creates it private and adds its labels." : "Hatch adds its labels when they are missing.")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(choice == Self.newTag ? "Create" : "Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 480, height: 320)
        .onAppear {
            makeDefault = isFirst
            if let login = account.user?.login { newName = "\(login)/hatch-tickets" }
        }
        .onChange(of: choice) { _, value in
            error = nil
            if value == Self.newTag { nameFocused = true }
        }
    }

    /// Private repositories the account can see that are not in the list yet.
    private var candidates: [GitHubRepoSummary] {
        account.repos.filter { repo in
            repo.isPrivate && !existing.contains { $0.caseInsensitiveCompare(repo.fullName) == .orderedSame }
        }
    }

    private func add() {
        guard let choice else { error = "Choose a repository, or a new one."; return }
        let create = choice == Self.newTag
        let name = (create ? newName : choice).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = name.split(separator: "/")
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            error = "Write the name as owner/name."
            nameFocused = true
            return
        }
        if existing.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            error = "\(name) is already in the list."
            return
        }
        working = true
        error = nil
        account.prepareTicketsRepo(name, create: create) { result in
            working = false
            switch result {
            case .success(let report) where report.isPublic:
                error = "\(report.repo.fullName) is public. Tickets need a private repository."
            case .success(let report):
                onAdded(report.repo.fullName, makeDefault)
                dismiss()
            case .failure(let failure):
                error = GitHubAccountModel.describe(failure)
            }
        }
    }
}
