import Foundation
import Security
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
    }

    /// Runs the Ask task with the provider and model chosen in Settings, off the main thread.
    static func ask(prompt: String, store: HatchStore, context: AgentContext) async throws -> Answer {
        try await Task.detached(priority: .userInitiated) { () throws -> Answer in
            let agent = try AgentFactory.resolve(.ask, settings: AgentSettings.load(from: store), context: context)
            let out = try agent.runner.run(prompt: prompt, options: AgentOptions())
            let text = out.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { throw AgentRunnerError.badOutput("\(agent.provider.name) returned an empty answer.") }
            return Answer(text: text, tokensIn: out.tokensIn, tokensOut: out.tokensOut, author: agent.provider.name, label: agent.label)
        }.value
    }
}
