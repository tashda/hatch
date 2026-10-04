import Foundation
import HatchCore
import HatchGit

// The agent launcher (design-review/agent-launcher.html). Hatch starts coding agents itself: when a ticket is ready
// for agent work and a slot is free, it claims the ticket, makes its workspaces (with the notebook's rules placed),
// writes the brief, and runs the task's program with the task's model. The program may only work in its workspace,
// run git, the build and test commands, and `hatch`; anything else is refused without asking. A run that stops before
// handing in is started once more; a second stop asks the owner on the ticket.

/// What one run of an agent looks like while it works, for the footer, the ticket and the Agents page.
public struct AgentRunInfo: Identifiable, Equatable, Sendable {
    public var id: Int { ticketId }
    public var ticketId: Int
    public var ticketNumber: String
    public var ticketTitle: String
    public var runId: Int
    public var agent: String
    public var role: AgentRole
    public var providerName: String
    public var model: String?
    public var repo: String?
    public var branch: String?
    public var workspace: String
    public var startedAt: Date
    public var attempt: Int
    /// The latest thing the agent did, in a few words ("Editing ToastView.swift", "Running swift build").
    public var step: String
    public var tokensIn: Int
    public var tokensOut: Int
    public var cacheTokens: Int = 0
    public var logPath: String

    public init(ticketId: Int, ticketNumber: String, ticketTitle: String, runId: Int, agent: String, role: AgentRole, providerName: String,
                model: String?, repo: String?, branch: String?, workspace: String, startedAt: Date, attempt: Int, step: String,
                tokensIn: Int, tokensOut: Int, logPath: String) {
        self.ticketId = ticketId; self.ticketNumber = ticketNumber; self.ticketTitle = ticketTitle; self.runId = runId; self.agent = agent
        self.role = role; self.providerName = providerName; self.model = model; self.repo = repo; self.branch = branch
        self.workspace = workspace; self.startedAt = startedAt; self.attempt = attempt; self.step = step
        self.tokensIn = tokensIn; self.tokensOut = tokensOut; self.logPath = logPath
    }
}

/// Turns Claude Code's stream-json lines into steps and token counts. Pure, so it is tested without a program.
public enum AgentStream {
    public struct Event: Equatable, Sendable {
        public var step: String?
        public var model: String?
        public var tokensIn: Int?
        public var tokensOut: Int?
        /// Prompt tokens read from the cache; counted apart from input, since they cost far less.
        public var cacheTokens: Int?
        public var finished = false
        public var isError = false
        public var result: String?
    }

    public static func parse(_ line: String) -> Event? {
        let j = JSONValue.parse(line)
        guard let type = j["type"]?.stringValue else { return nil }
        var e = Event()
        switch type {
        case "system":
            e.model = j["model"]?.stringValue
            e.step = "Starting"
        case "assistant":
            let content = j["message"]?["content"]?.arrayValue ?? []
            for part in content {
                if part["type"]?.stringValue == "tool_use" { e.step = toolStep(part["name"]?.stringValue ?? "", part["input"] ?? .null) }
                else if part["type"]?.stringValue == "text", e.step == nil, let t = part["text"]?.stringValue {
                    let first = t.split(separator: "\n").first.map(String.init) ?? ""
                    if !first.isEmpty { e.step = String(first.prefix(80)) }
                }
            }
            if let usage = j["message"]?["usage"] {
                e.tokensIn = usage["input_tokens"]?.intValue
                e.tokensOut = usage["output_tokens"]?.intValue
            }
        case "result":
            e.finished = true
            e.isError = j["is_error"]?.boolValue ?? (j["subtype"]?.stringValue != "success")
            e.result = j["result"]?.stringValue
            if let usage = j["usage"] {
                e.tokensIn = (usage["input_tokens"]?.intValue ?? 0) + (usage["cache_creation_input_tokens"]?.intValue ?? 0)
                e.cacheTokens = usage["cache_read_input_tokens"]?.intValue
                e.tokensOut = usage["output_tokens"]?.intValue
            }
        default:
            return nil
        }
        return e
    }

