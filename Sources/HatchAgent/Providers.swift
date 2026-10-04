import Foundation
import HatchCore

// Which program or service does each kind of model work, and with which model. The owner connects providers in
// Settings, turns them on or off, and picks a provider and model per task. Stored as one JSON setting in SQLite so
// the app and the `hatch` CLI read the same choice. API keys are never in it: they live in the Keychain or in an
// environment variable the provider names.

/// How Hatch reaches a model.
public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    /// The `claude` program: a Claude Pro or Max plan, an Anthropic key, or an Anthropic-compatible endpoint (GLM).
    case claudeCode
    /// The `codex` program: a ChatGPT plan or an OpenAI key, as `codex login` set it up.
    case codex
    /// The `gemini` program: a Google account or a Gemini key.
    case geminiCLI
    /// The `opencode` program, with any provider opencode is set up with.
    case opencode
    /// The Anthropic Messages API with a key, called directly.
    case anthropicAPI
    /// Any Chat Completions API: OpenAI, OpenRouter, Z.ai, Gemini, Ollama, LM Studio, LiteLLM.
    case openAICompatible

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .opencode: "opencode"
        case .anthropicAPI: "Anthropic API"
        case .openAICompatible: "OpenAI-compatible API"
        }
    }

    /// The program's name, for the kinds that run one.
    public var program: String? {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .geminiCLI: "gemini"
        case .opencode: "opencode"
        case .anthropicAPI, .openAICompatible: nil
        }
    }

    public var isProgram: Bool { program != nil }
}

/// How the `claude` program signs in. Account uses the plan you are signed in with in Claude Code.
public enum ClaudeSignIn: String, Codable, CaseIterable, Sendable {
    case account, apiKey, endpoint

    public var displayName: String {
        switch self {
        case .account: "Claude account (Pro or Max plan)"
        case .apiKey: "Anthropic API key"
        case .endpoint: "Other endpoint (GLM, proxy)"
        }
    }
}

/// One model a provider offers, as its list reports it.
public struct ModelInfo: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String?
    /// A short note from the provider, such as "Requires usage credits".
    public var note: String?
    /// Effort levels the model accepts. Empty means the setting does not apply.
    public var efforts: [String]
    public var defaultEffort: String?
    /// The provider lists it first (current models); false for older ones.
    public var featured: Bool
    /// An alias such as `haiku` that always points to the newest model of that family.
    public var isAlias: Bool

    public init(id: String, name: String? = nil, note: String? = nil, efforts: [String] = [], defaultEffort: String? = nil,
                featured: Bool = true, isAlias: Bool = false) {
        self.id = id; self.name = name; self.note = note; self.efforts = efforts; self.defaultEffort = defaultEffort
        self.featured = featured; self.isAlias = isAlias
    }

    public var label: String { name.map { $0 == id ? id : "\($0) (\(id))" } ?? id }
}

