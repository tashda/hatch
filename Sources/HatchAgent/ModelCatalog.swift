import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The models a provider offers, fetched from the provider itself so a new model can be picked the day it ships.
/// Signed-in programs are read from the list they keep for the account (Claude Code and Codex refresh it whenever
/// they run); APIs are asked for their model list.
public enum ModelCatalog {
    public enum Failure: Error, CustomStringConvertible, Equatable {
        case cannotList(String)
        public var description: String {
            switch self { case .cannotList(let m): return m }
        }
    }

    /// Aliases Claude Code resolves to the newest model of each family. Always offered, so "newest Haiku" is a choice.
    public static let claudeAliases: [ModelInfo] = [
        ModelInfo(id: "opus", name: "Newest Opus", featured: true, isAlias: true),
        ModelInfo(id: "sonnet", name: "Newest Sonnet", featured: true, isAlias: true),
        ModelInfo(id: "haiku", name: "Newest Haiku", featured: true, isAlias: true),
    ]

    /// The aliases with the effort levels of the newest listed model of their family (Haiku has none).
    static func aliases(matching listed: [ModelInfo]) -> [ModelInfo] {
        claudeAliases.map { alias in
            var a = alias
            if let newest = listed.first(where: { $0.featured && $0.id.contains("-\(alias.id)-") }) {
                a.efforts = newest.efforts; a.defaultEffort = newest.defaultEffort
                a.note = newest.name.map { "Now \($0)" }
            }
            return a
        }
    }

    public static func fetch(_ p: AgentProvider, context: AgentContext) throws -> [ModelInfo] {
        switch p.kind {
        case .claudeCode:
            switch p.signIn ?? .account {
            case .account:
                let listed = claudeCodeCatalog(directory: claudeConfigDirectory().appendingPathComponent("cache/model-catalog")) ?? []
                return aliases(matching: listed) + listed
            case .apiKey:
                guard let key = context.secrets.apiKey(for: p) else { throw AgentSetupError.missingKey(p.name) }
                let listed = try anthropicModels(base: AnthropicAPIRunner.defaultBaseURL, key: key, bearer: false, context: context)
                return aliases(matching: listed) + listed
            case .endpoint:
                guard let base = AgentFactory.nonEmpty(p.baseURL) else { throw AgentSetupError.missingBaseURL(p.name) }
                guard let key = context.secrets.apiKey(for: p) else { throw AgentSetupError.missingKey(p.name) }
                return try anthropicModels(base: base, key: key, bearer: true, context: context)
            }
        case .codex:
            let file = codexHome().appendingPathComponent("models_cache.json")
            guard let list = codexCatalog(file: file), !list.isEmpty else {
                throw Failure.cannotList("Codex has not saved its model list yet. Run Codex once, then refresh.")
            }
            return list
        case .geminiCLI:
            throw Failure.cannotList("Gemini CLI cannot list its models. Type the model name.")
        case .opencode:
            guard let path = AgentProcess.locate("opencode", configured: p.executable) else { throw AgentRunnerError.executableNotFound(p.executable ?? "opencode") }
            let r = try AgentProcess.spawn(path, ["models"], stdin: nil, directory: context.workingDirectory, environment: AgentProcess.environment(), timeout: 60)
            guard r.status == 0 else { throw AgentRunnerError.failed(code: r.status, stderr: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let list = openCodeModels(r.stdout)
            if list.isEmpty { throw Failure.cannotList("opencode lists no models. Connect a provider with `opencode auth login`.") }
            return list
        case .anthropicAPI:
            guard let key = context.secrets.apiKey(for: p) else { throw AgentSetupError.missingKey(p.name) }
            return try anthropicModels(base: AgentFactory.nonEmpty(p.baseURL) ?? AnthropicAPIRunner.defaultBaseURL, key: key, bearer: false, context: context)
        case .openAICompatible:
            guard let base = AgentFactory.nonEmpty(p.baseURL) else { throw AgentSetupError.missingBaseURL(p.name) }
            let key = context.secrets.apiKey(for: p)
            if key == nil && p.usesAPIKey { throw AgentSetupError.missingKey(p.name) }
            let req = try HTTP.request(try HTTP.url(base, "/models"), headers: OpenAICompatibleRunner.headers(apiKey: key), timeout: 30)
            let (status, body) = try context.transport.send(req)
            return openAIModels(try HTTP.object(status, body))
        }
    }

    /// Fetches and stores the list on the provider, keeping the old list when the fetch fails.
    public static func refresh(_ p: inout AgentProvider, context: AgentContext, now: Date = Date()) {
        do {
            p.models = try fetch(p, context: context)
            p.modelsError = nil
        } catch {
            p.modelsError = "\(error)"
        }
        p.modelsFetchedAt = now
    }

    /// True when the list is older than a day or was never fetched.
    public static func isStale(_ p: AgentProvider, now: Date = Date()) -> Bool {
        guard let at = p.modelsFetchedAt else { return true }
        return now.timeIntervalSince(at) > 24 * 3600
    }

    // MARK: Sources

    static func claudeConfigDirectory() -> URL {
        if let d = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !d.isEmpty { return URL(fileURLWithPath: d) }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
    }

    static func codexHome() -> URL {
        if let d = ProcessInfo.processInfo.environment["CODEX_HOME"], !d.isEmpty { return URL(fileURLWithPath: d) }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    }

    /// Claude Code keeps the models the account may use in `cache/model-catalog/*.json`. The newest file wins.
    static func claudeCodeCatalog(directory: URL) -> [ModelInfo]? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return nil }
        var best: (at: Double, models: [[String: Any]])?
        for name in names where name.hasSuffix(".json") {
            guard let data = fm.contents(atPath: directory.appendingPathComponent(name).path),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let catalog = obj["catalog"] as? [String: Any], let config = catalog["config"] as? [String: Any],
                  let models = config["models"] as? [[String: Any]] else { continue }
            let at = (obj["fetchedAt"] as? NSNumber)?.doubleValue ?? 0
            if best == nil || at > best!.at { best = (at, models) }
        }
        guard let models = best?.models else { return nil }
        return models.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            let thinking = m["thinking"] as? [String: Any]
            let efforts = (thinking?["effort_options"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            let defaultEffort = (thinking?["effort_options"] as? [[String: Any]] ?? []).first { $0["badge"] != nil }?["id"] as? String
            let note = ((m["badge"] as? [String: Any])?["message"] as? String) ?? ((m["notice"] as? [String: Any])?["text"] as? String)
            return ModelInfo(id: id, name: m["name"] as? String, note: note, efforts: efforts, defaultEffort: defaultEffort,
                             featured: (m["section"] as? String ?? "main") == "main")
        }
    }

    /// Codex's `models_cache.json`: models with visibility "list" are the ones the account may pick.
    static func codexCatalog(file: URL) -> [ModelInfo]? {
        guard let data = FileManager.default.contents(atPath: file.path),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return nil }
        return models.compactMap { m in
            guard let id = m["slug"] as? String, (m["visibility"] as? String ?? "list") == "list" else { return nil }
            let efforts = (m["supported_reasoning_levels"] as? [[String: Any]] ?? []).compactMap { $0["effort"] as? String }
            return ModelInfo(id: id, name: m["display_name"] as? String, note: m["description"] as? String, efforts: efforts,
                             defaultEffort: m["default_reasoning_level"] as? String)
        }
    }