    /// A tool call in plain words.
    static func toolStep(_ name: String, _ input: JSONValue) -> String {
        func file(_ key: String) -> String { (input[key]?.stringValue).map { ($0 as NSString).lastPathComponent } ?? "a file" }
        switch name {
        case "Read": return "Reading \(file("file_path"))"
        case "Edit", "MultiEdit": return "Editing \(file("file_path"))"
        case "Write": return "Writing \(file("file_path"))"
        case "Glob", "Grep": return "Searching the code"
        case "Bash":
            let cmd = input["command"]?.stringValue ?? ""
            let first = cmd.split(separator: "\n").first.map(String.init) ?? cmd
            return "Running \(String(first.prefix(60)))"
        case "TodoWrite": return "Planning the steps"
        default: return name
        }
    }
}

public final class AgentLauncher: @unchecked Sendable {
    public struct Configuration: Sendable {
        /// Hatch's data folder, passed to the agent as HATCH_HOME so its `hatch` commands use the same database.
        public var home: URL
        /// The `hatch` command agents call. Without it no agent is started.
        public var hatchPath: String?
        public var context: AgentContext
        public init(home: URL, hatchPath: String?, context: AgentContext) {
            self.home = home; self.hatchPath = hatchPath; self.context = context
        }
    }

    public enum LaunchError: Error, CustomStringConvertible, Equatable {
        case noHatchCommand
        case notForCoding(String)
        case noWorkspace(String)
        public var description: String {
            switch self {
            case .noHatchCommand: "Agents need the hatch command. Choose it in Settings, Agents."
            case .notForCoding(let name): "\(name) cannot run coding agents yet; choose Claude Code for this task in Settings, Agents."
            case .noWorkspace(let why): why
            }
        }
    }

    /// Paused: no new agent starts; running ones finish.
    public static let pausedSetting = "agents_paused"
    /// How many times a run that stopped early is started again before the owner is asked.
    public static let retries = 1

    let store: HatchStore
    let settings: @Sendable () -> AgentSettings
    var config: Configuration
    let onChange: @Sendable () -> Void
    private let lock = NSLock()
    /// One tick at a time, so the timer and a change cannot both take the same ticket.
    private let tickLock = NSLock()
    private var processes: [Int: Process] = [:]
    private var runs: [Int: AgentRunInfo] = [:]
    private var stopping: Set<Int> = []
    private var lastError: [Int: String] = [:]

    public init(store: HatchStore, configuration: Configuration, settings: @escaping @Sendable () -> AgentSettings,
                onChange: @escaping @Sendable () -> Void) {
        self.store = store; self.config = configuration; self.settings = settings; self.onChange = onChange
    }

    public func update(_ configuration: Configuration) { lock.withLock { config = configuration } }

    /// The agents running now, newest first.
    public var running: [AgentRunInfo] { lock.withLock { runs.values.sorted { $0.startedAt > $1.startedAt } } }

    /// Why the last start of a ticket's agent failed, if it did.
    public func problem(ticketId: Int) -> String? { lock.withLock { lastError[ticketId] } }

    public var isPaused: Bool { ((try? store.setting(Self.pausedSetting)) ?? nil) == "1" }

    public func setPaused(_ paused: Bool) throws { try store.setSetting(Self.pausedSetting, paused ? "1" : "0") }

    /// Starts agents for waiting work while slots are free. Called on a timer and after changes.
    public func tick() {
        guard !isPaused, tickLock.try() else { return }
        defer { tickLock.unlock() }
        let busy = lock.withLock { Set(runs.keys) }
        for task in (try? store.agentWork()) ?? [] where task.kind != .vet && !busy.contains(task.ticket.id) {
            guard (try? store.takeSlotAvailable(kind: task.kind, projectId: task.ticket.projectId)) == true else { break }
            do {
                try start(task.ticket.id)
            } catch {
                lock.withLock { lastError[task.ticket.id] = "\(error)" }
                // A ticket that cannot start (no program, no workspace) is not retried every tick until something changes.
                break
            }
        }
    }

