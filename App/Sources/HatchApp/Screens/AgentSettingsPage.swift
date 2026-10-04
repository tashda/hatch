import SwiftUI
import AppKit
import HatchCore
import HatchAgent

/// Settings, Agents: which provider and model each task uses, and the providers Hatch can reach.
/// Providers are connected once, turned on or off, and keep the model list they last fetched (refreshed daily and on
/// demand), so a newly released model can be picked as soon as the provider lists it.
struct AgentSettingsPage: View {
    @EnvironmentObject var state: AppState
    @State private var settings: AgentSettings?
    @State private var statuses: [String: ProviderStatus] = [:]
    @State private var refreshing: Set<String> = []
    @State private var testing: Set<String> = []
    @State private var tests: [String: Result<ProbeResult, ProbeFailure>] = [:]
    @State private var editing: AgentProvider?
    @State private var deleting: AgentProvider?
    @State private var maxAgents = 3
    @State private var loaded = false

    struct ProbeFailure: Error { let message: String }

    var body: some View {
        Form {
            if let settings {
                Section {
                    ForEach(AgentRole.allCases) { role in
                        RoleRow(role: role, settings: settings, onChange: { choice in update { $0.setChoice(choice, for: role) } },
                                test: tests["role-\(role.rawValue)"], testing: testing.contains("role-\(role.rawValue)"),
                                onTest: { testRole(role) })
                    }
                } header: {
                    Text("Tasks")
                } footer: {
                    Text("Each task uses the provider and model chosen here. Only providers that are on can be chosen.")
                }

                Section {
                    ForEach(settings.providers) { provider in
                        ProviderRow(provider: provider, status: statuses[provider.id], usedBy: settings.roles(using: provider.id),
                                    refreshing: refreshing.contains(provider.id), testing: testing.contains(provider.id),
                                    test: tests[provider.id],
                                    onToggle: { on in setEnabled(provider, on) },
                                    onRefresh: { refreshModels(provider.id) },
                                    onTest: { testProvider(provider) },
                                    onEdit: { editing = provider },
                                    onDelete: { deleting = provider })
                    }
                    HStack {
                        Spacer()
                        Menu {
                            ForEach(ProviderPreset.all) { preset in
                                Button(preset.title) { editing = preset.make() }
                            }
                        } label: {
                            Label("Add provider", systemImage: "plus")
                        }
                        .fixedSize()
                    }
                } header: {
                    Text("Providers")
                } footer: {
                    Text("A program provider (Claude Code, Codex, Gemini CLI, opencode) runs the official program and uses the plan it is signed in with. An API provider is billed per token to its key. Keys are stored in the Keychain.")
                }
            } else {
                Section { ProgressView("Loading providers…") }
            }

            Section {
                Stepper(value: $maxAgents, in: 1...12) { Text("Max agents at once: \(maxAgents)") }
                    .onChange(of: maxAgents) { _, newValue in
                        if loaded { state.hxSaveSetting("max_agents", String(newValue)) }
                    }
            } header: {
                Text("Agent work")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear(perform: load)
        .sheet(item: $editing) { provider in
            ProviderEditor(provider: provider, isNew: settings?.provider(provider.id) == nil) { saved, key in
                save(saved, key: key)
            }
        }
        .confirmationDialog("Remove \(deleting?.name ?? "provider")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { provider in
            Button("Remove", role: .destructive) { remove(provider) }
        } message: { provider in
            let used = settings?.roles(using: provider.id) ?? []
            Text(used.isEmpty ? "Its saved API key is deleted too." : "\(used.map(\.title).joined(separator: " and ")) will have no provider until you choose another. Its saved API key is deleted too.")
        }
    }

    // MARK: Loading and saving

    private func load() {
        guard !loaded else { return }
        if let s = state.hxSetting("max_agents"), let n = Int(s) { maxAgents = n }
        else { maxAgents = (try? state.store.maxAgents(projectId: state.projectFilterId)) ?? 3 }
        loaded = true
        let store = state.store
        let demo = Snapshots.demoMode
        Task {
            let first = await Task.detached { AgentSettings.load(from: store, detect: !demo) }.value
            settings = first
            guard !demo else { return }
            // First run: save the detected setup, so the CLI and Iris see the same providers as this page.
            if (try? store.setting(AgentSettings.settingKey)) == nil { persist(first) }
            checkAll()
            for p in first.providers where p.enabled && ModelCatalog.isStale(p) { refreshModels(p.id) }
        }
    }

    private func update(_ change: (inout AgentSettings) -> Void) {
        guard var s = settings else { return }
        change(&s)
        settings = s
        persist(s)
    }

    private func persist(_ s: AgentSettings) {
        guard !Snapshots.demoMode else { return }
        state.perform("Save agent settings") { try s.save(to: state.store) }
    }

    private func save(_ provider: AgentProvider, key: KeyChange) {
        switch key {
        case .keep: break
        case .set(let k): HXAgentKeychain.write(provider.id, k)
        case .remove: HXAgentKeychain.delete(provider.id)
        }
        let isNew = settings?.provider(provider.id) == nil
        update { s in
            s.update(provider)
            // A first provider that is on gets the tasks that have none yet.
            for role in AgentRole.allCases where s.choice(role) == nil && provider.enabled {
                s.setChoice(RoleChoice(providerId: provider.id), for: role)
            }
        }
        check(provider.id)
        if isNew || provider.models.isEmpty { refreshModels(provider.id) }
    }

    private func remove(_ provider: AgentProvider) {
        HXAgentKeychain.delete(provider.id)
        update { $0.remove(provider.id) }
        deleting = nil
    }

    private func setEnabled(_ provider: AgentProvider, _ on: Bool) {
        update { s in
            guard var p = s.provider(provider.id) else { return }
            p.enabled = on
            s.update(p)
        }
        if on, ModelCatalog.isStale(provider) { refreshModels(provider.id) }
    }

    // MARK: Background work

    private func checkAll() { for p in settings?.providers ?? [] { check(p.id) } }

    private func check(_ id: String) {
        guard !Snapshots.demoMode, let p = settings?.provider(id) else { return }
        let context = state.agentContext
        Task {
            let status = await Task.detached { ProviderCheck.status(p, context: context) }.value
            statuses[id] = status
        }
    }

    private func refreshModels(_ id: String) {
        guard !Snapshots.demoMode, var p = settings?.provider(id), !refreshing.contains(id) else { return }
        refreshing.insert(id)
        let context = state.agentContext
        Task {
            p = await Task.detached { [p] in
                var copy = p
                ModelCatalog.refresh(&copy, context: context)
                return copy
            }.value
            refreshing.remove(id)
            // Only the list changes; other edits made meanwhile are kept.
            update { s in
                guard var current = s.provider(id) else { return }
                current.models = p.models; current.modelsFetchedAt = p.modelsFetchedAt; current.modelsError = p.modelsError
                s.update(current)
            }
        }
    }

    private func testProvider(_ provider: AgentProvider) {
        let context = state.agentContext
        runTest(key: provider.id) { try ProviderCheck.test(provider, model: nil, context: context) }
    }

    private func testRole(_ role: AgentRole) {
        guard let settings else { return }
        let context = state.agentContext
        runTest(key: "role-\(role.rawValue)") {
            let agent = try AgentFactory.resolve(role, settings: settings, context: context)
            return try ProviderCheck.test(agent.provider, model: agent.model, effort: agent.effort, thinking: agent.thinking, context: context)
        }
    }

    private func runTest(key: String, _ work: @escaping @Sendable () throws -> ProbeResult) {
        guard !testing.contains(key) else { return }
        testing.insert(key)
        tests[key] = nil
        Task {
            let result: Result<ProbeResult, ProbeFailure> = await Task.detached {
                do { return .success(try work()) } catch { return .failure(ProbeFailure(message: "\(error)")) }
            }.value
            tests[key] = result
            testing.remove(key)
        }
    }
}

enum KeyChange { case keep, set(String), remove }

// MARK: Task row

private struct RoleRow: View {
    let role: AgentRole
    let settings: AgentSettings
    let onChange: (RoleChoice?) -> Void
    let test: Result<ProbeResult, AgentSettingsPage.ProbeFailure>?
    let testing: Bool
    let onTest: () -> Void

    @State private var customModel = ""
    @State private var askingCustom = false

    private var choice: RoleChoice? { settings.choice(role) }
    private var provider: AgentProvider? { choice.flatMap { settings.provider($0.providerId) } }
    private var selectedModel: ModelInfo? { provider?.model(choice?.model ?? provider?.defaultModel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.title).font(.body.weight(.medium))
                    Text(role.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(testing ? "Testing…" : "Test", action: onTest)
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(testing || provider?.enabled != true)
                    .help("Send a one-line prompt with this task's provider and model")
            }
            Picker("Provider", selection: providerBinding) {
                Text("None").tag("")
                ForEach(settings.providers.filter { $0.enabled || $0.id == choice?.providerId }) { p in
                    Text(p.enabled ? p.name : "\(p.name) (off)").tag(p.id)
                }
            }
            if let provider {
                Picker("Model", selection: modelBinding) {
                    Text(provider.defaultModel.map { "Provider default (\($0))" } ?? "Program default").tag("")
                    let featured = provider.models.filter(\.featured)
                    let older = provider.models.filter { !$0.featured }
                    ForEach(featured) { m in Text(modelTitle(m)).tag(m.id) }
                    if !older.isEmpty {
                        Section("Older models") { ForEach(older) { m in Text(modelTitle(m)).tag(m.id) } }
                    }
                    if let current = choice?.model, provider.model(current) == nil {
                        Text("\(current) (typed)").tag(current)
                    }
                    Divider()
                    Text("Other model…").tag(Self.otherTag)
                }
                if let efforts = selectedModel?.efforts, !efforts.isEmpty {
                    Picker("Effort", selection: effortBinding) {
                        Text(selectedModel?.defaultEffort.map { "Model default (\($0))" } ?? "Model default").tag("")
                        ForEach(efforts, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
                // Only for a known model without effort levels; the program's own default model is unknown here.
                if provider.kind == .claudeCode, let m = selectedModel, m.efforts.isEmpty {
                    Toggle("Thinking", isOn: thinkingBinding)
                        .help("Off sends MAX_THINKING_TOKENS=0 to Claude Code: faster and far fewer tokens for short, structured work")
                }
                if let m = selectedModel, !m.isAlias, let note = m.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Text(provider.billing).font(.caption).foregroundStyle(.secondary)
                if !provider.enabled {
                    Label("\(provider.name) is off, so \(role.title) cannot run.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Theme.critical)
                }
            } else {
                Label("\(role.title) has no provider and will not run.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.critical)
            }
            Text(role.recommendation).font(.caption).foregroundStyle(.secondary)
            TestResultView(result: test)
        }
        .padding(.vertical, 4)
        .alert("Model name", isPresented: $askingCustom) {
            TextField("For example claude-sonnet-5-5", text: $customModel)
            Button("Use") {
                let name = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { set(model: name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type a model id exactly as \(provider?.name ?? "the provider") expects it.")
        }
    }

    static let otherTag = "\u{0}other"

    private func modelTitle(_ m: ModelInfo) -> String {
        if m.isAlias { return m.note.map { "\(m.name ?? m.id): \($0.replacingOccurrences(of: "Now ", with: ""))" } ?? (m.name ?? m.id) }
        return m.name.map { $0 == m.id ? m.id : "\($0)" } ?? m.id
    }

    private var providerBinding: Binding<String> {
        Binding(get: { choice?.providerId ?? "" }, set: { id in
            onChange(id.isEmpty ? nil : RoleChoice(providerId: id))
        })
    }

    private var modelBinding: Binding<String> {
        Binding(get: { choice?.model ?? "" }, set: { id in
            if id == Self.otherTag { customModel = choice?.model ?? ""; askingCustom = true; return }
            set(model: id.isEmpty ? nil : id)
        })
    }

    /// On unless the task turned it off; Claude Code thinks by default.
    private var thinkingBinding: Binding<Bool> {
        Binding(get: { choice?.thinking ?? true }, set: { on in
            guard var c = choice else { return }
            c.thinking = on ? nil : false
            onChange(c)
        })
    }

    private var effortBinding: Binding<String> {
        Binding(get: { choice?.effort ?? "" }, set: { e in
            guard var c = choice else { return }
            c.effort = e.isEmpty ? nil : e
            onChange(c)
        })
    }

    private func set(model: String?) {
        guard var c = choice else { return }
        c.model = model
        // An effort the new model does not take is dropped rather than sent.
        if let e = c.effort, let p = provider, let info = p.model(model ?? p.defaultModel), !info.efforts.contains(e) { c.effort = nil }
        // A model with effort levels controls thinking through effort; the on/off switch is only for models without.
        if let p = provider, let info = p.model(model ?? p.defaultModel), !info.efforts.isEmpty { c.thinking = nil }
        onChange(c)
    }
}

// MARK: Provider row

private struct ProviderRow: View {
    let provider: AgentProvider
    let status: ProviderStatus?
    let usedBy: [AgentRole]
    let refreshing: Bool
    let testing: Bool
    let test: Result<ProbeResult, AgentSettingsPage.ProbeFailure>?
    let onToggle: (Bool) -> Void
    let onRefresh: () -> Void
    let onTest: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Toggle(isOn: Binding(get: { provider.enabled }, set: onToggle)) { EmptyView() }
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .help(provider.enabled ? "Turn off" : "Turn on")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name).font(.body.weight(.medium))
                        if provider.name != provider.kind.displayName {
                            Text(provider.kind.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let status {
                        Label(status.summary, systemImage: status.ready ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(status.ready ? Color.secondary : Theme.critical)
                    }
                    Text(modelsLine).font(.caption).foregroundStyle(provider.modelsError == nil ? Color.secondary : Theme.critical)
                    if !usedBy.isEmpty {
                        Text("Used by \(usedBy.map(\.title).joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onRefresh) {
                    if refreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.borderless)
                .disabled(refreshing)
                .help("Refresh the model list")
                Button(testing ? "Testing…" : "Test", action: onTest)
                    .buttonStyle(.bordered).controlSize(.small).disabled(testing)
                    .help("Send a one-line prompt with the default model")
                Button("Edit…", action: onEdit).buttonStyle(.bordered).controlSize(.small)
                Menu {
                    Button("Remove…", role: .destructive, action: onDelete)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).fixedSize()
            }
            TestResultView(result: test)
        }
        .padding(.vertical, 4)
    }

    private var modelsLine: String {
        if let e = provider.modelsError { return "Models: \(e)" }
        guard let at = provider.modelsFetchedAt else { return refreshing ? "Fetching models…" : "Models not fetched yet." }
        let count = provider.models.filter { !$0.isAlias }.count
        return "\(count) model\(count == 1 ? "" : "s") · updated \(at.formatted(.relative(presentation: .named)))"
    }
}

private struct TestResultView: View {
    let result: Result<ProbeResult, AgentSettingsPage.ProbeFailure>?

    var body: some View {
        switch result {
        case .success(let r)?:
            Label("Answered \"\(r.text.prefix(40))\" in \(String(format: "%.1f", r.seconds)) s · \(hxTokens(r.tokensIn)) in, \(hxTokens(r.tokensOut)) out\(r.model.map { " · \($0)" } ?? "")",
                  systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        case .failure(let f)?:
            Label(f.message, systemImage: "xmark.octagon").font(.caption).foregroundStyle(Theme.critical).textSelection(.enabled)
        case nil:
            EmptyView()
        }
    }
}

// MARK: Editor

/// Add or change one provider. The API key goes to the Keychain on Save; it is never shown again.
private struct ProviderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var provider: AgentProvider
    let isNew: Bool
    let onSave: (AgentProvider, KeyChange) -> Void

    @State private var key = ""
    @State private var removeKey = false
    @State private var arguments = ""
    @State private var hasStoredKey = false

    init(provider: AgentProvider, isNew: Bool, onSave: @escaping (AgentProvider, KeyChange) -> Void) {
        _provider = State(initialValue: provider)
        self.isNew = isNew
        self.onSave = onSave
        _arguments = State(initialValue: provider.extraArguments.joined(separator: " "))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $provider.name)
                    LabeledContent("Kind", value: provider.kind.displayName)
                    Toggle("On", isOn: $provider.enabled)
                } footer: {
                    Text(provider.billing)
                }
                if let program = provider.kind.program {
                    Section("Program") {
                        HStack {
                            TextField("Path", text: optional($provider.executable), prompt: Text("Found automatically (\(program))"))
                            Button("Choose…", action: choose)
                        }
                        TextField("Extra arguments", text: $arguments, prompt: Text("Optional, separated by spaces"))
                    }
                }
                if provider.kind == .claudeCode {
                    Section {
                        Picker("Sign in with", selection: Binding(get: { provider.signIn ?? .account }, set: { provider.signIn = $0 })) {
                            ForEach(ClaudeSignIn.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    } footer: {
                        Text("Claude account uses the plan you are signed in with in Claude Code; any Anthropic key in the environment is ignored. An endpoint such as Z.ai's (https://api.z.ai/api/anthropic) runs GLM through Claude Code.")
                    }
                }
                if provider.needsBaseURL || provider.kind == .anthropicAPI {
                    Section("Address") {
                        TextField("Base URL", text: optional($provider.baseURL), prompt: Text("https://…"))
                    }
                }
                if provider.usesAPIKey || provider.kind == .geminiCLI || provider.kind == .openAICompatible {
                    Section {
                        SecureField("API key", text: $key, prompt: Text(hasStoredKey && !removeKey ? "Saved in the Keychain" : "Paste the key"))
                        TextField("Or environment variable", text: optional($provider.apiKeyEnv), prompt: Text("For example OPENAI_API_KEY"))
                        if hasStoredKey {
                            Toggle("Remove the saved key", isOn: $removeKey)
                        }
                    } header: {
                        Text("API key")
                    } footer: {
                        Text("A saved key is used first; the environment variable is read when there is none, and by the hatch command line.")
                    }
                }
                Section {
                    Picker("Default model", selection: optionalPicker($provider.defaultModel)) {
                        Text("Program default").tag("")
                        ForEach(provider.models) { m in Text(m.isAlias ? (m.name ?? m.id) : m.label).tag(m.id) }
                        if let d = provider.defaultModel, provider.model(d) == nil { Text("\(d) (typed)").tag(d) }
                    }
                    TextField("Or type a model", text: optional($provider.defaultModel), prompt: Text("Model id"))
                } header: {
                    Text("Default model")
                } footer: {
                    Text("Used by a task that picks this provider without a model. The list is fetched from the provider when you save.")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save", action: save)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 600)
        .onAppear { hasStoredKey = HXAgentKeychain.read(provider.id) != nil }
    }

    private func save() {
        var p = provider
        p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.name.isEmpty { p.name = p.kind.displayName }
        p.extraArguments = arguments.split(separator: " ").map(String.init)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let change: KeyChange = !trimmed.isEmpty ? .set(trimmed) : (removeKey ? .remove : .keep)
        onSave(p, change)
        dismiss()
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { provider.executable = url.path }
    }

    /// An optional string as a text field: empty means nil.
    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func optionalPicker(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
