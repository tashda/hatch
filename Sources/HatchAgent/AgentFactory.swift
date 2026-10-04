import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where API keys come from. The app reads the Keychain; the CLI reads environment variables.
public protocol AgentSecrets: Sendable {
    /// The key stored for this provider (the Keychain in the app), or nil.
    func storedKey(providerId: String) -> String?
}

public extension AgentSecrets {
    /// The stored key, else the provider's environment variable.
    func apiKey(for p: AgentProvider) -> String? {
        if let k = storedKey(providerId: p.id)?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty { return k }
        if let name = p.apiKeyEnv, !name.isEmpty, let k = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty { return k }
        return nil
    }
}

/// Keys from environment variables only.
public struct EnvironmentSecrets: AgentSecrets {
    public init() {}
    public func storedKey(providerId: String) -> String? { nil }
}

/// What every run needs besides the choice itself.
public struct AgentContext: Sendable {
    public var secrets: AgentSecrets
    /// Where programs run. Text-only work runs in an empty folder so no project's CLAUDE.md or AGENTS.md is loaded.
    public var workingDirectory: URL?
    public var transport: HTTPTransport

    public init(secrets: AgentSecrets = EnvironmentSecrets(), workingDirectory: URL? = nil, transport: HTTPTransport = URLSessionTransport()) {
        self.secrets = secrets; self.workingDirectory = workingDirectory; self.transport = transport
    }
}

/// A task's choice turned into something that can run.
public struct ResolvedAgent: Sendable {
    public var role: AgentRole?
    public var provider: AgentProvider
    public var model: String?
    public var effort: String?
    public var thinking: Bool?
    public var runner: AgentRunner

    /// "Claude Code · haiku", for thread notes and the Agents screen.
    public var label: String {
        var parts = [provider.name]
        if let model { parts.append(model) }
        if let effort { parts.append("effort \(effort)") }
        if thinking == false { parts.append("no thinking") }
        return parts.joined(separator: " · ")
    }
}

public enum AgentFactory {
    /// Environment variables Claude Code reads for its sign-in; cleared so the chosen sign-in is the one used.
    static let claudeAuthVariables = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL"]

    /// The runner for a task, with its provider and model, or an error that says what to fix in Settings.
    public static func resolve(_ role: AgentRole, settings: AgentSettings, context: AgentContext) throws -> ResolvedAgent {
        guard let choice = settings.choice(role), let provider = settings.provider(choice.providerId) else { throw AgentSetupError.noProvider(role) }
        guard provider.enabled else { throw AgentSetupError.providerOff(role, provider.name) }
        let model = nonEmpty(choice.model) ?? nonEmpty(provider.defaultModel)
        var resolved = try make(provider, model: model, effort: nonEmpty(choice.effort), thinking: choice.thinking, context: context, timeout: role.timeout)
        resolved.role = role
        return resolved
    }

