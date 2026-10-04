import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Providers for everyone (Settings design, "Providers for everyone, not one setup"): every provider is one of three
// ways to reach a model, and the services behind them are data. A new service is a line here, not a new screen, and a
// setup such as Claude Code through Z.ai is an ordinary provider: a program pointed at a service.

/// How Hatch reaches a model.
public enum ProviderWay: String, CaseIterable, Identifiable, Sendable {
    /// An agent program on this Mac, signed in on its own or pointed at an API service. Only these can be coding agents.
    case program
    /// An API service billed per token to a key.
    case api
    /// A server on this Mac or the network that speaks the OpenAI-compatible API.
    case server

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .program: "A program you are signed in to"
        case .api: "An API service with a key"
        case .server: "A server on this Mac or network"
        }
    }

    public var detail: String {
        switch self {
        case .program: "Claude Code, Codex, Gemini CLI or opencode. Uses your plan."
        case .api: "Anthropic, OpenAI, OpenRouter, Z.ai and more. Billed per token."
        case .server: "Ollama, LM Studio and others. No bill."
        }
    }

    public var symbol: String {
        switch self {
        case .program: "terminal"
        case .api: "network"
        case .server: "server.rack"
        }
    }
}

/// The language a service speaks. A program can be pointed at a service that speaks its language.
public enum ServiceProtocol: String, Codable, Sendable {
    case anthropic, openAI
}

/// One API service Hatch knows: where it is, which variable usually holds its key, and where a key is made.
public struct ModelService: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Address of its Anthropic-compatible API, when it has one (Claude Code can use it).
    public var anthropicURL: String?
    /// Address of its OpenAI-compatible API, when it has one.
    public var openAIURL: String?
    public var keyEnv: String
    /// Where a key is created, shown as a link.
    public var keyPage: String?

    public func url(for p: ServiceProtocol) -> String? { p == .anthropic ? anthropicURL : openAIURL }

    /// Services Hatch knows. Addresses are the ones each service documents.
    public static let all: [ModelService] = [
        .init(id: "anthropic", name: "Anthropic", anthropicURL: "https://api.anthropic.com", openAIURL: nil,
              keyEnv: "ANTHROPIC_API_KEY", keyPage: "https://console.anthropic.com/settings/keys"),
        .init(id: "openai", name: "OpenAI", anthropicURL: nil, openAIURL: "https://api.openai.com/v1",
              keyEnv: "OPENAI_API_KEY", keyPage: "https://platform.openai.com/api-keys"),
        .init(id: "openrouter", name: "OpenRouter", anthropicURL: nil, openAIURL: "https://openrouter.ai/api/v1",
              keyEnv: "OPENROUTER_API_KEY", keyPage: "https://openrouter.ai/keys"),
        .init(id: "zai", name: "Z.ai", anthropicURL: "https://api.z.ai/api/anthropic", openAIURL: "https://api.z.ai/api/paas/v4",
              keyEnv: "ZAI_API_KEY", keyPage: "https://z.ai/manage-apikey/apikey-list"),
        .init(id: "deepseek", name: "DeepSeek", anthropicURL: "https://api.deepseek.com/anthropic", openAIURL: "https://api.deepseek.com",
              keyEnv: "DEEPSEEK_API_KEY", keyPage: "https://platform.deepseek.com/api_keys"),
        .init(id: "moonshot", name: "Moonshot (Kimi)", anthropicURL: "https://api.moonshot.ai/anthropic", openAIURL: "https://api.moonshot.ai/v1",
              keyEnv: "MOONSHOT_API_KEY", keyPage: "https://platform.moonshot.ai/console/api-keys"),
        .init(id: "gemini", name: "Google Gemini", anthropicURL: nil, openAIURL: "https://generativelanguage.googleapis.com/v1beta/openai",
              keyEnv: "GEMINI_API_KEY", keyPage: "https://aistudio.google.com/apikey"),
        .init(id: "mistral", name: "Mistral", anthropicURL: nil, openAIURL: "https://api.mistral.ai/v1",
              keyEnv: "MISTRAL_API_KEY", keyPage: "https://console.mistral.ai/api-keys"),
        .init(id: "groq", name: "Groq", anthropicURL: nil, openAIURL: "https://api.groq.com/openai/v1",
              keyEnv: "GROQ_API_KEY", keyPage: "https://console.groq.com/keys"),
        .init(id: "xai", name: "xAI", anthropicURL: nil, openAIURL: "https://api.x.ai/v1",
              keyEnv: "XAI_API_KEY", keyPage: "https://console.x.ai"),
    ]

    public static func service(_ id: String?) -> ModelService? { all.first { $0.id == id } }

    /// The services a Claude Code provider can be pointed at.
    public static var anthropicCompatible: [ModelService] { all.filter { $0.anthropicURL != nil } }
}

