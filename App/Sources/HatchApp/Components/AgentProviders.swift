import Foundation
import Security
import AppKit
import HatchCore
import HatchAgent

/// API keys for agent providers, one Keychain item per provider (service `app.hatch.agents`, account = provider id).
/// The `hatch` CLI reads the same item with `security`. Debug builds keep keys in UserDefaults, as the GitHub token
/// does, because every rebuild has a new signature and the Keychain would ask for the login password each time.
enum HXAgentKeychain {
    static let service = "app.hatch.agents"

    #if DEBUG
    private static func debugKey(_ id: String) -> String { "hatch.debug.agents.\(id)" }
    #endif

    private static func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id]
    }

    static func read(_ id: String) -> String? {
        #if DEBUG
        let stored = UserDefaults.standard.string(forKey: debugKey(id)) ?? ""
        return stored.isEmpty ? nil : stored
        #else
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
        #endif
    }

    @discardableResult
    static func write(_ id: String, _ key: String) -> Bool {
        delete(id)
        #if DEBUG
        UserDefaults.standard.set(key, forKey: debugKey(id))
        return true
        #else
        var q = query(id)
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        #endif
    }

    static func delete(_ id: String) {
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: debugKey(id))
        #else
        SecItemDelete(query(id) as CFDictionary)
        #endif
    }
}

struct HXAgentSecrets: AgentSecrets {
    func storedKey(providerId: String) -> String? { HXAgentKeychain.read(providerId) }
}

extension AppState {
    /// What every model call needs. Text-only work runs in an empty folder of Hatch's own, so no project's
    /// CLAUDE.md or AGENTS.md is read into the prompt.
    nonisolated static func agentContext(paths: AppPaths) -> AgentContext {
        let dir = paths.root.appendingPathComponent("agent-work", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return AgentContext(secrets: HXAgentSecrets(), workingDirectory: dir)
    }

    var agentContext: AgentContext { Self.agentContext(paths: paths) }
}

// MARK: Ask panel

enum HXAskAdapter {
    struct Answer: Sendable {
        var text: String
        var tokensIn: Int
        var tokensOut: Int
        /// The provider's name, which signs the answer in the ticket thread.
        var author: String
        var label: String
        var model: String?
    }

    /// Runs the Ask task with the provider and model chosen in Settings, off the main thread.
    static func ask(prompt: String, store: HatchStore, context: AgentContext) async throws -> Answer {
        try await Task.detached(priority: .userInitiated) { () throws -> Answer in
            let agent = try AgentFactory.resolve(.ask, settings: AgentSettings.load(from: store), context: context)
            let out = try agent.runner.run(prompt: prompt, options: AgentOptions())
            let text = out.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { throw AgentRunnerError.badOutput("\(agent.provider.name) returned an empty answer.") }
            return Answer(text: text, tokensIn: out.tokensIn, tokensOut: out.tokensOut, author: agent.provider.name, label: agent.label, model: agent.model)
        }.value
    }
}


// MARK: The launcher in the app

extension AppState {
    /// Where the `hatch` command is: chosen in Settings, else found on PATH or in the usual install places.
    static let hatchCommandSetting = "hatch_command"

    /// The hatch built into this app (Contents/Helpers), so agents always use the one that matches it.
    nonisolated static var builtInHatch: String? {
        let path = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/hatch").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// Where `hatch` is linked for Terminal: a folder macOS puts on every PATH.
    nonisolated static let pathLink = "/usr/local/bin/hatch"

    /// Whether Terminal finds this app's hatch: the PATH link points at the built-in one.
    nonisolated static var hatchInPath: Bool {
        guard let builtIn = builtInHatch,
              let target = try? FileManager.default.destinationOfSymbolicLink(atPath: pathLink) else { return false }
        return URL(fileURLWithPath: target).standardizedFileURL.path == URL(fileURLWithPath: builtIn).standardizedFileURL.path
    }

    nonisolated static func hatchCommand(store: HatchStore) -> String? {
        if let chosen = (try? store.setting(hatchCommandSetting)) ?? nil, FileManager.default.isExecutableFile(atPath: chosen) { return chosen }
        if let builtIn = builtInHatch { return builtIn }
        if let found = AgentProcess.locate("hatch") { return found }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/hatch", "/usr/local/bin/hatch", "/opt/homebrew/bin/hatch"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Starts the launcher and checks for waiting work every few seconds and after changes.
    func startLauncher() {
        guard launcher == nil, Snapshots.folder == nil, !Snapshots.demoMode else { return }
        let store = store
        let l = AgentLauncher(store: store,
                              configuration: .init(home: paths.root, hatchPath: Self.hatchCommand(store: store), context: agentContext),
                              settings: { AgentSettings.load(from: store, detect: false) },
                              onChange: { [weak self] in Task { @MainActor in self?.agentRunsChanged() } })
        launcher = l
        agentsPaused = l.isPaused
        launchTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickLauncher() }
        }
        tickLauncher()
    }

    /// One look for waiting work, off the main thread (it makes workspaces).
    func tickLauncher() {
        guard let l = launcher else { return }
        // Above the daily pause limit, running agents finish but nothing new starts until tomorrow.
        if checkUsage() == .pause { return }
        l.update(.init(home: paths.root, hatchPath: Self.hatchCommand(store: store), context: agentContext))
        DispatchQueue.global(qos: .utility).async { l.tick() }
    }

    /// Compares today's tokens with the limits and updates `usageLevel`.
    @discardableResult func checkUsage() -> UsageLimits.Level {
        let t = (try? store.tokenTotals(since: Calendar.current.startOfDay(for: Date()))) ?? (input: 0, output: 0)
        let level = UsageLimits.load(from: store).level(today: t.input + t.output)
        if usageLevel != level { usageLevel = level }
        return level
    }

    func agentRunsChanged() {
        let now = launcher?.running ?? []
        let ended = now.count != agentRuns.count
        agentRuns = now
        // A run starting or ending moves a ticket; a step inside a run does not.
        if ended { refresh() }
    }

    func stopAgent(ticketId: Int) { launcher?.stop(ticketId) }

    func setAgentsPaused(_ paused: Bool) {
        perform("Pause agents") { try launcher?.setPaused(paused) ?? store.setSetting(AgentLauncher.pausedSetting, paused ? "1" : "0") }
        agentsPaused = paused
        if !paused { tickLauncher() }
    }

    /// Links /usr/local/bin/hatch to the built-in hatch, so `hatch` works in Terminal. macOS asks for an administrator's
    /// password in its own dialog; Hatch never sees it. Returns why it failed, or nil.
    func installHatchInPath() -> String? {
        guard let builtIn = Self.builtInHatch else { return "This copy of Hatch has no built-in hatch command." }
        let quoted = builtIn.replacingOccurrences(of: "'", with: "'\\''")
        let source = "do shell script \"mkdir -p /usr/local/bin && ln -sf '\(quoted)' \(Self.pathLink)\" with administrator privileges with prompt \"Hatch wants to add the hatch command to Terminal.\""
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // Cancelling the password dialog is not a failure worth a message.
            if (error[NSAppleScript.errorNumber] as? Int) == -128 { return nil }
            return error[NSAppleScript.errorMessage] as? String ?? "macOS did not allow the link."
        }
        tickLauncher()
        return nil
    }

    /// Opens Terminal in an agent's workspace, so the owner can take over.
    func openInTerminal(_ path: String) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}