/// A connected provider.
public struct AgentProvider: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: ProviderKind
    /// Off means no task may use it; a task set to it fails with a message that says so.
    public var enabled: Bool
    /// Path of the program; nil finds it on PATH and in the usual install places.
    public var executable: String?
    public var signIn: ClaudeSignIn?
    /// API address for the API kinds and for Claude Code's endpoint sign-in.
    public var baseURL: String?
    /// Environment variable that holds the API key, used when no key is stored in the Keychain (and by the CLI).
    public var apiKeyEnv: String?
    /// The model a task gets when it names none. Nil leaves it to the program.
    public var defaultModel: String?
    public var models: [ModelInfo]
    public var modelsFetchedAt: Date?
    public var modelsError: String?
    /// Extra arguments for the program, for options Hatch has no field for.
    public var extraArguments: [String]
    /// The known service this provider was set up for (`ModelService.id`), for its name, key link and address.
    public var serviceId: String?
    /// Nil or true: tasks on one of its models move to a newer version of the same family when the list shows one.
    public var autoUpgrade: Bool?
    public var movesToNewVersions: Bool { autoUpgrade ?? true }

    public init(id: String = UUID().uuidString.lowercased(), name: String, kind: ProviderKind, enabled: Bool = true,
                executable: String? = nil, signIn: ClaudeSignIn? = nil, baseURL: String? = nil, apiKeyEnv: String? = nil,
                defaultModel: String? = nil, models: [ModelInfo] = [], modelsFetchedAt: Date? = nil, modelsError: String? = nil,
                extraArguments: [String] = []) {
        self.id = id; self.name = name; self.kind = kind; self.enabled = enabled; self.executable = executable
        self.signIn = signIn ?? (kind == .claudeCode ? .account : nil); self.baseURL = baseURL; self.apiKeyEnv = apiKeyEnv
        self.defaultModel = defaultModel; self.models = models; self.modelsFetchedAt = modelsFetchedAt
        self.modelsError = modelsError; self.extraArguments = extraArguments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(ProviderKind.self, forKey: .kind)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        executable = try c.decodeIfPresent(String.self, forKey: .executable)
        signIn = try c.decodeIfPresent(ClaudeSignIn.self, forKey: .signIn) ?? (kind == .claudeCode ? .account : nil)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL)
        apiKeyEnv = try c.decodeIfPresent(String.self, forKey: .apiKeyEnv)
        defaultModel = try c.decodeIfPresent(String.self, forKey: .defaultModel)
        models = try c.decodeIfPresent([ModelInfo].self, forKey: .models) ?? []
        modelsFetchedAt = try c.decodeIfPresent(Date.self, forKey: .modelsFetchedAt)
        modelsError = try c.decodeIfPresent(String.self, forKey: .modelsError)
        extraArguments = try c.decodeIfPresent([String].self, forKey: .extraArguments) ?? []
        serviceId = try c.decodeIfPresent(String.self, forKey: .serviceId)
        autoUpgrade = try c.decodeIfPresent(Bool.self, forKey: .autoUpgrade)
    }

    /// Whether a key is needed at all (local servers and signed-in programs need none).
    public var usesAPIKey: Bool {
        switch kind {
        case .claudeCode: return signIn == .apiKey || signIn == .endpoint
        case .anthropicAPI: return true
        case .openAICompatible: return !isLocal
        case .geminiCLI: return apiKeyEnv != nil
        case .codex, .opencode: return false
        }
    }

    public var needsBaseURL: Bool { kind == .openAICompatible || (kind == .claudeCode && signIn == .endpoint) }

    public var isLocal: Bool {
        guard let host = baseURL.flatMap({ URL(string: $0)?.host }) else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
    }

    /// Who pays, in one line, so the choice of provider is a choice of bill.
    public var billing: String {
        switch kind {
        case .claudeCode:
            switch signIn ?? .account {
            case .account: return "Uses your Claude plan (Pro or Max)."
            case .apiKey: return "Billed per token to your Anthropic key."
            case .endpoint: return "Billed by the endpoint, for example your GLM Coding Plan."
            }
        case .codex: return "Uses your ChatGPT plan, or the key Codex is signed in with."
        case .geminiCLI: return "Uses your Google account, or the Gemini key."
        case .opencode: return "Billed by whichever provider opencode uses for the model."
        case .anthropicAPI: return "Billed per token to your Anthropic key."
        case .openAICompatible: return isLocal ? "Runs on this Mac; no bill." : "Billed per token to this key."
        }
    }

    /// The listed model with this id, or nil.
    public func model(_ id: String?) -> ModelInfo? {
        guard let id else { return nil }
        return models.first { $0.id == id }
    }
}

/// A ready-made provider for the Add menu.
public struct ProviderPreset: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var provider: AgentProvider

    public static let all: [ProviderPreset] = [
        .init(id: "claude", title: "Claude Code (Claude plan)", provider: .init(name: "Claude Code", kind: .claudeCode, signIn: .account)),
        .init(id: "claude-glm", title: "Claude Code with GLM (Z.ai Coding Plan)",
              provider: .init(name: "GLM via Claude Code", kind: .claudeCode, signIn: .endpoint,
                              baseURL: "https://api.z.ai/api/anthropic", apiKeyEnv: "ZAI_API_KEY")),
        .init(id: "codex", title: "Codex (ChatGPT plan)", provider: .init(name: "Codex", kind: .codex)),
        .init(id: "gemini", title: "Gemini CLI (Google account)", provider: .init(name: "Gemini CLI", kind: .geminiCLI)),
        .init(id: "opencode", title: "opencode", provider: .init(name: "opencode", kind: .opencode)),
        .init(id: "anthropic-api", title: "Anthropic API key",
              provider: .init(name: "Anthropic API", kind: .anthropicAPI, baseURL: AnthropicAPIRunner.defaultBaseURL, apiKeyEnv: "ANTHROPIC_API_KEY")),
        .init(id: "openai", title: "OpenAI API key",
              provider: .init(name: "OpenAI", kind: .openAICompatible, baseURL: "https://api.openai.com/v1", apiKeyEnv: "OPENAI_API_KEY")),
        .init(id: "openrouter", title: "OpenRouter",
              provider: .init(name: "OpenRouter", kind: .openAICompatible, baseURL: "https://openrouter.ai/api/v1", apiKeyEnv: "OPENROUTER_API_KEY")),
        .init(id: "zai", title: "Z.ai GLM API key",
              provider: .init(name: "Z.ai GLM", kind: .openAICompatible, baseURL: "https://api.z.ai/api/paas/v4", apiKeyEnv: "ZAI_API_KEY")),
        .init(id: "gemini-api", title: "Gemini API key",
              provider: .init(name: "Gemini API", kind: .openAICompatible, baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
                              apiKeyEnv: "GEMINI_API_KEY")),
        .init(id: "ollama", title: "Ollama (this Mac)", provider: .init(name: "Ollama", kind: .openAICompatible, baseURL: "http://localhost:11434/v1")),
        .init(id: "lmstudio", title: "LM Studio (this Mac)", provider: .init(name: "LM Studio", kind: .openAICompatible, baseURL: "http://localhost:1234/v1")),
        .init(id: "custom", title: "Other OpenAI-compatible server", provider: .init(name: "Custom server", kind: .openAICompatible, baseURL: "")),
    ]

    /// A copy with a fresh id, ready to add.
    public func make() -> AgentProvider {
        var p = provider
        p.id = UUID().uuidString.lowercased()
        return p
    }
}