/// A local OpenAI-compatible server Hatch looks for on its usual port.
public struct LocalServer: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: String

    public static let known: [LocalServer] = [
        .init(id: "ollama", name: "Ollama", baseURL: "http://localhost:11434/v1"),
        .init(id: "lmstudio", name: "LM Studio", baseURL: "http://localhost:1234/v1"),
        .init(id: "llamacpp", name: "llama.cpp", baseURL: "http://localhost:8080/v1"),
    ]

    /// Which known servers answer right now, and how many models each lists. Asks each one once, briefly.
    public static func detect(timeout: TimeInterval = 1.5) -> [(server: LocalServer, models: Int)] {
        known.compactMap { s in
            guard let count = modelCount(baseURL: s.baseURL, timeout: timeout) else { return nil }
            return (s, count)
        }
    }

    /// The number of models a server lists at `<baseURL>/models`, or nil when it does not answer.
    public static func modelCount(baseURL: String, timeout: TimeInterval = 1.5) -> Int? {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200, let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                box.value = (json["data"] as? [Any])?.count ?? 0
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 0.5)
        return box.value
    }

    private final class ResultBox: @unchecked Sendable { var value: Int? }
}

extension AgentProvider {
    /// Which of the three ways this provider reaches its model.
    public var way: ProviderWay {
        if kind.isProgram { return .program }
        return kind == .openAICompatible && (isLocal || serviceId == nil && apiKeyEnv == nil) ? .server : .api
    }

    /// A program provider signed in on its own (Claude Code with its account, the other programs).
    public static func program(_ kind: ProviderKind) -> AgentProvider {
        AgentProvider(name: kind.displayName, kind: kind, signIn: kind == .claudeCode ? .account : nil)
    }

    /// Claude Code pointed at an Anthropic-compatible service, named after both so two Claude Code providers differ.
    public static func claudeCode(through service: ModelService) -> AgentProvider {
        var p = AgentProvider(name: "Claude Code · \(service.name)", kind: .claudeCode,
                              signIn: service.id == "anthropic" ? .apiKey : .endpoint,
                              baseURL: service.id == "anthropic" ? nil : service.anthropicURL, apiKeyEnv: service.keyEnv)
        p.serviceId = service.id
        return p
    }

    /// An API service with a key, in the language it speaks best (Anthropic's own API natively, the rest OpenAI-compatible).
    public static func api(_ service: ModelService) -> AgentProvider {
        var p: AgentProvider
        if service.id == "anthropic" {
            p = AgentProvider(name: service.name, kind: .anthropicAPI, baseURL: AnthropicAPIRunner.defaultBaseURL, apiKeyEnv: service.keyEnv)
        } else {
            p = AgentProvider(name: service.name, kind: .openAICompatible, baseURL: service.openAIURL, apiKeyEnv: service.keyEnv)
        }
        p.serviceId = service.id
        return p
    }

    /// A server that speaks the OpenAI-compatible API, known or at an address typed by the owner.
    public static func server(name: String, baseURL: String) -> AgentProvider {
        AgentProvider(name: name, kind: .openAICompatible, baseURL: baseURL)
    }
}