    /// Claims the ticket and starts its agent.
    public func start(_ ticketId: Int) throws {
        let cfg = lock.withLock { config }
        guard let hatch = cfg.hatchPath, FileManager.default.isExecutableFile(atPath: hatch) else { throw LaunchError.noHatchCommand }
        guard let t = try store.ticket(id: ticketId), let kind = HatchStore.taskKind(for: t.status, type: t.type) else { return }
        let role = AgentRole.forWork(kind)
        let resolved = try AgentFactory.resolve(role, settings: settings(), context: cfg.context)
        guard resolved.provider.kind == .claudeCode else { throw LaunchError.notForCoding(resolved.provider.name) }

        let agent = "Agent on \(t.displayNumber)"
        let task = try store.take(ticketId, agent: agent)
        do {
            let plan = try Self.plan(store: store, task: task, role: role, provider: resolved.provider, model: resolved.model,
                                     effort: resolved.effort, thinking: resolved.thinking, agent: agent, hatch: hatch, config: cfg)
            try launch(plan, attempt: 1)
        } catch {
            try? store.release(ticketId, reason: "could not start: \(error)")
            throw error
        }
    }

    /// Stops a running agent. The ticket waits, blocked, until the owner resumes it.
    public func stop(_ ticketId: Int) {
        let process = lock.withLock { () -> Process? in
            stopping.insert(ticketId)
            return processes[ticketId]
        }
        process?.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if process?.isRunning == true { process?.terminate() } }
    }

    // MARK: Planning

    /// Everything one run needs, decided before the program starts.
    public struct Plan: Sendable {
        public var ticketId: Int
        public var ticketNumber: String
        public var ticketTitle: String
        public var statusAtStart: Status
        public var role: AgentRole
        public var agent: String
        public var executable: String
        public var arguments: [String]
        public var environment: [String: String]
        public var workingDirectory: String
        public var brief: String
        public var providerName: String
        public var model: String?
        public var repo: String?
        public var branch: String?
        public var logPath: String
    }

    static func plan(store: HatchStore, task: AgentTask, role: AgentRole, provider: AgentProvider, model: String?, effort: String?,
                     thinking: Bool?, agent: String, hatch: String, config: Configuration) throws -> Plan {
        let t = task.ticket
        let spaces = try AgentWorkspaces.make(store: store, task: task)
        guard let main = spaces.main else { throw LaunchError.noWorkspace(spaces.notes.first ?? "No workspace could be made for \(t.displayNumber).") }
        let brief = try BriefBuilder.brief(store: store, ticketId: t.id, agent: agent, kind: task.kind)
        let others = spaces.all.map(\.workspace.path).filter { $0 != main.workspace.path }
        let project = try store.project(id: t.projectId)
        let commands = (project?.config?.repos ?? []).flatMap { [$0.buildCommand, $0.testCommand] }.compactMap { $0 }
        guard let program = AgentProcess.locate(provider.kind.program ?? "claude", configured: provider.executable) else {
            throw LaunchError.noWorkspace("\(provider.name) is not installed, or not on the usual paths.")
        }
        var env = try AgentFactory.claudeEnvironment(provider, secrets: config.context.secrets, thinking: thinking)
        env["HATCH_HOME"] = config.home.path
        env["HATCH_PROJECT"] = project?.key
        // The agent's shell finds `hatch` first, whatever its PATH says.
        env["PATH"] = ((hatch as NSString).deletingLastPathComponent) + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        let logs = config.home.appendingPathComponent("runs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        return Plan(ticketId: t.id, ticketNumber: t.displayNumber, ticketTitle: t.title, statusAtStart: task.ticket.status, role: role, agent: agent,
                    executable: program,
                    arguments: claudeArguments(model: model, effort: effort, otherDirectories: others, commands: commands),
                    environment: env, workingDirectory: main.workspace.path, brief: brief, providerName: provider.name, model: model,
                    repo: main.repo.remote, branch: main.workspace.branch,
                    logPath: logs.appendingPathComponent("\(t.ghNumber ?? t.id)-\(stamp).jsonl").path)
    }

    /// Claude Code, headless: the brief on stdin, a live stream on stdout, only the tools the work needs (decision 3).
    public static func claudeArguments(model: String?, effort: String?, otherDirectories: [String], commands: [String]) -> [String] {
        var tools = ["Read", "Edit", "MultiEdit", "Write", "Glob", "Grep", "TodoWrite", "Bash(git *)", "Bash(hatch *)"]
        // The build and test commands the project names, by their program (xcodebuild, swift, make…).
        for c in commands {
            guard let program = c.split(separator: " ").first.map(String.init), !program.isEmpty,
                  !tools.contains("Bash(\(program) *)") else { continue }
            tools.append("Bash(\(program) *)")
        }
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--permission-mode", "dontAsk", "--allowedTools"] + tools
        // Every turn re-sends the start-up context, so define only the tools the agent may use, and load no MCP servers
        // or skills: in dontAsk mode anything else was refused anyway. The per-machine sections (folder, git status) move
        // into the first message so the rest is the same for every workspace and stays in the prompt cache.
        // Measured: about 7.7k input tokens per turn instead of about 41.6k, same tools available.
        args += ["--tools", definedTools(tools).joined(separator: ","), "--strict-mcp-config", "--disable-slash-commands",
                 "--exclude-dynamic-system-prompt-sections"]
        if let model { args += ["--model", model] }
        if let effort { args += ["--effort", effort] }
        for d in otherDirectories { args += ["--add-dir", d] }
        args += ["--append-system-prompt", "You are a coding agent started by Hatch. Work only in your workspaces. Use the hatch commands in the brief to plan, ask and hand in; never change a ticket's status any other way. When the work is done, hand it in as the brief says and stop."]
        return args
    }

    /// The tool names behind permission rules: `Bash(git *)` needs the Bash tool defined.
    static func definedTools(_ allowed: [String]) -> [String] {
        var names: [String] = []
        for rule in allowed {
            let name = String(rule.prefix { $0 != "(" })
            if !name.isEmpty, !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Whether a run handed in: the ticket left the status it was in when the agent started.
    public static func handedIn(statusAtStart: Status, now: Status) -> Bool { now != statusAtStart }

    // MARK: Running

    private func launch(_ plan: Plan, attempt: Int) throws {
        let runId = try store.startRun(ticketId: plan.ticketId, agent: plan.agent, step: "\(plan.role.taskTitle) · \(plan.model ?? "default model")",
                                       provider: plan.providerName, model: plan.model, role: plan.role.rawValue)
        FileManager.default.createFile(atPath: plan.logPath, contents: nil)
        let log = FileHandle(forWritingAtPath: plan.logPath)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: plan.executable)
        p.arguments = plan.arguments
        p.currentDirectoryURL = URL(fileURLWithPath: plan.workingDirectory)
        p.environment = plan.environment
        let input = Pipe(), output = Pipe()
        p.standardInput = input; p.standardOutput = output; p.standardError = output

        let info = AgentRunInfo(ticketId: plan.ticketId, ticketNumber: plan.ticketNumber, ticketTitle: plan.ticketTitle, runId: runId,
                                agent: plan.agent, role: plan.role, providerName: plan.providerName, model: plan.model, repo: plan.repo,
                                branch: plan.branch, workspace: plan.workingDirectory, startedAt: Date(), attempt: attempt, step: "Starting",
                                tokensIn: 0, tokensOut: 0, logPath: plan.logPath)
        var pending = Data()
        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let self else { return }
            log?.write(data)
            pending.append(data)
            while let nl = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[..<nl], as: UTF8.self)
                pending.removeSubrange(...nl)
                guard let e = AgentStream.parse(line) else { continue }
                self.lock.withLock {
                    guard var r = self.runs[plan.ticketId] else { return }
                    if let s = e.step { r.step = s }
                    if let m = e.model, r.model == nil { r.model = m }
                    if e.finished { r.tokensIn = e.tokensIn ?? r.tokensIn; r.tokensOut = e.tokensOut ?? r.tokensOut; r.cacheTokens = e.cacheTokens ?? r.cacheTokens }
                    else { r.tokensIn += e.tokensIn ?? 0; r.tokensOut += e.tokensOut ?? 0 }
                    self.runs[plan.ticketId] = r
                }
                self.onChange()
            }
        }
        p.terminationHandler = { [weak self] proc in
            output.fileHandleForReading.readabilityHandler = nil
            try? log?.close()
            self?.finished(plan, attempt: attempt, exitCode: proc.terminationStatus)
        }
        lock.withLock { runs[plan.ticketId] = info; processes[plan.ticketId] = p; lastError[plan.ticketId] = nil }
        try p.run()
        input.fileHandleForWriting.write(Data(plan.brief.utf8))
        try? input.fileHandleForWriting.close()
        onChange()
    }

    private func finished(_ plan: Plan, attempt: Int, exitCode: Int32) {
        let (info, stopped) = lock.withLock { () -> (AgentRunInfo?, Bool) in
            let r = runs.removeValue(forKey: plan.ticketId)
            processes[plan.ticketId] = nil
            return (r, stopping.remove(plan.ticketId) != nil)
        }
        let now = (try? store.ticket(id: plan.ticketId))?.status
        let done = now.map { Self.handedIn(statusAtStart: plan.statusAtStart, now: $0) } ?? true
        let outcome = stopped ? "stopped" : done ? "ok" : "stopped early (exit \(exitCode))"
        try? store.endRun(info?.runId ?? 0, tokensIn: info?.tokensIn ?? 0, tokensOut: info?.tokensOut ?? 0, outcome: outcome,
                          cacheTokens: info?.cacheTokens ?? 0)
        defer { onChange() }
        if done { return }
        let tail = Self.tail(of: plan.logPath)
        if stopped {
            try? store.release(plan.ticketId, reason: "stopped by the owner")
            _ = try? store.move(plan.ticketId, to: .blocked, actor: .hatch, reason: "Stopped by you. Resume to start the agent again.")
            return
        }
        if attempt <= Self.retries {
            _ = try? store.addNote(plan.ticketId, kind: .system, author: "hatch",
                                   body: "The agent stopped before handing in (exit \(exitCode)). Starting it once more.\n\n\(tail)")
            var again = plan
            again.logPath = (plan.logPath as NSString).deletingPathExtension + "-\(attempt + 1).jsonl"
            do { try launch(again, attempt: attempt + 1) } catch { lock.withLock { lastError[plan.ticketId] = "\(error)" } }
            return
        }
        try? store.release(plan.ticketId, reason: "stopped twice")
        _ = try? store.ask(plan.ticketId, text: "The agent stopped twice before handing in (exit \(exitCode)). Its last lines are in the thread. Should it try again?",
                           suggestions: ["Try again", "Stop working on it"], by: "Hatch")
        _ = try? store.addNote(plan.ticketId, kind: .system, author: "hatch", body: tail)
    }

    /// The last lines the program wrote, as plain text, for the ticket's thread.
    public static func tail(of path: String, lines: Int = 12) -> String {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        let readable = text.split(separator: "\n").suffix(60).compactMap { line -> String? in
            let s = String(line)
            if let e = AgentStream.parse(s) { return e.result ?? e.step }
            return s.isEmpty ? nil : String(s.prefix(200))
        }
        return readable.suffix(lines).joined(separator: "\n")
    }
}

