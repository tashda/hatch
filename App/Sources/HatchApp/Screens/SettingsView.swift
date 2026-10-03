import SwiftUI
import AppKit
import HatchCore
import HatchSync

/// Settings organized as a native navigation split view, with focused grouped forms.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: SettingsPage? = .workspace

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Workspace") {
                    settingsLink(.workspace)
                }
                Section("Services") {
                    settingsLink(.github)
                }
                Section("Automation") {
                    settingsLink(.agents)
                }
                Section("Applications") {
                    settingsLink(.apps)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
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
    }

    private func settingsLink(_ page: SettingsPage) -> some View {
        NavigationLink(value: page) {
            Label(page.title, systemImage: page.symbol)
        }
    }
}

private enum SettingsPage: Hashable {
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
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
                content
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }
}

private struct AgentSettingsPage: View {
    @EnvironmentObject var state: AppState
    @State private var maxAgents = 3
    @State private var claudeStatus = "Checking…"
    @State private var loaded = false

    var body: some View {
        SettingsPageForm(title: "Agents", subtitle: "Choose how Hatch runs local agent work.") {
            Stepper(value: $maxAgents, in: 1...12) { Text("Max agents at once: \(maxAgents)") }
                .onChange(of: maxAgents) { _, newValue in
                    if loaded { state.hxSaveSetting("max_agents", String(newValue)) }
                }
            LabeledContent("Claude CLI", value: claudeStatus)
            HXPathRow(title: "Claude CLI path", key: "claude_path", placeholder: "Found automatically", chooseApp: false)
        }
        .navigationTitle("Agents")
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        if let s = state.hxSetting("max_agents"), let n = Int(s) { maxAgents = n }
        else { maxAgents = (try? state.store.maxAgents(projectId: state.projectFilterId)) ?? 3 }
        loaded = true
        guard !Snapshots.demoMode else { claudeStatus = "Not checked in demo mode"; return }
        let configured = state.hxSetting("claude_path")
        Task { claudeStatus = await Task.detached { HXSettingsProbe.claudeStatus(configured: configured) }.value }
    }
}

private struct GitHubSettingsPage: View {
    @StateObject private var account = GitHubAccountModel()
    @StateObject private var deviceFlow = GitHubDeviceFlow()

    var body: some View {
        SettingsPageForm(title: "GitHub", subtitle: "Connect Hatch to a private tickets repository.") {
            LabeledContent("Account") { Text(accountLine).textSelection(.enabled) }
            if let error = account.error { Text(error).font(.callout).foregroundStyle(Theme.critical) }
            Button { deviceFlow.start { _ in account.refresh() } } label: {
                Label(deviceFlow.busy ? "Waiting for GitHub…" : (account.user == nil ? "Connect with GitHub" : "Reconnect with GitHub"), systemImage: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(.glassProminent)
            .disabled(deviceFlow.busy)
            .controlSize(.large)
            if let code = deviceFlow.userCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter this one-time code on GitHub").font(.callout)
                    HStack {
                        Text(code).font(.title2.monospaced().weight(.semibold)).textSelection(.enabled)
                        Spacer()
                        if let url = deviceFlow.verificationURL {
                            Button("Open GitHub") { NSWorkspace.shared.open(url) }.buttonStyle(.glass)
                        }
                    }
                }
            }
            if let message = deviceFlow.message { Text(message).font(.callout).foregroundStyle(.secondary) }
            if let error = deviceFlow.error { Text(error).font(.callout).foregroundStyle(Theme.critical) }
            HStack {
                if deviceFlow.busy { Button("Cancel") { deviceFlow.cancel() }.buttonStyle(.glass) }
                Spacer()
                if account.source == .stored {
                    Button { account.signOut() } label: { Label("Disconnect", systemImage: "xmark") }.buttonStyle(.glass)
                }
                Button { account.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.glass)
            }
            Text("Approve Hatch in your browser. The authorization is stored in the macOS Keychain. Hatch requests access only to repositories where its GitHub App is installed. Tickets repositories must be private.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle("GitHub")
        .onAppear { if !Snapshots.demoMode { account.refresh() } }
    }

    private var accountLine: String {
        if account.busy && account.user == nil { return "Checking…" }
        guard let user = account.user else { return account.source == .none ? "Not connected" : "Authorization not accepted" }
        let source: String
        switch account.source {
        case .stored: source = "Connected securely in Keychain"
        case .environment: source = "GITHUB_TOKEN environment variable"
        case .ghTool: source = "GitHub CLI"
        case .none: source = ""
        }
        return "@\(user.login) · \(source)"
    }
}

private struct AppPathSettingsPage: View {
    var body: some View {
        SettingsPageForm(title: "Apps", subtitle: "Choose the applications Hatch opens for project work.") {
            HXPathRow(title: "Preview app copy", key: "preview_app_path", placeholder: "Path to Echo (Preview).app", chooseApp: true)
            HXPathRow(title: "Hatch Stage", key: "stage_executable", placeholder: "Path to the Stage executable", chooseApp: false)
            HXPathRow(title: "Spec app", key: "spec_app_path", placeholder: "Optional: the project's Spec app", chooseApp: true)
        }
        .navigationTitle("Apps")
    }
}

private struct FileSettingsPage: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        SettingsPageForm(title: "Local data", subtitle: "Hatch's database and working files stay on this Mac.") {
            LabeledContent("Hatch home") { Text(state.paths.root.path).textSelection(.enabled) }
            LabeledContent("Database") { Text(state.paths.database.path).textSelection(.enabled) }
        }
        .navigationTitle("Local data")
    }
}

enum HXSettingsProbe {
    static func claudeStatus(configured: String?) -> String {
        if let path = HXAskAdapter.locateClaude(setting: configured) { return "Using \(path)" }
        return "claude CLI not found. Install Claude Code or set its path."
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
