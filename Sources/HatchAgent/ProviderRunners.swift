import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// One runner per kind of provider. Each turns a prompt into text and token counts, and turns every failure into an
// `AgentRunnerError` whose text says what to do. Prompts always go through stdin for the CLIs, so size never matters.

private func jsonObject(_ line: Substring) -> [String: Any]? {
    guard let data = line.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

private func number(_ any: Any?) -> Int { (any as? NSNumber)?.intValue ?? 0 }

/// An error message may itself be a JSON string (`{"error":{"message":...}}`); show the inner message.
func readableError(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let obj = jsonObject(Substring(trimmed)) {
        if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
        if let m = obj["message"] as? String { return m }
    }
    return trimmed
}

// MARK: Codex (ChatGPT plan or an OpenAI key, whatever `codex login` set up)

/// Runs `codex exec --json` read-only, with no MCP servers and no saved session, and reads its event stream.
public struct CodexCLIRunner: AgentRunner {
    public var executable: String
    public var model: String?
    public var effort: String?
    public var workingDirectory: URL?
    public var timeout: TimeInterval
    public var environment: [String: String]?
    public var extraArguments: [String]

    public init(executable: String = "codex", model: String? = nil, effort: String? = nil, workingDirectory: URL? = nil,
                timeout: TimeInterval = 300, environment: [String: String]? = nil, extraArguments: [String] = []) {
        self.executable = executable; self.model = model; self.effort = effort; self.workingDirectory = workingDirectory
        self.timeout = timeout; self.environment = environment; self.extraArguments = extraArguments
    }

    func arguments(model: String?) -> [String] {
        var args = ["exec", "--json", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only", "-c", "mcp_servers={}"]
        if let model, !model.isEmpty { args += ["--model", model] }
        if let effort, !effort.isEmpty { args += ["-c", "model_reasoning_effort=\"\(effort)\""] }
        return args + extraArguments + ["-"]
    }

    public func run(prompt: String, options: AgentOptions) throws -> AgentOutput {
        guard let program = AgentProcess.locate(executable) else { throw AgentRunnerError.executableNotFound(executable) }
        let r = try AgentProcess.spawn(program, arguments(model: options.model ?? model), stdin: prompt,
                                       directory: options.workingDirectory ?? workingDirectory, environment: environment,
                                       timeout: options.timeout ?? timeout)
        return try Self.parse(r.stdout, status: r.status, stderr: r.stderr)
    }

    /// Reads the JSONL events: the last `agent_message` is the answer, `turn.completed` has the usage,
    /// `turn.failed` or `error` is a failure. Item events of type `error` are warnings (unknown settings) and are skipped.
    public static func parse(_ stdout: String, status: Int32 = 0, stderr: String = "") throws -> AgentOutput {
        var text: String?
        var tokensIn = 0, tokensOut = 0
        var failure: String?
        for line in stdout.split(whereSeparator: \.isNewline) {
            guard let e = jsonObject(line), let type = e["type"] as? String else { continue }
            switch type {
            case "item.completed":
                if let item = e["item"] as? [String: Any], (item["type"] as? String) == "agent_message", let t = item["text"] as? String { text = t }
            case "turn.completed":
                let u = e["usage"] as? [String: Any] ?? [:]
                // OpenAI counts cached input inside input_tokens; reasoning inside output_tokens is reported apart.
                tokensIn += number(u["input_tokens"])
                tokensOut += number(u["output_tokens"]) + number(u["reasoning_output_tokens"])
            case "turn.failed":
                if let err = e["error"] as? [String: Any], let m = err["message"] as? String { failure = readableError(m) }
            case "error":
                if let m = e["message"] as? String { failure = readableError(m) }
            default: break
            }
        }
        if let failure { throw AgentRunnerError.failed(code: status == 0 ? 1 : status, stderr: failure) }
        if let text { return AgentOutput(text: text, tokensIn: tokensIn, tokensOut: tokensOut) }
        if status != 0 { throw AgentRunnerError.failed(code: status, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        throw AgentRunnerError.badOutput("codex gave no answer: \(String(stdout.prefix(200)))")
    }
}

// MARK: Gemini CLI (Google account, or a Gemini key)

/// Runs `gemini --output-format json` with the prompt on stdin and reads `{response, stats, error}`.
public struct GeminiCLIRunner: AgentRunner {
    public var executable: String
    public var model: String?
    public var workingDirectory: URL?
    public var timeout: TimeInterval
    public var environment: [String: String]?
    public var extraArguments: [String]

    public init(executable: String = "gemini", model: String? = nil, workingDirectory: URL? = nil, timeout: TimeInterval = 300,
                environment: [String: String]? = nil, extraArguments: [String] = []) {
        self.executable = executable; self.model = model; self.workingDirectory = workingDirectory
        self.timeout = timeout; self.environment = environment; self.extraArguments = extraArguments
    }

    /// A normal prompt goes in `--prompt`; a very large one goes to stdin alone (piped stdin also selects headless mode).
    func invocation(prompt: String, model: String?) -> (args: [String], stdin: String?) {
        var args = ["--output-format", "json"]
        if let model, !model.isEmpty { args += ["--model", model] }
        args += extraArguments
        if prompt.utf8.count > ClaudeCLIRunner.maxArgumentBytes { return (args, prompt) }
        return (args + ["--prompt", prompt], nil)
    }

    public func run(prompt: String, options: AgentOptions) throws -> AgentOutput {
        guard let program = AgentProcess.locate(executable) else { throw AgentRunnerError.executableNotFound(executable) }
        let call = invocation(prompt: prompt, model: options.model ?? model)
        let r = try AgentProcess.spawn(program, call.args, stdin: call.stdin,
                                       directory: options.workingDirectory ?? workingDirectory, environment: environment,
                                       timeout: options.timeout ?? timeout)
        return try Self.parse(r.stdout, status: r.status, stderr: r.stderr)
    }

    /// Tokens: `stats.models.<name>.tokens.prompt` (includes cached) and `candidates` plus `thoughts`, summed over models.
    public static func parse(_ stdout: String, status: Int32 = 0, stderr: String = "") throws -> AgentOutput {
        // Some versions print a line before the JSON; read from the first brace.
        guard let start = stdout.firstIndex(of: "{"), let end = stdout.lastIndex(of: "}"), start < end,
              let obj = jsonObject(stdout[start...end]) else {
            if status != 0 { throw AgentRunnerError.failed(code: status, stderr: readableError(stderr.isEmpty ? stdout : stderr)) }
            throw AgentRunnerError.badOutput("not JSON: \(String(stdout.prefix(200)))")
        }
        if let err = obj["error"] as? [String: Any] {
            throw AgentRunnerError.failed(code: status == 0 ? 1 : status, stderr: (err["message"] as? String) ?? "unknown error")
        }
        guard let text = obj["response"] as? String else { throw AgentRunnerError.badOutput("no \"response\" text") }
        var tokensIn = 0, tokensOut = 0
        let models = (obj["stats"] as? [String: Any])?["models"] as? [String: Any] ?? [:]
        for case let m as [String: Any] in models.values {
            let t = m["tokens"] as? [String: Any] ?? [:]
            tokensIn += number(t["prompt"])
            tokensOut += number(t["candidates"]) + number(t["thoughts"])
        }
        return AgentOutput(text: text, tokensIn: tokensIn, tokensOut: tokensOut)
    }
}

// MARK: opencode (any provider opencode is set up with)

/// Runs `opencode run --format json`. The model is `provider/model` as `opencode models` lists it.
public struct OpenCodeRunner: AgentRunner {
    public var executable: String
    public var model: String?
    public var workingDirectory: URL?
    public var timeout: TimeInterval
    public var environment: [String: String]?
    public var extraArguments: [String]

    public init(executable: String = "opencode", model: String? = nil, workingDirectory: URL? = nil, timeout: TimeInterval = 300,
                environment: [String: String]? = nil, extraArguments: [String] = []) {
        self.executable = executable; self.model = model; self.workingDirectory = workingDirectory
        self.timeout = timeout; self.environment = environment; self.extraArguments = extraArguments
    }

    func arguments(model: String?) -> [String] {
        // A fixed title skips the extra model call opencode otherwise makes to name the session.
        var args = ["run", "--format", "json", "--title", "Hatch"]
        if let model, !model.isEmpty { args += ["--model", model] }
        return args + extraArguments
    }

    public func run(prompt: String, options: AgentOptions) throws -> AgentOutput {
        guard let program = AgentProcess.locate(executable) else { throw AgentRunnerError.executableNotFound(executable) }
        let r = try AgentProcess.spawn(program, arguments(model: options.model ?? model), stdin: prompt,
                                       directory: options.workingDirectory ?? workingDirectory, environment: environment,
                                       timeout: options.timeout ?? timeout)
        return try Self.parse(r.stdout, status: r.status, stderr: r.stderr)
    }

    /// The answer is the text of the last step that had text; tokens are summed over `step_finish` events.
    public static func parse(_ stdout: String, status: Int32 = 0, stderr: String = "") throws -> AgentOutput {
        var current = "", last = ""
        var tokensIn = 0, tokensOut = 0
        var failure: String?
        for line in stdout.split(whereSeparator: \.isNewline) {
            guard let e = jsonObject(line), let type = e["type"] as? String else { continue }
            let part = e["part"] as? [String: Any] ?? [:]
            switch type {
            case "step_start": current = ""
            case "text": current += (part["text"] as? String) ?? ""
            case "step_finish":
                if !current.isEmpty { last = current }
                let t = part["tokens"] as? [String: Any] ?? [:]
                let cache = t["cache"] as? [String: Any] ?? [:]
                tokensIn += number(t["input"]) + number(cache["read"]) + number(cache["write"])
                tokensOut += number(t["output"]) + number(t["reasoning"])
            case "error":
                let err = e["error"] as? [String: Any] ?? [:]
                let data = err["data"] as? [String: Any] ?? [:]
                failure = (err["message"] as? String) ?? (data["message"] as? String) ?? (err["name"] as? String) ?? "unknown error"
            default: break
            }
        }
        if last.isEmpty { last = current }
        if let failure { throw AgentRunnerError.failed(code: status == 0 ? 1 : status, stderr: failure) }
        if !last.isEmpty { return AgentOutput(text: last, tokensIn: tokensIn, tokensOut: tokensOut) }
        if status != 0 { throw AgentRunnerError.failed(code: status, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        throw AgentRunnerError.badOutput("opencode gave no answer: \(String(stdout.prefix(200)))")
    }
}

// MARK: HTTP

/// The one place HTTP is sent, so tests replace it.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) throws -> (status: Int, body: Data)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    private final class Box: @unchecked Sendable { var result: Result<(Int, Data), Error>? }

    public func send(_ request: URLRequest) throws -> (status: Int, body: Data) {
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { box.result = .failure(error) }
            else { box.result = .success(((response as? HTTPURLResponse)?.statusCode ?? 0, data ?? Data())) }
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + request.timeoutInterval + 5) == .timedOut {
            task.cancel()
            throw AgentRunnerError.timedOut(seconds: request.timeoutInterval)
        }
        switch box.result {
        case .success(let r): return r
        case .failure(let e as URLError) where e.code == .timedOut: throw AgentRunnerError.timedOut(seconds: request.timeoutInterval)
        case .failure(let e): throw AgentRunnerError.failed(code: -1, stderr: "Could not reach \(request.url?.host ?? "the server"): \(e.localizedDescription)")
        case nil: throw AgentRunnerError.failed(code: -1, stderr: "no response")
        }
    }
}

enum HTTP {
    static func url(_ base: String, _ path: String) throws -> URL {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        guard let url = URL(string: b + path), url.scheme == "http" || url.scheme == "https" else {
            throw AgentRunnerError.failed(code: -1, stderr: "'\(base)' is not an http or https address.")
        }
        return url
    }

    static func request(_ url: URL, method: String = "GET", headers: [String: String], body: [String: Any]? = nil, timeout: TimeInterval) throws -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = method
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    /// The JSON object of a 2xx answer, or a failure that carries the server's own message.
    static func object(_ status: Int, _ body: Data) throws -> [String: Any] {
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        guard (200..<300).contains(status) else {
            var message = String(decoding: body.prefix(400), as: UTF8.self)
            if let obj {
                if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { message = m }
                else if let m = obj["error"] as? String { message = m }
                else if let m = obj["message"] as? String { message = m }
            }
            let hint = status == 401 || status == 403 ? " Check the API key in Settings, Agents." : ""
            throw AgentRunnerError.failed(code: Int32(status), stderr: "HTTP \(status): \(message)\(hint)")
        }
        guard let obj else { throw AgentRunnerError.badOutput("not JSON: \(String(decoding: body.prefix(200), as: UTF8.self))") }
        return obj
    }
}

// MARK: Anthropic Messages API (an API key, or an Anthropic-compatible endpoint such as Z.ai's)

public struct AnthropicAPIRunner: AgentRunner {
    public static let defaultBaseURL = "https://api.anthropic.com"
    public var baseURL: String
    public var apiKey: String?
    public var model: String?
    public var effort: String?
    public var maxTokens: Int
    public var timeout: TimeInterval
    public var transport: HTTPTransport

    public init(baseURL: String = AnthropicAPIRunner.defaultBaseURL, apiKey: String?, model: String?, effort: String? = nil,
                maxTokens: Int = 16_000, timeout: TimeInterval = 300, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL; self.apiKey = apiKey; self.model = model; self.effort = effort
        self.maxTokens = maxTokens; self.timeout = timeout; self.transport = transport
    }

    static func headers(apiKey: String?) -> [String: String] {
        var h = ["anthropic-version": "2023-06-01"]
        if let apiKey, !apiKey.isEmpty { h["x-api-key"] = apiKey }
        return h
    }

    public func run(prompt: String, options: AgentOptions) throws -> AgentOutput {
        guard let m = options.model ?? model, !m.isEmpty else { throw AgentRunnerError.failed(code: -1, stderr: "No model chosen. Pick one in Settings, Agents.") }
        guard let apiKey, !apiKey.isEmpty else { throw AgentRunnerError.failed(code: -1, stderr: "No API key. Add it in Settings, Agents.") }
        var body: [String: Any] = ["model": m, "max_tokens": maxTokens, "messages": [["role": "user", "content": prompt]]]
        if let effort, !effort.isEmpty { body["output_config"] = ["effort": effort] }
        let req = try HTTP.request(try HTTP.url(baseURL, "/v1/messages"), method: "POST", headers: Self.headers(apiKey: apiKey), body: body,
                                   timeout: options.timeout ?? timeout)
        let (status, data) = try transport.send(req)
        return try Self.parse(try HTTP.object(status, data))
    }

    /// Text blocks joined; input tokens include cache reads and writes. A refusal is a failure with its reason.
    static func parse(_ obj: [String: Any]) throws -> AgentOutput {
        if (obj["stop_reason"] as? String) == "refusal" {
            let why = ((obj["stop_details"] as? [String: Any])?["explanation"] as? String) ?? "the model declined this request"
            throw AgentRunnerError.failed(code: 1, stderr: "Refused: \(why)")
        }
        let blocks = obj["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AgentRunnerError.badOutput("no text in the answer") }
        let u = obj["usage"] as? [String: Any] ?? [:]
        return AgentOutput(text: text, tokensIn: number(u["input_tokens"]) + number(u["cache_creation_input_tokens"]) + number(u["cache_read_input_tokens"]),
                           tokensOut: number(u["output_tokens"]))
    }
}

// MARK: OpenAI-compatible Chat Completions (OpenAI, OpenRouter, Z.ai, Gemini's OpenAI endpoint, Ollama, LM Studio, LiteLLM)

public struct OpenAICompatibleRunner: AgentRunner {
    public var baseURL: String
    public var apiKey: String?
    public var model: String?
    public var effort: String?
    public var timeout: TimeInterval
    public var transport: HTTPTransport

    public init(baseURL: String, apiKey: String?, model: String?, effort: String? = nil, timeout: TimeInterval = 300,
                transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL; self.apiKey = apiKey; self.model = model; self.effort = effort
        self.timeout = timeout; self.transport = transport
    }

    static func headers(apiKey: String?) -> [String: String] {
        guard let apiKey, !apiKey.isEmpty else { return [:] }  // Local servers need none.
        return ["Authorization": "Bearer \(apiKey)"]
    }

    public func run(prompt: String, options: AgentOptions) throws -> AgentOutput {
        guard let m = options.model ?? model, !m.isEmpty else { throw AgentRunnerError.failed(code: -1, stderr: "No model chosen. Pick one in Settings, Agents.") }
        var body: [String: Any] = ["model": m, "messages": [["role": "user", "content": prompt]]]
        if let effort, !effort.isEmpty { body["reasoning_effort"] = effort }
        let req = try HTTP.request(try HTTP.url(baseURL, "/chat/completions"), method: "POST", headers: Self.headers(apiKey: apiKey), body: body,
                                   timeout: options.timeout ?? timeout)
        let (status, data) = try transport.send(req)
        return try Self.parse(try HTTP.object(status, data))
    }

    static func parse(_ obj: [String: Any]) throws -> AgentOutput {
        guard let choice = (obj["choices"] as? [[String: Any]])?.first, let message = choice["message"] as? [String: Any] else {
            throw AgentRunnerError.badOutput("no choices in the answer")
        }
        var text = ""
        if let s = message["content"] as? String { text = s }
        else if let parts = message["content"] as? [[String: Any]] { text = parts.compactMap { $0["text"] as? String }.joined() }
        guard !text.isEmpty else {
            if let refusal = message["refusal"] as? String { throw AgentRunnerError.failed(code: 1, stderr: "Refused: \(refusal)") }
            throw AgentRunnerError.badOutput("empty answer")
        }
        let u = obj["usage"] as? [String: Any] ?? [:]
        return AgentOutput(text: text, tokensIn: number(u["prompt_tokens"]), tokensOut: number(u["completion_tokens"]))
    }
}