/// The kinds of work that call a model. Each picks its own provider and model.
public enum AgentRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case iris, ask

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iris: "Iris (vetting)"
        case .ask: "Ask"
        }
    }

    public var detail: String {
        switch self {
        case .iris: "Checks each new ticket: questions, a rewrite, the type and duplicates."
        case .ask: "Answers your questions about the current ticket or screen."
        }
    }

    /// One recommendation with its reason (rule 3), in one line for the section footer.
    public var recommendation: String {
        switch self {
        case .iris: "Recommended: Haiku with thinking off, about 6 seconds per check with the same questions. Sonnet if rewrites read poorly."
        case .ask: "Recommended: Sonnet, quick answers with good judgement and far less of your plan than Opus."
        }
    }

    /// The model the recommendation names, as a Claude model family, to mark it in the model menu.
    public var recommendedModel: String {
        switch self {
        case .iris: "haiku"
        case .ask: "sonnet"
        }
    }

    /// What the task does, as the title of its section.
    public var taskTitle: String {
        switch self {
        case .iris: "Check new tickets"
        case .ask: "Answer questions"
        }
    }

    /// Seconds before the run is stopped.
    public var timeout: TimeInterval {
        switch self {
        case .iris: 240
        case .ask: 180
        }
    }
}

/// The provider and model one task uses. A nil model means the provider's default model.
public struct RoleChoice: Codable, Equatable, Sendable {
    /// A task set to this does not run (stored so it is not mistaken for "use the default").
    public static let off = RoleChoice(providerId: "")
    public var isOff: Bool { providerId.isEmpty }

    public var providerId: String
    public var model: String?
    public var effort: String?
    /// Claude Code only: false turns thinking off (`MAX_THINKING_TOKENS=0`), for models without effort levels such as
    /// Haiku. Nil leaves the program's default.
    public var thinking: Bool?
    public init(providerId: String, model: String? = nil, effort: String? = nil, thinking: Bool? = nil) {
        self.providerId = providerId; self.model = model; self.effort = effort; self.thinking = thinking
    }
}

public enum AgentSetupError: Error, CustomStringConvertible, Equatable {
    case noProvider(AgentRole)
    case providerOff(AgentRole, String)
    case missingKey(String)
    case missingBaseURL(String)

    public var description: String {
        switch self {
        case .noProvider(let r): return "No provider is chosen for \(r.title). Choose one in Settings, Agents."
        case .providerOff(let r, let name): return "\(r.title) uses \(name), which is turned off. Turn it on or choose another provider in Settings, Agents."
        case .missingKey(let name): return "\(name) has no API key. Add one in Settings, Agents."
        case .missingBaseURL(let name): return "\(name) has no address. Add one in Settings, Agents."
        }
    }
}

public struct AgentSettings: Codable, Equatable, Sendable {
    public static let settingKey = "agent_settings"
    /// The old single setting this replaces; its value becomes the Claude Code provider's path.
    public static let legacyClaudePathKey = "claude_path"
    public static let claudeProviderId = "claude-code"

    public var version: Int
    public var providers: [AgentProvider]
    /// Keyed by `AgentRole.rawValue`, so a role added later decodes from an older file.
    public var roles: [String: RoleChoice]
    /// The program provider that runs coding agents (the agents that build tickets). Nil means Claude Code.
    public var codingProviderId: String?
    /// The provider and model every task uses unless it has its own choice.
    public var defaultChoice: RoleChoice?