/// The workspaces a kind of agent work needs, made the same way for `hatch take` and the launcher.
public enum AgentWorkspaces {
    public struct Space: Sendable { public var repo: Repo; public var workspace: Workspace }
    public struct Result: Sendable {
        public var all: [Space] = []
        public var notes: [String] = []
        /// Where the program runs: the app for building and fixing, the notebook (specimens) for preparing.
        public var main: Space?
    }

    public static func roles(for kind: AgentTaskKind) -> [RepoRole] {
        switch kind {
        case .prepare, .revise: [.specimens, .notebook]
        case .build, .fix: [.app, .designSystem, .notebook]
        case .vet: []
        }
    }

    public static func make(store: HatchStore, task: AgentTask, git: GitRunner = ProcessGit()) throws -> Result {
        var r = Result()
        let wanted = roles(for: task.kind)
        let manager = WorkspaceManager(store: store, git: git)
        for repo in try store.repos(projectId: task.ticket.projectId) where wanted.contains(repo.role) {
            guard repo.localPath != nil else { r.notes.append("No local clone configured for the \(repo.role.rawValue) repository, so no workspace was made for it."); continue }
            r.all.append(Space(repo: repo, workspace: try manager.create(ticket: task.ticket, repo: repo)))
        }
        let order: [RepoRole] = task.kind == .build || task.kind == .fix ? [.app, .designSystem, .notebook] : [.notebook, .specimens]
        r.main = order.lazy.compactMap { role in r.all.first { $0.repo.role == role } }.first
        return r
    }
}
