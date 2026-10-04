import SwiftUI
import AppKit
import HatchCore
import HatchSync

/// Settings organized as a native navigation split view, with focused grouped forms.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: SettingsPage? = .workspace
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField("Search Settings", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                List(selection: $selection) {
                    if matches(.workspace) { settingsLink(.workspace) }
                    if matches(.github) { settingsLink(.github) }
                    if matches(.agents) { settingsLink(.agents) }
                    if matches(.apps) { settingsLink(.apps) }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            Group {
                switch selection ?? .workspace {
                case .workspace: FileSettingsPage()
                case .agents: AgentSettingsPage()
                case .github: GitHubSettingsPage()
                case .apps: AppPathSettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 480)
        .onAppear(perform: showRequestedPage)
        .onChange(of: state.settingsPage) { _, _ in showRequestedPage() }
    }

    /// Another screen (Cmd-K's Connect GitHub) can ask for a page; the window may already be open.
    private func showRequestedPage() {
        guard let page = state.settingsPage else { return }
        selection = page
        state.settingsPage = nil
    }

    private func settingsLink(_ page: SettingsPage) -> some View {
        NavigationLink(value: page) {
            Label(page.title, systemImage: page.symbol)
        }
    }

    private func matches(_ page: SettingsPage) -> Bool {
        searchText.isEmpty || page.title.localizedCaseInsensitiveContains(searchText)
    }
}

enum SettingsPage: Hashable, CaseIterable {
    case workspace, agents, github, apps
    var title: String {
        switch self {
        case .workspace: "Local data"
        case .agents: "Agents"
        case .github: "GitHub"
        case .apps: "Apps"
        }
    }
    var symbol: String {
        switch self {
        case .workspace: "internaldrive"
        case .agents: "cpu"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .apps: "app.badge"
        }
    }
}

private struct SettingsPageForm<Content: View>: View {
    let section: String
    let footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
                content
            } header: {
                Text(section)
            } footer: {
                if let footer { Text(footer) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct GitHubSettingsPage: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var account = GitHubAccountModel()
    @StateObject private var deviceFlow = GitHubDeviceFlow()
    @State private var selectedProjectForRepositories: Project?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(accountTitle)
                            .font(.body.weight(.medium))
                        Text(accountDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button {
                        deviceFlow.start { _ in account.refresh() }
                    } label: {
                        Text(deviceFlow.busy ? "Waiting for GitHub…" : (account.user == nil ? "Connect with GitHub" : "Reconnect"))
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(deviceFlow.busy)
                    if account.user != nil {
                        Button { account.refresh() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh GitHub account")
                    }
                }
                .padding(.vertical, 4)

                if let error = account.error { Text(error).font(.callout).foregroundStyle(Theme.critical) }
                if let code = deviceFlow.userCode {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Enter this code on GitHub").font(.callout)
                            Text(code).font(.title3.monospaced().weight(.semibold)).textSelection(.enabled)
                        }
                        Spacer()
                        if let url = deviceFlow.verificationURL {
                            Button("Open GitHub") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
                if let message = deviceFlow.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                if let error = deviceFlow.error { Text(error).font(.callout).foregroundStyle(Theme.critical) }
                if deviceFlow.busy || account.source == .stored {
                    HStack {
                        Spacer()
                        if deviceFlow.busy { Button("Cancel") { deviceFlow.cancel() } }
                        if account.source == .stored { Button("Disconnect") { account.signOut() } }
                    }
                }
            } header: {
                Text("GitHub account")
            } footer: {
                Text("Authorization is stored in the macOS Keychain. Hatch can access repositories where its GitHub App is installed.")
            }

            if state.projects.isEmpty {
                Section("Project repositories") {
                    Text("No projects yet. Add a project to choose its repositories.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(orderedProjects) { project in
                    Section {
                        repositoryRow("Tickets", detail: "Issues and attachments", remote: repository(project, role: .tickets))
                        repositoryRow("Project", detail: "App source and Specs", remote: repository(project, role: .app))
                        repositoryRow("Components", detail: "Colors, type and shared views", remote: repository(project, role: .designSystem))
                        HStack {
                            Spacer()
                            Button("Choose repositories…") { selectedProjectForRepositories = project }
                        }
                    } header: {
                        Text("\(project.name) repositories")
                    } footer: {
                        Text("These are the repositories selected in Hatch for \(project.name). Tickets repositories must be private.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { if !Snapshots.demoMode { account.refresh() } }
        .sheet(item: $selectedProjectForRepositories) { project in
            HXRepositorySelectionSheet(account: account, projectName: project.name,
                                       initial: selectedRepositoryNames(for: project),
                                       ticketsLocked: state.hasTickets(projectId: project.id)) { assignments in
                state.saveRepositoryAssignments(projectId: project.id, assignments)
            }
        }
    }

    private var accountTitle: String {
        guard let user = account.user else { return "Not connected" }
        return "Connected as @\(user.login)"
    }

    private var accountDetail: String {
        if account.busy && account.user == nil { return "Checking authorization…" }
        guard account.user != nil else { return "Connect to choose repositories from GitHub and sync tickets." }
        switch account.source {
        case .stored: return "Authorization saved in Keychain"
        case .environment: return "Using GITHUB_TOKEN"
        case .ghTool: return "Using GitHub CLI"
        case .none: return ""
        }
    }

    private var orderedProjects: [Project] {
        state.projects.sorted { lhs, rhs in
            if lhs.key == state.selectedProjectKey { return true }
            if rhs.key == state.selectedProjectKey { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func repository(_ project: Project, role: RepoRole) -> String? {
        let remote: String?
        if let config = project.config {
            remote = role == .tickets ? config.ticketsRepo : config.repo(role)?.remote
        } else {
            remote = (try? state.store.repo(projectId: project.id, role: role))?.remote
        }
        let trimmed = remote?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func selectedRepositoryNames(for project: Project) -> [RepoRole: String] {
        var names: [RepoRole: String] = [:]
        for role in [RepoRole.tickets, .app, .designSystem] {
            if let remote = repository(project, role: role) { names[role] = remote }
        }
        return names
    }

    private func repositoryRow(_ title: String, detail: String, remote: String?) -> some View {
        LabeledContent {
            Text(remote ?? "Not selected")
                .foregroundStyle(remote == nil ? .secondary : .primary)
                .textSelection(.enabled)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AppPathSettingsPage: View {
    var body: some View {
        SettingsPageForm(section: "Applications", footer: "Choose the applications Hatch opens for project work.") {
            HXPathRow(title: "Preview app copy", key: "preview_app_path", placeholder: "Path to Echo (Preview).app", chooseApp: true)
            HXPathRow(title: "Hatch Stage", key: "stage_executable", placeholder: "Path to the Stage executable", chooseApp: false)
            HXPathRow(title: "Spec app", key: "spec_app_path", placeholder: "Optional: the project's Spec app", chooseApp: true)
        }
    }
}

private struct FileSettingsPage: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        SettingsPageForm(section: "Local data", footer: "Hatch's database and working files stay on this Mac.") {
            LabeledContent("Hatch home") { Text(state.paths.root.path).textSelection(.enabled) }
            LabeledContent("Database") { Text(state.paths.database.path).textSelection(.enabled) }
        }
    }
}

/// One path setting with a text field and a Choose button.
struct HXPathRow: View {
    @EnvironmentObject var state: AppState
    let title: String
    let key: String
    let placeholder: String
    let chooseApp: Bool

    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        HStack {
            Text(title).frame(width: 130, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
            Button("Choose…") { choose() }
        }
        .onAppear {
            if !loaded { text = state.hxSetting(key) ?? ""; loaded = true }
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard loaded else { return }
        if text != (state.hxSetting(key) ?? "") { state.hxSaveSetting(key, text) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = chooseApp
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { text = url.path; commit() }
    }
}
