import Foundation

public struct AgentOptions: Equatable, Sendable {
    public var model: String?
    public var workingDirectory: URL?
    /// Seconds before the run is stopped. Nil means the runner's own default.
    public var timeout: TimeInterval?
    public init(model: String? = nil, workingDirectory: URL? = nil, timeout: TimeInterval? = nil) {
        self.model = model; self.workingDirectory = workingDirectory; self.timeout = timeout
    }
}

public struct AgentOutput: Equatable, Sendable {
    public var text: String
    public var tokensIn: Int
    public var tokensOut: Int
    public init(text: String, tokensIn: Int = 0, tokensOut: Int = 0) { self.text = text; self.tokensIn = tokensIn; self.tokensOut = tokensOut }
}

public enum AgentRunnerError: Error, CustomStringConvertible, Equatable {
    case executableNotFound(String)
    case failed(code: Int32, stderr: String)
    case timedOut(seconds: Double)
    case badOutput(String)
    case scriptExhausted

    public var description: String {
        switch self {
        case .executableNotFound(let p): return "Could not find the agent program '\(p)'. Install it, or set its path in Settings, Agents."
        case .failed(let code, let err): return "The agent program stopped with exit code \(code): \(err.isEmpty ? "no message" : err)"
        case .timedOut(let s): return "The agent did not answer within \(Int(s)) seconds and was stopped."
        case .badOutput(let m): return "The agent program answered in a form Hatch could not read: \(m)"
        case .scriptExhausted: return "The scripted runner has no more replies."
        }
    }
}

/// The only place a model is called. Everything around it is deterministic Swift, so tests swap this for `ScriptedRunner`.
public protocol AgentRunner: Sendable {
    func run(prompt: String, options: AgentOptions) throws -> AgentOutput
}

/// Runs `claude -p <prompt> --output-format json` and reads the answer and the token counts from its JSON.
/// Running the official program is also how a Claude Pro or Max plan is used: Hatch never reads its login itself.
public struct ClaudeCLIRunner: AgentRunner {
    public var executable: String
    public var model: String?
    public var workingDirectory: URL?
    public var timeout: TimeInterval
    public var extraArguments: [String]
    /// Text-only work (Iris, Ask): no tools, no MCP servers, no slash commands, no saved session.
    /// This cuts about 35k tokens of start-up context per call.
    public var lean: Bool
    public var effort: String?
    /// The child's environment. Nil inherits this process's environment unchanged.
    public var environment: [String: String]?

    public init(executable: String = "claude", model: String? = nil, workingDirectory: URL? = nil, timeout: TimeInterval = 300,
                extraArguments: [String] = [], lean: Bool = false, effort: String? = nil, environment: [String: String]? = nil) {
        self.executable = executable; self.model = model; self.workingDirectory = workingDirectory
        self.timeout = timeout; self.extraArguments = extraArguments
        self.lean = lean; self.effort = effort; self.environment = environment
    }

    /// Absolute path of the program, searching PATH and the usual install places for a bare name. Nil when it is not there.
    public func resolvedExecutable() -> String? { AgentProcess.locate(executable) }

