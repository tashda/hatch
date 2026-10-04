import SwiftUI
import AppKit
import HatchCore
import HatchAgent

// Settings, Agents (design-review/settings-agents-concepts.html). One grouped Form in three parts: each task with its
// provider and model, how coding agents run, and the providers. Rows are a label and a value; details and actions for
// a provider live in its sheet, and adding one is a sheet in three steps. Providers keep the model list they last
// fetched (refreshed daily and on demand), so a newly released model can be picked as soon as the provider lists it.

struct AgentSettingsPage: View {
    @EnvironmentObject var state: AppState
    @State private var settings: AgentSettings?
    @State private var statuses: [String: ProviderStatus] = [:]
    @State private var refreshing: Set<String> = []
    @State private var testing: Set<String> = []
    @State private var tests: [String: Result<ProbeResult, ProbeFailure>] = [:]
    @State private var details: AgentProvider?
    @State private var taskSheet: AgentRole?
    /// Each task's last check, kept between launches so a task is checked when it changes and once a day.
    @State private var checks: [String: TaskCheck] = [:]
    @State private var adding = false
    @State private var maxAgents = 3
    @State private var loaded = false

    struct ProbeFailure: Error { let message: String }

    /// The useful numbers of agents at once; the recommended one is 3.
    static let agentCounts = [1, 2, 3, 4, 6, 8]

