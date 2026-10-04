import SwiftUI
import AppKit
import HatchCore
import HatchSync

/// Settings, GitHub (design-review/settings-pages.html). To be redesigned.
struct GitHubSettingsPage: View {
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
                        repositoryRow("Components", detail: "Only when they are a separate repository", remote: repository(project, role: .designSystem))
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