    /// A runner for one provider and model, used by `resolve` and by the Test button.
    public static func make(_ p: AgentProvider, model: String?, effort: String?, thinking: Bool? = nil, context: AgentContext,
                            timeout: TimeInterval) throws -> ResolvedAgent {
        // Only send an effort the model accepts; a model the list does not know gets it as asked.
        let effort: String? = {
            guard let effort else { return nil }
            if let info = p.model(model), !info.efforts.contains(effort) { return nil }
            return effort
        }()
        let dir = context.workingDirectory
        let runner: AgentRunner
        switch p.kind {
        case .claudeCode:
            runner = ClaudeCLIRunner(executable: p.executable ?? "claude", model: model, workingDirectory: dir, timeout: timeout,
                                     extraArguments: p.extraArguments, lean: true, effort: effort,
                                     environment: try claudeEnvironment(p, secrets: context.secrets, thinking: thinking))
        case .codex:
            runner = CodexCLIRunner(executable: p.executable ?? "codex", model: model, effort: effort, workingDirectory: dir, timeout: timeout,
                                    environment: AgentProcess.environment(), extraArguments: p.extraArguments)
        case .geminiCLI:
            var add: [String: String] = [:]
            if let key = context.secrets.apiKey(for: p) { add["GEMINI_API_KEY"] = key }
            runner = GeminiCLIRunner(executable: p.executable ?? "gemini", model: model, workingDirectory: dir, timeout: timeout,
                                     environment: AgentProcess.environment(adding: add), extraArguments: p.extraArguments)
        case .opencode:
            runner = OpenCodeRunner(executable: p.executable ?? "opencode", model: model, workingDirectory: dir, timeout: timeout,
                                    environment: AgentProcess.environment(), extraArguments: p.extraArguments)
        case .anthropicAPI:
            guard let key = context.secrets.apiKey(for: p) else { throw AgentSetupError.missingKey(p.name) }
            runner = AnthropicAPIRunner(baseURL: nonEmpty(p.baseURL) ?? AnthropicAPIRunner.defaultBaseURL, apiKey: key, model: model, effort: effort,
                                        timeout: timeout, transport: context.transport)
        case .openAICompatible:
            guard let base = nonEmpty(p.baseURL) else { throw AgentSetupError.missingBaseURL(p.name) }
            let key = context.secrets.apiKey(for: p)
            if key == nil && p.usesAPIKey { throw AgentSetupError.missingKey(p.name) }
            runner = OpenAICompatibleRunner(baseURL: base, apiKey: key, model: model, effort: effort, timeout: timeout, transport: context.transport)
        }
        return ResolvedAgent(role: nil, provider: p, model: model, effort: effort, thinking: p.kind == .claudeCode ? thinking : nil, runner: runner)
    }