    var body: some View {
        Form {
            if let settings {
                tasksSection(settings)
                codingSection(settings)
                providersSection(settings)
            } else {
                Section { ProgressView("Loading providers…") }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear(perform: load)
        .sheet(item: $details) { provider in
            ProviderDetailsSheet(provider: provider, status: statuses[provider.id], usedBy: usage(of: provider.id),
                                 refreshing: refreshing.contains(provider.id), testing: testing.contains(provider.id),
                                 test: tests[provider.id],
                                 onTest: { testProvider($0) }, onRefresh: { refreshModels($0) },
                                 onSave: { saved, key in save(saved, key: key) }, onRemove: { remove($0) })
        }
        .sheet(item: $taskSheet) { role in
            TaskSheet(role: role, settings: settings ?? AgentSettings(), check: checks[role.rawValue],
                      checking: testing.contains("role-\(role.rawValue)"),
                      onChange: { own in update { $0.setChoice(own, for: role) } }, onTest: { testRole(role) })
        }
        .sheet(isPresented: $adding) {
            AddProviderSheet(settings: settings ?? AgentSettings(), context: state.agentContext) { provider, key, uses in
                add(provider, key: key, uses: uses)
            }
        }
    }

    // MARK: Sections

    /// The default every task uses, then one line per task: what it uses and whether it works.
    private func tasksSection(_ settings: AgentSettings) -> some View {
        Section {
            ChoiceRows(settings: settings, choice: settings.defaultChoice, recommendedModel: nil, providerLabel: "Default provider",
                       modelLabel: "Default model") { c in update { $0.defaultChoice = c } }
            ForEach(AgentRole.allCases) { role in
                TaskListRow(role: role, settings: settings, check: checks[role.rawValue],
                            checking: testing.contains("role-\(role.rawValue)")) { taskSheet = role }
            }
        } header: {
            Text("Tasks")
        } footer: {
            Text("Each task uses the default unless you choose otherwise. Open a task to check that it works.")
        }
    }

    private func codingSection(_ settings: AgentSettings) -> some View {
        let programs = settings.providers.filter { $0.kind.isProgram }
        return Section {
            Picker("Run agents with", selection: Binding(
                get: { settings.codingProviderId ?? programs.first { $0.id == AgentSettings.claudeProviderId }?.id ?? programs.first?.id ?? "" },
                set: { id in update { $0.codingProviderId = id } })) {
                ForEach(programs) { p in
                    Text(p.enabled ? p.name : "\(p.name) (off)").tag(p.id)
                }
                if programs.isEmpty { Text("No program connected").tag("") }
            }
            Picker("Agents at once", selection: $maxAgents) {
                ForEach(Self.agentCounts, id: \.self) { n in
                    Text(n == 3 ? "3 · Recommended" : "\(n)").tag(n)
                }
                if !Self.agentCounts.contains(maxAgents) { Text("\(maxAgents)").tag(maxAgents) }
            }
            .onChange(of: maxAgents) { _, newValue in
                if loaded { state.hxSaveSetting("max_agents", String(newValue)) }
            }
        } header: {
            Text("Coding agents")
        } footer: {
            Text("Each agent works on one ticket in its own copy of the code. More at once finishes sooner and uses your plan faster.")
        }
    }

    private func providersSection(_ settings: AgentSettings) -> some View {
        Section {
            ForEach(settings.providers) { provider in
                ProviderListRow(provider: provider, status: statuses[provider.id], usedBy: usage(of: provider.id),
                                onToggle: { on in setEnabled(provider, on) }, onDetails: { details = provider })
            }
        } header: {
            Text("Providers")
        } footer: {
            HStack(alignment: .top) {
                Text("A program uses the plan it is signed in with. An API key is billed per token; keys are kept in the Keychain.")
                Spacer(minLength: 16)
                Button("Add Provider…") { adding = true }
            }
        }
    }

    /// What uses a provider, in plain words: its tasks and coding agents.
    private func usage(of providerId: String) -> [String] {
        guard let settings else { return [] }
        var out = settings.roles(using: providerId).map(\.taskTitle)
        let coding = settings.codingProviderId ?? AgentSettings.claudeProviderId
        if coding == providerId { out.append("Coding agents") }
        return out
    }

    // MARK: Loading and saving

    private func load() {
        guard !loaded else { return }
        if let s = state.hxSetting("max_agents"), let n = Int(s) { maxAgents = n }
        else { maxAgents = (try? state.store.maxAgents(projectId: state.projectFilterId)) ?? 3 }
        loaded = true
        let store = state.store
        let demo = Snapshots.demoMode
        checks = TaskCheck.load(from: store)
        Task {
            var first = await Task.detached { AgentSettings.load(from: store, detect: !demo) }.value
            let moved = first.upgradeModels()
            settings = first
            guard !demo else { return }
            // First run: save the detected setup, so the CLI and Iris see the same providers as this page.
            if (try? store.setting(AgentSettings.settingKey)) == nil || !moved.isEmpty { persist(first) }
            checkAll()
            for p in first.providers where p.enabled && ModelCatalog.isStale(p) { refreshModels(p.id) }
        }
    }

    /// Applies a change and saves it. A task whose provider or model changed loses its last check, which no longer
    /// says anything about it; checks run only when the owner asks.
    private func update(_ change: (inout AgentSettings) -> Void) {
        guard var s = settings else { return }
        let before = settings
        change(&s)
        settings = s
        persist(s)
        let stale = AgentRole.allCases.filter { s.choice($0) != before?.choice($0) && checks[$0.rawValue] != nil }
        guard !stale.isEmpty, !Snapshots.demoMode else { return }
        for role in stale { checks[role.rawValue] = nil }
        TaskCheck.save(checks, to: state.store)
    }

    private func persist(_ s: AgentSettings) {
        guard !Snapshots.demoMode else { return }
        state.perform("Save agent settings") { try s.save(to: state.store) }
    }

    private func storeKey(_ id: String, _ key: KeyChange) {
        switch key {
        case .keep: break
        case .set(let k): HXAgentKeychain.write(id, k)
        case .remove: HXAgentKeychain.delete(id)
        }
    }

    private func save(_ provider: AgentProvider, key: KeyChange) {
        storeKey(provider.id, key)
        update { $0.update(provider) }
        check(provider.id)
        if provider.models.isEmpty { refreshModels(provider.id) }
    }

    /// A new provider, put to work for the tasks the owner chose in the last step of Add Provider.
    private func add(_ provider: AgentProvider, key: KeyChange, uses: Set<String>) {
        storeKey(provider.id, key)
        update { s in
            s.update(provider)
            for role in AgentRole.allCases where uses.contains(role.rawValue) { s.setChoice(RoleChoice(providerId: provider.id), for: role) }
            if uses.contains("coding") { s.codingProviderId = provider.id }
        }
        check(provider.id)
        refreshModels(provider.id)
    }

    private func remove(_ provider: AgentProvider) {
        HXAgentKeychain.delete(provider.id)
        update { s in
            s.remove(provider.id)
            if s.codingProviderId == provider.id { s.codingProviderId = nil }
        }
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
                s.upgradeModels()
            }
        }
    }

    private func testProvider(_ provider: AgentProvider) {
        let context = state.agentContext
        runTest(key: provider.id) { try ProviderCheck.test(provider, model: nil, context: context) }
    }