    /// Prompts larger than this go to stdin, because one argument is limited to about 128 KB on Linux.
    static let maxArgumentBytes = 100_000
    static let leanArguments = ["--tools", "", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence"]

    public func run(prompt: String, options: AgentOptions) throws -> AgentOutput {
        guard let program = resolvedExecutable() else { throw AgentRunnerError.executableNotFound(executable) }
        do { return try attempt(program, prompt: prompt, options: options, lean: lean) }
        catch AgentRunnerError.failed(_, let message) where lean && Self.isUnknownOption(message) {
            // An older claude without one of the lean flags: still answer, just with the full start-up context.
            return try attempt(program, prompt: prompt, options: options, lean: false)
        }
    }

    static func isUnknownOption(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("unknown option") || m.contains("unknown argument")
    }

    private func attempt(_ program: String, prompt: String, options: AgentOptions, lean: Bool) throws -> AgentOutput {
        let useStdin = prompt.utf8.count > Self.maxArgumentBytes
        var args = useStdin ? ["-p"] : ["-p", prompt]
        args += ["--output-format", "json"]
        if let m = options.model ?? model { args += ["--model", m] }
        if let effort, !effort.isEmpty { args += ["--effort", effort] }
        if lean { args += Self.leanArguments }
        args += extraArguments
        let seconds = options.timeout ?? timeout
        let result = try AgentProcess.spawn(program, args, stdin: useStdin ? prompt : nil, directory: options.workingDirectory ?? workingDirectory,
                                            environment: environment, timeout: seconds)
        guard result.status == 0 else {
            // The CLI reports some errors as JSON on stdout; prefer that text when it is there.
            let fromJSON: String? = {
                do { return try Self.parse(result.stdout).text }
                catch AgentRunnerError.failed(_, let m) { return m }
                catch { return nil }
            }()
            let detail = fromJSON ?? (result.stderr.isEmpty ? result.stdout : result.stderr)
            throw AgentRunnerError.failed(code: result.status, stderr: detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try Self.parse(result.stdout)
    }

    /// Reads the CLI's JSON: `{"result": "...", "usage": {...}}`, or an array of events that ends with such an object.
    /// Input tokens include cache reads and writes, since those are billed input too.
    public static func parse(_ stdout: String) throws -> AgentOutput {
        guard let data = stdout.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data) else {
            throw AgentRunnerError.badOutput("not JSON: \(String(stdout.prefix(200)))")
        }
        var object: [String: Any]?
        if let o = any as? [String: Any] { object = o }
        else if let a = any as? [[String: Any]] { object = a.last { ($0["type"] as? String) == "result" } }
        guard let obj = object else { throw AgentRunnerError.badOutput("no result object") }
        guard let text = obj["result"] as? String else { throw AgentRunnerError.badOutput("no \"result\" text") }
        if (obj["is_error"] as? Bool) == true { throw AgentRunnerError.failed(code: 1, stderr: text) }
        let usage = obj["usage"] as? [String: Any] ?? [:]
        func n(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
        return AgentOutput(text: text, tokensIn: n("input_tokens") + n("cache_creation_input_tokens") + n("cache_read_input_tokens"), tokensOut: n("output_tokens"))
    }
}

/// A runner for tests: replies in order, or from a closure. It records every prompt it was given.
public final class ScriptedRunner: AgentRunner, @unchecked Sendable {
    public typealias Reply = Result<AgentOutput, Error>
    private let lock = NSLock()
    private var replies: [Reply]
    private let handler: (@Sendable (String, AgentOptions) throws -> AgentOutput)?
    private var seenPrompts: [String] = []
    private var seenOptions: [AgentOptions] = []

    public init(replies: [Reply]) { self.replies = replies; self.handler = nil }
    public init(handler: @escaping @Sendable (String, AgentOptions) throws -> AgentOutput) { self.replies = []; self.handler = handler }

    /// One text reply with token counts.
    public convenience init(text: String, tokensIn: Int = 0, tokensOut: Int = 0) {
        self.init(replies: [.success(AgentOutput(text: text, tokensIn: tokensIn, tokensOut: tokensOut))])
    }

    public var prompts: [String] { lock.lock(); defer { lock.unlock() }; return seenPrompts }
    public var optionsSeen: [AgentOptions] { lock.lock(); defer { lock.unlock() }; return seenOptions }

    public func run(prompt: String, options: AgentOptions) throws -> AgentOutput {
        lock.lock()
        seenPrompts.append(prompt); seenOptions.append(options)
        let reply: Reply? = handler == nil ? (replies.isEmpty ? nil : replies.removeFirst()) : nil
        lock.unlock()
        if let handler { return try handler(prompt, options) }
        guard let reply else { throw AgentRunnerError.scriptExhausted }
        return try reply.get()
    }
}