    public init(providers: [AgentProvider] = [], roles: [String: RoleChoice] = [:]) {
        self.version = 1; self.providers = providers; self.roles = roles
    }

    /// First run: Claude Code, signed in with the Claude account, Haiku without thinking for Iris and the program's
    /// default for Ask.
    /// Codex, Gemini CLI and opencode are added switched off when they are installed, so connecting one is a click.
    public static func initial(claudePath: String? = nil, detect: Bool = true) -> AgentSettings {
        var providers = [AgentProvider(id: claudeProviderId, name: "Claude Code", kind: .claudeCode,
                                       executable: claudePath.flatMap { $0.isEmpty ? nil : $0 }, signIn: .account)]
        if detect {
            for preset in ["codex", "gemini", "opencode"] {
                guard let p = ProviderPreset.all.first(where: { $0.id == preset }), let program = p.provider.kind.program,
                      AgentProcess.locate(program) != nil else { continue }
                var provider = p.make()
                provider.id = preset
                provider.enabled = false
                providers.append(provider)
            }
        }
        var s = AgentSettings(providers: providers, roles: [
            // Measured on five real tickets: same questions and rewrites, about 6 s instead of 35 to 60 s,
            // and about a twelfth of the output tokens, compared with thinking on.
            AgentRole.iris.rawValue: RoleChoice(providerId: claudeProviderId, model: "haiku", thinking: false),
        ])
        s.defaultChoice = RoleChoice(providerId: claudeProviderId)
        return s
    }

    /// Settings saved before the default existed get one: the choice most tasks share (or Claude Code), and tasks that
    /// match it follow it from then on.
    public mutating func normalize() {
        guard defaultChoice == nil else { return }
        let choices = AgentRole.allCases.compactMap { roles[$0.rawValue] }.filter { !$0.isOff }
        let common = choices.max { a, b in choices.filter { $0 == a }.count < choices.filter { $0 == b }.count }
        defaultChoice = common ?? (provider(Self.claudeProviderId) != nil ? RoleChoice(providerId: Self.claudeProviderId) : providers.first.map { RoleChoice(providerId: $0.id) })
        for role in AgentRole.allCases where roles[role.rawValue] == defaultChoice { roles[role.rawValue] = nil }
    }

    public static func decode(_ json: String) -> AgentSettings? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(AgentSettings.self, from: Data(json.utf8))
    }

    public func encoded() throws -> String {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return String(decoding: try e.encode(self), as: UTF8.self)
    }

    /// The saved settings, or the first-run settings (built from the old `claude_path` setting) when none are saved.
    public static func load(from store: HatchStore, detect: Bool = true) -> AgentSettings {
        if let raw = try? store.setting(settingKey), var s = decode(raw) { s.normalize(); return s }
        let legacy = try? store.setting(legacyClaudePathKey)
        return initial(claudePath: legacy ?? nil, detect: detect)
    }

    public func save(to store: HatchStore) throws {
        try store.setSetting(Self.settingKey, try encoded())
    }

    public func provider(_ id: String) -> AgentProvider? { providers.first { $0.id == id } }

    /// What a task runs with: its own choice, or the default. Nil when it is off or nothing is chosen.
    public func choice(_ role: AgentRole) -> RoleChoice? {
        guard let c = roles[role.rawValue] ?? defaultChoice, !c.isOff else { return nil }
        return c
    }

    /// The task's own choice: nil when it follows the default, `RoleChoice.off` when it is off.
    public func ownChoice(_ role: AgentRole) -> RoleChoice? { roles[role.rawValue] }

    /// Nil makes the task follow the default.
    public mutating func setChoice(_ choice: RoleChoice?, for role: AgentRole) { roles[role.rawValue] = choice }

    public mutating func update(_ provider: AgentProvider) {
        if let i = providers.firstIndex(where: { $0.id == provider.id }) { providers[i] = provider } else { providers.append(provider) }
    }

    /// Removes a provider. Tasks that used it lose their choice and say so when they run.
    public mutating func remove(_ id: String) {
        providers.removeAll { $0.id == id }
        for (k, v) in roles where v.providerId == id { roles[k] = nil }
        if defaultChoice?.providerId == id { defaultChoice = nil }
    }

    /// The tasks that use a provider, for the Settings list and for the warning before turning it off.
    public func roles(using providerId: String) -> [AgentRole] {
        AgentRole.allCases.filter { choice($0)?.providerId == providerId }
    }
}