    /// Account sign-in removes any Anthropic key from the environment, so the Claude plan is what pays.
    static func claudeEnvironment(_ p: AgentProvider, secrets: AgentSecrets, thinking: Bool? = nil) throws -> [String: String] {
        var add: [String: String] = thinking == false ? ["MAX_THINKING_TOKENS": "0"] : [:]
        switch p.signIn ?? .account {
        case .account:
            break
        case .apiKey:
            guard let key = secrets.apiKey(for: p) else { throw AgentSetupError.missingKey(p.name) }
            add["ANTHROPIC_API_KEY"] = key
        case .endpoint:
            guard let base = nonEmpty(p.baseURL) else { throw AgentSetupError.missingBaseURL(p.name) }
            guard let key = secrets.apiKey(for: p) else { throw AgentSetupError.missingKey(p.name) }
            add["ANTHROPIC_BASE_URL"] = base; add["ANTHROPIC_AUTH_TOKEN"] = key
        }
        return AgentProcess.environment(removing: claudeAuthVariables + (thinking == nil ? [] : ["MAX_THINKING_TOKENS"]), adding: add)
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

// MARK: Status and test

public struct ProviderStatus: Equatable, Sendable {
    public var ready: Bool
    public var summary: String
    public init(ready: Bool, summary: String) { self.ready = ready; self.summary = summary }
}

public struct ProbeResult: Equatable, Sendable {
    public var text: String
    public var tokensIn: Int
    public var tokensOut: Int
    public var seconds: Double
    public var model: String?
}

public enum ProviderCheck {
    /// Whether a provider can run, without calling a model: the program is found and signed in, or the key is there.
    public static func status(_ p: AgentProvider, context: AgentContext) -> ProviderStatus {
        if let program = p.kind.program {
            guard let path = AgentProcess.locate(program, configured: p.executable) else {
                return ProviderStatus(ready: false, summary: p.executable.map { "No program at \($0)." } ?? "\(program) is not installed, or not on PATH. Set its path.")
            }
            switch p.kind {
            case .claudeCode:
                switch p.signIn ?? .account {
                case .account: return claudeAccount(path)
                case .apiKey: return keyStatus(p, context, found: path)
                case .endpoint:
                    if AgentFactory.nonEmpty(p.baseURL) == nil { return ProviderStatus(ready: false, summary: "Add the endpoint address.") }
                    return keyStatus(p, context, found: path)
                }
            case .codex:
                let r = try? AgentProcess.spawn(path, ["login", "status"], stdin: nil, directory: nil, environment: AgentProcess.environment(), timeout: 15)
                let text = [r?.stdout, r?.stderr].compactMap { $0 }.joined(separator: "\n")
                    .split(whereSeparator: \.isNewline).map(String.init).last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
                if r?.status == 0 { return ProviderStatus(ready: true, summary: text.isEmpty ? "Signed in." : "\(text).") }
                return ProviderStatus(ready: false, summary: "Not signed in. Run `codex login` in Terminal.")
            default:
                if p.usesAPIKey { return keyStatus(p, context, found: path) }
                return ProviderStatus(ready: true, summary: "Found at \(path).")
            }
        }
        if p.kind == .openAICompatible, AgentFactory.nonEmpty(p.baseURL) == nil { return ProviderStatus(ready: false, summary: "Add the server address.") }
        if p.usesAPIKey { return keyStatus(p, context, found: nil) }
        return ProviderStatus(ready: true, summary: "No key needed at \(p.baseURL ?? "").")
    }

    private static func keyStatus(_ p: AgentProvider, _ context: AgentContext, found path: String?) -> ProviderStatus {
        let prefix = path.map { "Found at \($0). " } ?? ""
        if context.secrets.storedKey(providerId: p.id) != nil { return ProviderStatus(ready: true, summary: prefix + "Key saved in the Keychain.") }
        if let env = p.apiKeyEnv, context.secrets.apiKey(for: p) != nil { return ProviderStatus(ready: true, summary: prefix + "Key from $\(env).") }
        return ProviderStatus(ready: false, summary: prefix + "No API key yet.")
    }

    /// Reads `claude auth status` (JSON) for the signed-in account.
    private static func claudeAccount(_ path: String) -> ProviderStatus {
        let env = AgentProcess.environment(removing: AgentFactory.claudeAuthVariables)
        guard let r = try? AgentProcess.spawn(path, ["auth", "status"], stdin: nil, directory: nil, environment: env, timeout: 15),
              let start = r.stdout.firstIndex(of: "{"),
              let obj = (try? JSONSerialization.jsonObject(with: Data(r.stdout[start...].utf8))) as? [String: Any] else {
            return ProviderStatus(ready: true, summary: "Found at \(path). Sign-in not checked.")
        }
        guard (obj["loggedIn"] as? Bool) == true else {
            return ProviderStatus(ready: false, summary: "Not signed in. Run `claude` in Terminal and sign in with your Claude account.")
        }
        let method = obj["authMethod"] as? String
        let who = (obj["email"] as? String).map { " as \($0)" } ?? ""
        let plan = method == "claude.ai" ? "Claude account" : (method ?? "Claude")
        return ProviderStatus(ready: true, summary: "Signed in with your \(plan)\(who).")
    }

    /// One tiny real call, so a setup is known to work before a task depends on it.
    public static func test(_ p: AgentProvider, model: String?, effort: String? = nil, thinking: Bool? = nil, context: AgentContext) throws -> ProbeResult {
        let resolved = try AgentFactory.make(p, model: AgentFactory.nonEmpty(model) ?? AgentFactory.nonEmpty(p.defaultModel), effort: effort,
                                             thinking: thinking, context: context, timeout: 120)
        let started = Date()
        let out = try resolved.runner.run(prompt: "Reply with exactly: OK", options: AgentOptions())
        return ProbeResult(text: out.text.trimmingCharacters(in: .whitespacesAndNewlines), tokensIn: out.tokensIn, tokensOut: out.tokensOut,
                           seconds: Date().timeIntervalSince(started), model: resolved.model)
    }
}