    private func testRole(_ role: AgentRole) {
        guard let settings, !Snapshots.demoMode else { return }
        let context = state.agentContext, key = "role-\(role.rawValue)"
        guard !testing.contains(key) else { return }
        testing.insert(key)
        Task {
            let check = await Task.detached { () -> TaskCheck in
                do {
                    let agent = try AgentFactory.resolve(role, settings: settings, context: context)
                    let r = try ProviderCheck.test(agent.provider, model: agent.model, effort: agent.effort, thinking: agent.thinking, context: context)
                    return TaskCheck(ok: true, seconds: r.seconds, message: nil, model: r.model, at: Date())
                } catch {
                    return TaskCheck(ok: false, seconds: nil, message: "\(error)", model: nil, at: Date())
                }
            }.value
            testing.remove(key)
            checks[role.rawValue] = check
            TaskCheck.save(checks, to: state.store)
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

/// A test result as one line for a row's value: how long it took, or why it failed.
private func testLine(_ result: Result<ProbeResult, AgentSettingsPage.ProbeFailure>?) -> (text: String, failed: Bool, help: String)? {
    switch result {
    case .success(let r)?:
        return ("Answered in \(String(format: "%.1f", r.seconds)) s", false,
                "\"\(r.text.prefix(60))\" · \(hxTokens(r.tokensIn)) in, \(hxTokens(r.tokensOut)) out\(r.model.map { " · \($0)" } ?? "")")
    case .failure(let f)?:
        return ("Failed", true, f.message)
    case nil:
        return nil
    }
}

// MARK: Tasks

/// A task's last check: whether its provider and model answered, how fast, or why not.
struct TaskCheck: Codable, Equatable {
    var ok: Bool
    var seconds: Double?
    var message: String?
    var model: String?
    var at: Date

    static let settingKey = "agent_task_checks"

    static func load(from store: HatchStore) -> [String: TaskCheck] {
        guard let raw = try? store.setting(settingKey) else { return [:] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (try? d.decode([String: TaskCheck].self, from: Data(raw.utf8))) ?? [:]
    }

    static func save(_ checks: [String: TaskCheck], to store: HatchStore) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(checks) else { return }
        try? store.setSetting(settingKey, String(decoding: data, as: UTF8.self))
    }

    /// The status line: how long it took, or the first line of why it failed.
    var line: String {
        ok ? "answered in \(String(format: "%.1f", seconds ?? 0)) s"
           : (message?.split(separator: "\n").first.map(String.init) ?? "Failed")
    }
}

/// The name a model is shown by: its listed name, or its id when the list does not have it.
private func modelName(_ id: String?, in provider: AgentProvider?) -> String {
    guard let id else { return provider?.defaultModel.flatMap { provider?.model($0)?.name ?? $0 } ?? "Default" }
    return provider?.model(id)?.name ?? id
}

/// Provider, model, and the effort or thinking switch when the model takes one. Used for the default and in a task's sheet.
private struct ChoiceRows: View {
    let settings: AgentSettings
    let choice: RoleChoice?
    let recommendedModel: String?
    var providerLabel = "Provider"
    var modelLabel = "Model"
    let onChange: (RoleChoice) -> Void

    @State private var customModel = ""
    @State private var askingCustom = false

    private var provider: AgentProvider? { choice.flatMap { settings.provider($0.providerId) } }
    private var selectedModel: ModelInfo? { provider?.model(choice?.model ?? provider?.defaultModel) }

    var body: some View {
        Picker(providerLabel, selection: Binding(get: { choice?.providerId ?? "" }, set: { id in
            if !id.isEmpty { onChange(RoleChoice(providerId: id)) }
        })) {
            if choice == nil { Text("Choose…").tag("") }
            ForEach(settings.providers.filter { $0.enabled || $0.id == choice?.providerId }) { p in
                Text(p.enabled ? p.name : "\(p.name) (off)").tag(p.id)
            }
        }
        if let provider {
            Picker(modelLabel, selection: modelBinding) {
                Text(provider.defaultModel.map { "Default (\(modelName($0, in: provider)))" } ?? "Default").tag("")
                // Real versions only; tasks move to newer ones on their own (the provider's switch).
                let listed = provider.models.filter { !$0.isAlias }
                ForEach(listed.filter(\.featured)) { m in Text(title(m, provider)).tag(m.id) }
                let older = listed.filter { !$0.featured }
                if !older.isEmpty {
                    Section("Older models") { ForEach(older) { m in Text(title(m, provider)).tag(m.id) } }
                }
                if let current = choice?.model, provider.model(current) == nil || provider.model(current)?.isAlias == true {
                    Text(current).tag(current)
                }
                Divider()
                Text("Other Model…").tag(Self.otherTag)
            }
            .alert("Other model", isPresented: $askingCustom) {
                TextField("Model id", text: $customModel)
                Button("Use") {
                    let name = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { set(model: name) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Type the model id exactly as \(provider.name) expects it.")
            }
            if let efforts = selectedModel?.efforts, !efforts.isEmpty {
                Picker("Effort", selection: Binding(get: { choice?.effort ?? "" }, set: { e in
                    guard var c = choice else { return }
                    c.effort = e.isEmpty ? nil : e
                    onChange(c)
                })) {
                    Text(selectedModel?.defaultEffort.map { "Default (\($0.capitalized))" } ?? "Default").tag("")
                    ForEach(efforts, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            if provider.kind == .claudeCode, let m = selectedModel, m.efforts.isEmpty {
                Toggle("Thinking", isOn: Binding(get: { choice?.thinking ?? true }, set: { on in
                    guard var c = choice else { return }
                    c.thinking = on ? nil : false
                    onChange(c)
                }))
                .help("Off sends MAX_THINKING_TOKENS=0 to Claude Code: faster and far fewer tokens for short, structured work")
            }
        }
    }

    static let otherTag = "\u{0}other"

    private func title(_ m: ModelInfo, _ provider: AgentProvider) -> String {
        let name = m.name ?? m.id
        guard provider.kind == .claudeCode, let r = recommendedModel, AgentSettings.family(of: m.id) == r,
              provider.models.first(where: { !$0.isAlias && $0.featured && AgentSettings.family(of: $0.id) == r })?.id == m.id
        else { return name }
        return "\(name) · Recommended"
    }

    private var modelBinding: Binding<String> {
        Binding(get: { choice?.model ?? "" }, set: { id in
            if id == Self.otherTag { customModel = choice?.model ?? ""; askingCustom = true; return }
            set(model: id.isEmpty ? nil : id)
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

/// One task in the list: its name, then what it uses and whether it works. Opens the task's sheet.
private struct TaskListRow: View {
    let role: AgentRole
    let settings: AgentSettings
    let check: TaskCheck?
    let checking: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.taskTitle).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Circle().fill(dotColor).frame(width: 7, height: 7)
                        Text(statusLine).font(.callout).foregroundStyle(check?.ok == false && !checking ? Theme.critical : .secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the settings for \(role.taskTitle)")
    }

    private var uses: String {
        let own = settings.ownChoice(role)
        if own?.isOff == true { return "Off" }
        guard let own else { return "Same as default" }
        let provider = settings.provider(own.providerId)
        var text = modelName(own.model, in: provider)
        if own.thinking == false { text += ", thinking off" }
        if own.providerId != settings.defaultChoice?.providerId { text += " · \(provider?.name ?? "missing provider")" }
        return text
    }

    private var statusLine: String {
        if settings.choice(role) == nil { return uses == "Off" ? "Off: it does not run" : "No provider chosen" }
        if checking { return "\(uses) · checking…" }
        guard let check else { return "\(uses) · not checked yet" }
        return "\(uses) · \(check.line)"
    }

    private var dotColor: Color {
        if settings.choice(role) == nil || checking || check == nil { return .secondary.opacity(0.5) }
        return check!.ok ? Theme.finished : Theme.critical
    }
}

/// A task's own settings: the default, its own provider and model, or off; its last check and Test Again.
private struct TaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let role: AgentRole
    let settings: AgentSettings
    let check: TaskCheck?
    let checking: Bool
    let onChange: (RoleChoice?) -> Void
    let onTest: () -> Void

    private enum Mode: String { case useDefault, own, off }

    private var mode: Mode {
        guard let own = settings.ownChoice(role) else { return .useDefault }
        return own.isOff ? .off : .own
    }

    private var defaultTitle: String {
        guard let d = settings.defaultChoice, let p = settings.provider(d.providerId) else { return "The default" }
        return "The default (\(modelName(d.model, in: p)) · \(p.name))"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(role.taskTitle).font(.title3.weight(.semibold))
                Text(role.detail).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 20)
            Form {
                Section {
                    Picker("Use", selection: Binding(get: { mode }, set: { m in
                        switch m {
                        case .useDefault: onChange(nil)
                        case .off: onChange(.off)
                        case .own: onChange(settings.choice(role) ?? settings.defaultChoice ?? settings.providers.first.map { RoleChoice(providerId: $0.id) })
                        }
                    })) {
                        Text(defaultTitle).tag(Mode.useDefault)
                        Text("Its own provider and model").tag(Mode.own)
                        Text("Off").tag(Mode.off)
                    }
                    if mode == .own {
                        ChoiceRows(settings: settings, choice: settings.ownChoice(role), recommendedModel: role.recommendedModel) { onChange($0) }
                    }
                } footer: {
                    Text(role.recommendation)
                }
                if mode != .off {
                    Section {
                        LabeledContent("Last check") {
                            if checking { Text("Checking…").foregroundStyle(.secondary) }
                            else if let check {
                                Text(check.ok ? "Answered in \(String(format: "%.1f", check.seconds ?? 0)) s, \(check.at.formatted(.relative(presentation: .named)))" : "Failed")
                                    .foregroundStyle(check.ok ? Color.secondary : Theme.critical)
                            } else { Text("Not checked yet").foregroundStyle(.secondary) }
                        }
                        if let check, !check.ok, let message = check.message {
                            Text(message).font(.callout).foregroundStyle(Theme.critical).textSelection(.enabled)
                        }
                    } header: {
                        Text("Status")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            HStack {
                Spacer()
                Button(checking ? "Checking…" : "Check", action: onTest)
                    .disabled(checking || mode == .off)
                    .help("Send one short prompt with this task's provider and model")
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 520, height: 480)
    }
}

// MARK: Provider row

/// A provider in the list: what it is, its status and what uses it, its switch, and the i button for its sheet.
private struct ProviderListRow: View {
    let provider: AgentProvider
    let status: ProviderStatus?
    let usedBy: [String]
    let onToggle: (Bool) -> Void
    let onDetails: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProviderTile(way: provider.way)
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.name)
                Text(subtitle).font(.callout)
                    .foregroundStyle(status?.ready == false ? Theme.critical : .secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            Toggle(provider.name, isOn: Binding(get: { provider.enabled }, set: onToggle))
                .toggleStyle(.switch).labelsHidden()
            Button(action: onDetails) { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .help("Details for \(provider.name)")
                .accessibilityLabel("Details for \(provider.name)")
        }
    }

    private var subtitle: String {
        let first = status.map { $0.summary.trimmingCharacters(in: CharacterSet(charactersIn: ".")) } ?? provider.billing.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return first + " · " + (usedBy.isEmpty ? "Not used" : "Used by " + usedBy.joined(separator: ", ").lowercased().capitalizedFirst)
    }
}

private struct ProviderTile: View {
    let way: ProviderWay
    var body: some View {
        Image(systemName: way.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    private var tint: Color {
        switch way {
        case .program: .indigo
        case .api: .blue
        case .server: .green
        }
    }
}

// MARK: Details sheet

/// Everything about one provider: status and test, models, how it connects, and Remove. Changes apply on Done.
private struct ProviderDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var provider: AgentProvider
    let status: ProviderStatus?
    let usedBy: [String]
    let refreshing: Bool
    let testing: Bool
    let test: Result<ProbeResult, AgentSettingsPage.ProbeFailure>?
    let onTest: (AgentProvider) -> Void
    let onRefresh: (String) -> Void
    let onSave: (AgentProvider, KeyChange) -> Void
    let onRemove: (AgentProvider) -> Void

    @State private var key = ""
    @State private var removeKey = false
    @State private var hasStoredKey = false
    @State private var arguments = ""
    @State private var confirmRemove = false

    init(provider: AgentProvider, status: ProviderStatus?, usedBy: [String], refreshing: Bool, testing: Bool,
         test: Result<ProbeResult, AgentSettingsPage.ProbeFailure>?, onTest: @escaping (AgentProvider) -> Void,
         onRefresh: @escaping (String) -> Void, onSave: @escaping (AgentProvider, KeyChange) -> Void,
         onRemove: @escaping (AgentProvider) -> Void) {
        _provider = State(initialValue: provider)
        self.status = status; self.usedBy = usedBy; self.refreshing = refreshing; self.testing = testing; self.test = test
        self.onTest = onTest; self.onRefresh = onRefresh; self.onSave = onSave; self.onRemove = onRemove
        _arguments = State(initialValue: provider.extraArguments.joined(separator: " "))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ProviderTile(way: provider.way)
                Text(provider.name).font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 20)
            Form {
                Section {
                    Toggle("On", isOn: $provider.enabled)
                    LabeledContent("Connection") {
                        Text(status?.summary.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? "Not checked yet")
                            .foregroundStyle(status?.ready == false ? Theme.critical : .secondary)
                    }
                    LabeledContent("Used by", value: usedBy.isEmpty ? "Nothing yet" : usedBy.joined(separator: ", "))
                    LabeledContent("Last check") {
                        if testing { Text("Checking…").foregroundStyle(.secondary) }
                        else if let line = testLine(test) {
                            Text(line.text).foregroundStyle(line.failed ? Theme.critical : .secondary).help(line.help)
                        } else { Text("Not checked yet").foregroundStyle(.secondary) }
                    }
                } header: {
                    Text("Status")
                }
                Section {
                    Picker("Default model", selection: Binding(get: { provider.defaultModel ?? "" },
                                                                set: { provider.defaultModel = $0.isEmpty ? nil : $0 })) {
                        Text(provider.kind.isProgram ? "The program's default" : "None").tag("")
                        ForEach(provider.models.filter { !$0.isAlias }) { m in Text(m.name ?? m.id).tag(m.id) }
                        if let d = provider.defaultModel, provider.model(d) == nil || provider.model(d)?.isAlias == true { Text(d).tag(d) }
                    }
                    LabeledContent("Available") {
                        Text(modelsLine).foregroundStyle(provider.modelsError == nil ? Color.secondary : Theme.critical)
                    }
                    Toggle("Move tasks to new versions", isOn: Binding(get: { provider.movesToNewVersions },
                                                                      set: { provider.autoUpgrade = $0 ? nil : false }))
                } header: {
                    HStack {
                        Text("Models")
                        Spacer()
                        Button(refreshing ? "Refreshing…" : "Refresh") { onRefresh(provider.id) }.buttonStyle(.link).disabled(refreshing)
                    }
                } footer: {
                    Text("When the list shows a newer version of a model a task uses, the task moves to it.")
                }
                connectionSection
                Section("Advanced") {
                    TextField("Name", text: $provider.name)
                    if let program = provider.kind.program {
                        LabeledContent("Program") {
                            HStack(spacing: 8) {
                                Text(provider.executable ?? "Found automatically (\(program))").foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Button("Choose…", action: chooseProgram)
                            }
                        }
                        TextField("Extra arguments", text: $arguments, prompt: Text("None"))
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            HStack {
                Button("Remove Provider…", role: .destructive) { confirmRemove = true }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(testing ? "Checking…" : "Check") { onTest(provider) }.disabled(testing)
                    .help("Send one short prompt with the provider's default model")
                Button("Done", action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 560, height: 640)
        .onAppear { hasStoredKey = HXAgentKeychain.read(provider.id) != nil }
        .confirmationDialog("Remove \(provider.name)?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { onRemove(provider); dismiss() }
        } message: {
            Text(usedBy.isEmpty ? "Its saved API key is deleted too." : "\(usedBy.joined(separator: " and ")) will need another provider. Its saved API key is deleted too.")
        }
    }

    /// How this provider connects, in the words of its way: a program's sign-in, a service's key, a server's address.
    @ViewBuilder private var connectionSection: some View {
        switch provider.way {
        case .program where provider.kind == .claudeCode:
            Section {
                Picker("Sign in with", selection: claudeSignInBinding) {
                    Text("Its own sign-in").tag("")
                    Section("An Anthropic-compatible service") {
                        ForEach(ModelService.anthropicCompatible) { s in Text(s.name).tag(s.id) }
                    }
                    if provider.signIn == .endpoint, provider.serviceId == nil { Text("Custom address").tag("custom") }
                }
                if provider.signIn == .endpoint, provider.serviceId == nil {
                    TextField("Address", text: optional($provider.baseURL), prompt: Text("https://…"))
                }
                if provider.usesAPIKey { keyRows }
            } header: {
                Text("Connection")
            } footer: {
                Text(provider.signIn == .account ? "Uses the plan Claude Code is signed in with; an Anthropic key in the environment is ignored." : provider.billing)
            }
        case .program:
            Section("Connection") {
                LabeledContent("Sign-in", value: "Set up in the program itself")
            }
        case .api:
            Section {
                LabeledContent("Service", value: ModelService.service(provider.serviceId)?.name ?? "Custom")
                if ModelService.service(provider.serviceId) == nil {
                    TextField("Address", text: optional($provider.baseURL), prompt: Text("https://…"))
                }
                keyRows
            } header: {
                Text("Connection")
            } footer: {
                keyFooter
            }
        case .server:
            Section("Connection") {
                TextField("Address", text: optional($provider.baseURL), prompt: Text("http://localhost:11434/v1"))
            }
        }
    }

    @ViewBuilder private var keyRows: some View {
        SecureField("API key", text: $key, prompt: Text(hasStoredKey && !removeKey ? "Saved in the Keychain" : "Paste the key"))
        TextField("Or environment variable", text: optional($provider.apiKeyEnv), prompt: Text("None"))
        if hasStoredKey { Toggle("Remove the saved key", isOn: $removeKey) }
    }

    @ViewBuilder private var keyFooter: some View {
        if let page = ModelService.service(provider.serviceId)?.keyPage, let url = URL(string: page) {
            Text("A saved key is used first, then the environment variable. [Create a key](\(url.absoluteString))")
        } else {
            Text("A saved key is used first, then the environment variable.")
        }
    }

    private var claudeSignInBinding: Binding<String> {
        Binding(get: {
            switch provider.signIn ?? .account {
            case .account: return ""
            case .apiKey: return "anthropic"
            case .endpoint: return provider.serviceId ?? "custom"
            }
        }, set: { id in
            if id.isEmpty { provider.signIn = .account; provider.serviceId = nil; provider.baseURL = nil; return }
            guard let s = ModelService.service(id) else { return }
            let target = AgentProvider.claudeCode(through: s)
            provider.signIn = target.signIn; provider.baseURL = target.baseURL; provider.serviceId = s.id
            provider.apiKeyEnv = provider.apiKeyEnv ?? s.keyEnv
        })
    }

    private var modelsLine: String {
        if let e = provider.modelsError { return e }
        guard let at = provider.modelsFetchedAt else { return refreshing ? "Fetching…" : "Not fetched yet" }
        let count = provider.models.filter { !$0.isAlias }.count
        return "\(count), updated \(at.formatted(.relative(presentation: .named)))"
    }

    private func save() {
        var p = provider
        p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.name.isEmpty { p.name = p.kind.displayName }
        p.extraArguments = arguments.split(separator: " ").map(String.init)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(p, !trimmed.isEmpty ? .set(trimmed) : (removeKey ? .remove : .keep))
        dismiss()
    }

    private func chooseProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { provider.executable = url.path }
    }
}

/// An optional string as a text field: empty means nil.
private func optional(_ binding: Binding<String?>) -> Binding<String> {
    Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
}

// MARK: Add Provider

/// Adding a provider in three steps: how Hatch reaches the model, which one (found ones first), then connect and put
/// it to work. Replaces the long menu of ready-made setups.
private struct AddProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let settings: AgentSettings
    let context: AgentContext
    let onAdd: (AgentProvider, KeyChange, Set<String>) -> Void

    enum Step { case way, which, connect }
    @State private var step = Step.way
    @State private var way = ProviderWay.program

    // Which
    @State private var programKind = ProviderKind.claudeCode
    @State private var located: [ProviderKind: String] = [:]
    @State private var serviceId: String? = "anthropic"
    @State private var search = ""
    @State private var servers: [(server: LocalServer, models: Int)] = []
    @State private var findingServers = false
    @State private var serverChoice: String? = nil

    // Connect
    @State private var draft = AgentProvider.program(.claudeCode)
    @State private var claudeService = ""
    @State private var key = ""
    @State private var status: ProviderStatus?
    @State private var uses: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                switch step {
                case .way: waySection
                case .which: whichSections
                case .connect: connectSections
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            HStack {
                if step != .way { Button("Back", action: back) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(step == .connect ? "Add" : "Continue", action: next)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 560, height: 560)
        .task { await locatePrograms() }
    }

    // Step 1

    private var waySection: some View {
        Section {
            ForEach(ProviderWay.allCases) { w in
                ChoiceRow(selected: way == w, title: w.title, detail: w.detail, symbol: w.symbol) { way = w }
            }
        } header: {
            Text("How should Hatch reach the model?")
        }
    }

    // Step 2

    @ViewBuilder private var whichSections: some View {
        switch way {
        case .program:
            let kinds = ProviderKind.allCases.filter(\.isProgram)
            let found = kinds.filter { located[$0] != nil }, missing = kinds.filter { located[$0] == nil }
            if !found.isEmpty {
                Section("Found on this Mac") {
                    ForEach(found, id: \.self) { k in
                        ChoiceRow(selected: programKind == k, title: k.displayName, detail: located[k] ?? "", symbol: "terminal") { programKind = k }
                    }
                }
            }
            if !missing.isEmpty {
                Section {
                    ForEach(missing, id: \.self) { k in
                        ChoiceRow(selected: programKind == k, title: k.displayName, detail: "Not installed, or not on the usual paths", symbol: "terminal") { programKind = k }
                    }
                } header: {
                    Text("Not found")
                } footer: {
                    Text("Install the program and sign in to it first, or choose its path in the provider's details later.")
                }
            }
        case .api:
            Section {
                TextField("Search", text: $search, prompt: Text("Search services"))
                ForEach(ModelService.all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { s in
                    ChoiceRow(selected: serviceId == s.id, title: s.name, detail: s.id == "anthropic" ? "Anthropic's own API" : "OpenAI-compatible API",
                              symbol: "network") { serviceId = s.id }
                }
                ChoiceRow(selected: serviceId == nil, title: "Another service", detail: "Any OpenAI-compatible API, by its address", symbol: "ellipsis.circle") { serviceId = nil }
            } header: {
                Text("Which service?")
            }
        case .server:
            Section {
                if findingServers { ProgressView("Looking for servers…").controlSize(.small) }
                ForEach(servers, id: \.server.id) { s in
                    ChoiceRow(selected: serverChoice == s.server.id, title: s.server.name,
                              detail: "Running · \(s.models) model\(s.models == 1 ? "" : "s")", symbol: "server.rack") { serverChoice = s.server.id }
                }
                if !findingServers && servers.isEmpty {
                    Text("No server answered on the usual ports (Ollama, LM Studio, llama.cpp).").foregroundStyle(.secondary)
                }
                ChoiceRow(selected: serverChoice == nil, title: "Another address", detail: "A server on this Mac or the network", symbol: "ellipsis.circle") { serverChoice = nil }
            } header: {
                Text("Which server?")
            }
            .task { await findServers() }
        }
    }

    // Step 3

    @ViewBuilder private var connectSections: some View {
        switch way {
        case .program where draft.kind == .claudeCode:
            Section {
                Picker("Sign in with", selection: $claudeService) {
                    Text("Its own sign-in").tag("")
                    Section("An Anthropic-compatible service") {
                        ForEach(ModelService.anthropicCompatible) { s in Text(s.name).tag(s.id) }
                    }
                }
                .onChange(of: claudeService) { _, id in
                    draft = ModelService.service(id).map(AgentProvider.claudeCode(through:)) ?? .program(.claudeCode)
                }
                if !claudeService.isEmpty { SecureField("API key", text: $key, prompt: Text("Paste the key, or set \(draft.apiKeyEnv ?? "its variable")")) }
                statusRow
            } header: {
                Text("Connection")
            } footer: {
                Text(claudeService.isEmpty ? "Uses the plan Claude Code is signed in with." : "Claude Code talks to \(ModelService.service(claudeService)?.name ?? "the service") instead of Anthropic; it bills you.")
            }
        case .program:
            Section("Connection") { statusRow }
        case .api:
            Section {
                if serviceId == nil {
                    TextField("Name", text: $draft.name)
                    TextField("Address", text: optional($draft.baseURL), prompt: Text("https://…/v1"))
                }
                SecureField("API key", text: $key, prompt: Text("Paste the key, or set \(draft.apiKeyEnv ?? "an environment variable")"))
            } header: {
                Text("Connection")
            } footer: {
                if let page = ModelService.service(serviceId)?.keyPage { Text("The key is kept in the Keychain. [Create a key](\(page))") }
                else { Text("The key is kept in the Keychain.") }
            }
        case .server:
            Section("Connection") {
                TextField("Name", text: $draft.name)
                TextField("Address", text: optional($draft.baseURL), prompt: Text("http://localhost:11434/v1"))
            }
        }
        Section {
            ForEach(AgentRole.allCases) { role in
                Toggle(role.taskTitle, isOn: binding(role.rawValue))
            }
            if draft.kind.isProgram { Toggle("Coding agents", isOn: binding("coding")) }
        } header: {
            Text("Use it for")
        } footer: {
            Text("You can change this later, per task.")
        }
    }

    private var statusRow: some View {
        LabeledContent("Status") {
            if let status {
                Label(status.summary, systemImage: status.ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(status.ready ? Theme.finished : Theme.critical)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: draft.signIn?.rawValue ?? draft.kind.rawValue) { await checkStatus() }
    }

    private func binding(_ use: String) -> Binding<Bool> {
        Binding(get: { uses.contains(use) }, set: { on in if on { uses.insert(use) } else { uses.remove(use) } })
    }

    // Flow

    private var canContinue: Bool {
        switch step {
        case .way: return true
        case .which: return way != .server || serverChoice != nil || !findingServers
        case .connect:
            switch way {
            case .program: return true
            case .api: return serviceId != nil || !(draft.baseURL ?? "").isEmpty
            case .server: return !(draft.baseURL ?? "").isEmpty
            }
        }
    }

    private func next() {
        switch step {
        case .way: step = .which
        case .which: prepareDraft(); step = .connect
        case .connect: finish()
        }
    }

    private func back() {
        switch step {
        case .way: break
        case .which: step = .way
        case .connect: step = .which; status = nil
        }
    }

    /// The provider the last step edits, made from the choices so far. Tasks without a provider get it by default.
    private func prepareDraft() {
        switch way {
        case .program:
            draft = .program(programKind)
            claudeService = ""
        case .api:
            draft = ModelService.service(serviceId).map(AgentProvider.api) ?? AgentProvider(name: "Custom service", kind: .openAICompatible, baseURL: "")
        case .server:
            let s = servers.first { $0.server.id == serverChoice }?.server
            draft = .server(name: s?.name ?? "Server", baseURL: s?.baseURL ?? "")
        }
        key = ""
        status = nil
        uses = Set(AgentRole.allCases.filter { settings.choice($0) == nil }.map(\.rawValue))
        if draft.kind.isProgram && settings.codingProviderId == nil && !settings.providers.contains(where: { $0.kind.isProgram && $0.enabled }) {
            uses.insert("coding")
        }
    }

    private func finish() {
        var p = draft
        p.id = UUID().uuidString.lowercased()
        // A second provider of the same name gets the service or address in its name, so the two are told apart.
        if settings.providers.contains(where: { $0.name == p.name }) { p.name += " (\(settings.providers.filter { $0.name.hasPrefix(p.name) }.count + 1))" }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        onAdd(p, trimmed.isEmpty ? .keep : .set(trimmed), uses)
        dismiss()
    }

    private func locatePrograms() async {
        let found = await Task.detached { () -> [ProviderKind: String] in
            var out: [ProviderKind: String] = [:]
            for k in ProviderKind.allCases { if let program = k.program, let path = AgentProcess.locate(program) { out[k] = path } }
            return out
        }.value
        located = found
        if let first = ProviderKind.allCases.first(where: { found[$0] != nil }), found[programKind] == nil { programKind = first }
    }

    private func findServers() async {
        guard servers.isEmpty, !findingServers else { return }
        findingServers = true
        let found = await Task.detached { LocalServer.detect() }.value
        servers = found
        serverChoice = found.first?.server.id
        findingServers = false
    }

    private func checkStatus() async {
        status = nil
        let p = draft, context = context
        status = await Task.detached { ProviderCheck.status(p, context: context) }.value
    }
}

/// A choice in a list, drawn as a native row: an icon, a title with one line under it, and a checkmark when chosen.
private struct ChoiceRow: View {
    let selected: Bool
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary)
                    if !detail.isEmpty { Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