    /// `opencode models` prints one `provider/model` per line.
    static func openCodeModels(_ stdout: String) -> [ModelInfo] {
        stdout.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("/") && !$0.contains(" ") }
            .map { ModelInfo(id: $0) }
    }

    static func anthropicModels(base: String, key: String, bearer: Bool, context: AgentContext) throws -> [ModelInfo] {
        var headers = AnthropicAPIRunner.headers(apiKey: key)
        if bearer { headers["Authorization"] = "Bearer \(key)" }
        let req = try HTTP.request(try HTTP.url(base, "/v1/models?limit=1000"), headers: headers, timeout: 30)
        let (status, body) = try context.transport.send(req)
        let data = (try HTTP.object(status, body))["data"] as? [[String: Any]] ?? []
        return data.compactMap { m in (m["id"] as? String).map { ModelInfo(id: $0, name: m["display_name"] as? String) } }
    }

    static func openAIModels(_ obj: [String: Any]) -> [ModelInfo] {
        let data = obj["data"] as? [[String: Any]] ?? obj["models"] as? [[String: Any]] ?? []
        return data.compactMap { m in (m["id"] as? String).map { ModelInfo(id: $0, name: m["name"] as? String) } }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
}

extension AgentSettings {
    /// Claude model families, as they appear in model ids (`claude-haiku-4-5`).
    static let claudeFamilies = ["opus", "sonnet", "haiku", "fable"]

    /// The family of a Claude model id or alias, or nil for other models.
    public static func family(of model: String) -> String? {
        if claudeFamilies.contains(model) { return model }
        return claudeFamilies.first { model.contains("-\($0)-") || model.hasPrefix("\($0)-") }
    }

    /// Moves tasks to real versions (decisions round two): an alias such as `haiku` becomes the newest Haiku the list
    /// shows, and a version moves to a newer one of its family when its provider allows it. Returns what moved, as
    /// (task or "Default", from, to), for the status line.
    @discardableResult
    public mutating func upgradeModels() -> [(what: String, from: String, to: String)] {
        var moved: [(String, String, String)] = []
        func upgraded(_ c: RoleChoice?) -> RoleChoice? {
            guard var c, let model = c.model, let p = provider(c.providerId), let family = Self.family(of: model) else { return nil }
            let listed = p.models.filter { !$0.isAlias && $0.featured && Self.family(of: $0.id) == family }
            guard let newest = listed.first, newest.id != model else { return nil }
            let isAlias = Self.claudeFamilies.contains(model)
            if !isAlias {
                guard p.movesToNewVersions else { return nil }
                // Only forward: a version the list shows below the newest, or one it no longer lists.
                if let i = p.models.firstIndex(where: { $0.id == model }), let j = p.models.firstIndex(where: { $0.id == newest.id }), j > i { return nil }
            }
            c.model = newest.id
            return c
        }
        if let d = upgraded(defaultChoice) { moved.append(("Default", defaultChoice?.model ?? "", d.model ?? "")); defaultChoice = d }
        for role in AgentRole.allCases {
            if let c = upgraded(roles[role.rawValue]) { moved.append((role.taskTitle, roles[role.rawValue]?.model ?? "", c.model ?? "")); roles[role.rawValue] = c }
        }
        return moved
    }
}

