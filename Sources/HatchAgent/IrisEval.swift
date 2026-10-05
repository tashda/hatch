import Foundation
import HatchCore
import HatchGit

// The Iris pipeline test bench. One case is one prompt filed as a ticket in a throwaway world (projects with real git
// repositories in a temp folder), checked by Iris, and, when it becomes ready, planned for the agent that would build or
// prepare it: which workspaces, which branch, which brief. Nothing is built and no agent program runs.
//
// Two ways to use it. `IrisEval.scriptedReply` turns a case's gold answer into the JSON a correct Iris would send, so
// `swift test` can run hundreds of prompts for free and prove that Hatch handles every kind of answer. `hatch iris-eval`
// sends the same prompts to the real model and scores what comes back against the gold answer.

public enum IrisEvalOutcome: String, Codable, Sendable { case ready, asks, split, duplicate }

public struct IrisEvalCase: Codable, Sendable {
    public struct Seed: Codable, Sendable {
        public var title: String
        public var body: String
        /// For a seeded ticket: its status ("done", "dropped"), when it is not an open one.
        public var status: String?
        public init(title: String, body: String = "", status: String? = nil) { self.title = title; self.body = body; self.status = status }
    }
    /// What a careful reader would file. `next` is the agent task the ticket should wait for once it is ready.
    public struct Gold: Codable, Sendable {
        public var path: WorkPath
        public var area: String?
        public var outcome: IrisEvalOutcome
        public var next: String?
        public var split: [String]?
        /// The index in `seeds` of the ticket this one repeats.
        public var duplicateOf: Int?
        public var question: String?
        /// Other paths that are just as right where the owner's rules do not pick one ("add 4pt" is small or visual).
        public var alsoPaths: [WorkPath]?
        /// Other areas that are just as right, with "none" for no area.
        public var alsoAreas: [String]?
        /// Another outcome that is just as right (a prompt with nothing in it may be filed with a best reading or asked about).
        public var alsoOutcomes: [IrisEvalOutcome]?
        public init(path: WorkPath, area: String? = nil, outcome: IrisEvalOutcome = .ready, next: String? = nil, split: [String]? = nil,
                    duplicateOf: Int? = nil, question: String? = nil, alsoPaths: [WorkPath]? = nil) {
            self.path = path; self.area = area; self.outcome = outcome; self.next = next; self.split = split
            self.duplicateOf = duplicateOf; self.question = question; self.alsoPaths = alsoPaths
        }
    }
    public var id: String
    public var project: String
    public var title: String
    public var body: String
    public var seeds: [Seed]?
    /// Earlier decisions (title and why) the ticket may clash with.
    public var decisions: [Seed]?
    public var gold: Gold
    /// How the scripted answer is dressed: "plain", "fence", "prose" or "snake". Only the scripted run reads these.
    public var style: String?
    /// Extra things a scripted answer may carry that Hatch must cope with: "urgent", "unknownArea", "ghostRelated", "twoQuestions", "lowConfidence".
    public var quirks: [String]?

    public init(id: String, project: String, title: String, body: String, seeds: [Seed]? = nil, decisions: [Seed]? = nil, gold: Gold, style: String? = nil, quirks: [String]? = nil) {
        self.id = id; self.project = project; self.title = title; self.body = body; self.seeds = seeds; self.decisions = decisions; self.gold = gold
        self.style = style; self.quirks = quirks
    }
}

public struct IrisEvalCheck: Sendable {
    public enum Kind: String, Sendable {
        /// Must hold for any answer Iris could give. A failure is a bug in Hatch.
        case invariant
        /// What a careful reader would have filed. A failure is Iris being wrong (or the gold being arguable).
        case gold
    }
    public var kind: Kind
    public var name: String
    public var ok: Bool
    public var detail: String
}

public struct IrisEvalResult: Sendable {
    public var id: String
    public var checks: [IrisEvalCheck]
    public var tokensIn: Int
    public var tokensOut: Int
    /// What the model sent, kept so a miss can be read.
    public var reply: String = ""
    public var failures: [IrisEvalCheck] { checks.filter { !$0.ok } }
    public var invariantFailures: [IrisEvalCheck] { failures.filter { $0.kind == .invariant } }
}

/// Projects with real git repositories in a temp folder: `echo` (app, design system, notebook, specimens), `web` (app and
/// notebook) and `docs` (notebook only, so work starts there).
public final class IrisEvalWorld {
    public let root: URL
    public let store: HatchStore
    public private(set) var projects: [String: Project] = [:]
    public let git = ProcessGit(environment: ["GIT_AUTHOR_NAME": "T", "GIT_AUTHOR_EMAIL": "t@x", "GIT_COMMITTER_NAME": "T",
                                              "GIT_COMMITTER_EMAIL": "t@x", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"])
    /// The tip of every source repository when the world was made; they must be the same afterwards.
    public private(set) var tips: [String: String] = [:]
    private var nextNumber = 1000

    public static let areas: [String: [String]] = ["echo": ["Notifications", "Settings", "Sidebar", "Editor"], "web": ["Billing", "Auth"], "docs": []]
    static let layout: [String: [RepoRole]] = ["echo": [.app, .designSystem, .notebook, .specimens], "web": [.app, .notebook], "docs": [.notebook]]
    static let roleFolder: [RepoRole: String] = [.app: "app", .designSystem: "design", .notebook: "notebook", .specimens: "specimens"]

    public init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().appendingPathComponent("iris-eval-\(UUID().uuidString)")
        store = try HatchStore.inMemory()
        for (key, roles) in Self.layout {
            var repos: [RepoConfig] = []
            for role in roles {
                let dir = root.appendingPathComponent(key).appendingPathComponent(key + "-" + Self.roleFolder[role]!).path
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try git.git(["init", "-q", "-b", "dev"], in: dir)
                try "x".write(toFile: dir + "/README.md", atomically: true, encoding: .utf8)
                try git.git(["add", "."], in: dir); try git.git(["commit", "-qm", "start"], in: dir)
                tips[dir] = try git.git(["rev-parse", "HEAD"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
                repos.append(RepoConfig(role: role, remote: "acme/\(key)-\(Self.roleFolder[role]!)", branch: "dev", localPath: dir,
                                        buildCommand: role == .app ? "swift build -c \(key)" : nil))
            }
            let areas = (Self.areas[key] ?? []).map { AreaConfig(name: $0, paths: ["\($0)/**"], specPrefix: String($0.prefix(4)).uppercased()) }
            projects[key] = try store.upsertProject(key: key, name: key.capitalized, config: ProjectConfig(
                name: key.capitalized, ticketsRepo: "acme/tickets", repos: repos, areas: areas, docs: []))
        }
    }

    public func number() -> Int { nextNumber += 1; return nextNumber }
    public func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// Source repositories whose branch moved or whose files changed since the world was made.
    public func disturbedSources() -> [String] {
        tips.compactMap { dir, sha in
            let now = (try? git.git(["rev-parse", "HEAD"], in: dir))?.trimmingCharacters(in: .whitespacesAndNewlines)
            let dirty = (try? git.git(["status", "--porcelain"], in: dir))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
            return now == sha && dirty.isEmpty ? nil : dir
        }.sorted()
    }
}

final class RecordingRunner: AgentRunner, @unchecked Sendable {
    let inner: AgentRunner
    private let lock = NSLock()
    private var text = ""
    init(_ inner: AgentRunner) { self.inner = inner }
    var last: String { lock.lock(); defer { lock.unlock() }; return text }
    func run(prompt: String, options: AgentOptions) throws -> AgentOutput {
        let out = try inner.run(prompt: prompt, options: options)
        lock.lock(); text = out.text; lock.unlock()
        return out
    }
}

public enum IrisEval {
    /// A fixed program for plans: nothing is ever run.
    static let program = "/usr/bin/true"

    // MARK: One case

    /// `runner` gets the case and the numbers of its seed tickets (so a scripted answer can name them).
    public static func run(_ c: IrisEvalCase, in world: IrisEvalWorld, runner: (IrisEvalCase, [String]) -> AgentRunner) throws -> IrisEvalResult {
        var checks: [IrisEvalCheck] = []
        func check(_ kind: IrisEvalCheck.Kind, _ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            checks.append(IrisEvalCheck(kind: kind, name: name, ok: ok, detail: ok ? "" : detail()))
        }
        let store = world.store
        guard let project = world.projects[c.project] else { throw StoreError.notFound("project \(c.project)") }

        var seedNumbers: [String] = []
        for s in c.seeds ?? [] {
            let t = try store.createTicket(projectId: project.id, type: .tweak, title: s.title, body: s.body, ghNumber: world.number(), status: s.status.flatMap(Status.init(rawValue:)) ?? .ready)
            seedNumbers.append(t.displayNumber)
        }
        for d in c.decisions ?? [] {
            let host = try store.createTicket(projectId: project.id, type: .question, title: d.title, ghNumber: world.number(), status: .done)
            try store.recordDecision(ticketId: host.id, kind: .design, title: d.title, summary: d.body, choice: d.title, reason: d.body)
        }
        let ticket = try store.createTicket(projectId: project.id, type: .question, title: c.title, body: c.body, ghNumber: world.number(), status: .checking)
        let recorder = RecordingRunner(runner(c, seedNumbers))
        let service = VettingService(store: store, runner: recorder, label: "eval", provider: "eval", model: "eval")
        let outcome = try service.vet(ticketId: ticket.id)

        guard case .vetted(let o) = outcome else {
            if case .failed(let why) = outcome { check(.gold, "Iris's answer was usable", false, why) }
            let t = try store.ticket(id: ticket.id)!
            check(.invariant, "an unusable answer leaves the ticket in Checking with an event", t.status == .checking, "status \(t.status)")
            return IrisEvalResult(id: c.id, checks: checks, tokensIn: 0, tokensOut: 0, reply: recorder.last)
        }
        let t = try store.ticket(id: ticket.id)!
        let open = try store.questions(ticketId: t.id, openOnly: true)

        // Invariants: true whatever Iris said.
        check(.invariant, "the ticket left Checking", t.status != .checking, "still Checking")
        check(.invariant, "at most one question", open.count <= 1, "\(open.count) open")
        check(.invariant, "priority is never above normal", t.priority <= TicketPriority.normal, "priority \(t.priority)")
        check(.invariant, "the ticket stays in its project", t.projectId == project.id)
        check(.invariant, "the owner's words are kept", (t.originalTitle ?? t.title) == c.title, "original title \(t.originalTitle ?? t.title)")
        check(.invariant, "a ticket that is not ready is not claimed", t.takenBy == nil)
        if let area = t.area { check(.invariant, "the area is one the project has", (IrisEvalWorld.areas[c.project] ?? []).contains(area), area) }
        let runs = try store.runRecords(since: Date(timeIntervalSince1970: 0), projectId: project.id).filter { $0.ticketId == t.id }
        check(.invariant, "the check is recorded as one run", runs.count == 1, "\(runs.count) runs")

        // Gold: what a careful reader would file.
        let g = c.gold
        switch g.outcome {
        case .ready, .asks:
            let readyOK = t.status == .ready, asksOK = t.status == .needsAnswers && open.count == 1
            let accepted = [g.outcome] + (g.alsoOutcomes ?? [])
            check(.gold, accepted.map { $0 == .ready ? "filed as ready" : "asks the owner one question" }.joined(separator: " or "),
                  (accepted.contains(.ready) && readyOK) || (accepted.contains(.asks) && asksOK), "status \(t.status), \(open.count) open")
        case .split:
            let oneTicketOK = (g.alsoOutcomes ?? []).contains(.ready) && t.status == .ready && o.split.isEmpty
            check(.gold, "split into \(g.split?.count ?? 0) tickets\(g.alsoOutcomes == nil ? "" : " (or one ticket)")", o.split.count == (g.split?.count ?? 0) || oneTicketOK, "\(o.split.count) parts, status \(t.status)")
            if !o.split.isEmpty { check(.invariant, "the prompt's own ticket is closed once split", t.status == .dropped, "status \(t.status)") }
            for id in o.split {
                let part = try store.ticket(id: id)!
                check(.invariant, "part \(part.displayNumber) is in the same project", part.projectId == project.id)
                check(.invariant, "part \(part.displayNumber) is ready, or waits to be checked as its own ticket", part.status == .ready || part.status == .checking, "status \(part.status)")
                if part.status == .ready { checks += try planReady(part, project: project, world: world, next: nil) }
            }
        case .duplicate:
            check(.gold, "closed as a repeat", t.status.isTerminal, "status \(t.status)")
        }
        if g.outcome != .split && g.outcome != .duplicate {
            let accepted = Set(([g.path] + (g.alsoPaths ?? [])).map(\.type))
            check(.gold, "the kind of work is \(g.path.displayName)\(g.alsoPaths == nil ? "" : " (or " + g.alsoPaths!.map(\.displayName).joined(separator: ", ") + ")")", accepted.contains(t.type), "type \(t.type.rawValue)")
        }
        if (g.outcome == .ready || g.outcome == .asks), let area = g.area {
            let accepted = [area] + (g.alsoAreas ?? [])
            check(.gold, "area is \(accepted.joined(separator: " or "))", accepted.contains(t.area ?? "none"), "area \(t.area ?? "none")")
        }

        // Downstream: what would start once the ticket is ready. Nothing is built and no program runs.
        if t.status == .ready { checks += try planReady(t, project: project, world: world, next: g.alsoPaths == nil ? g.next : nil) }
        // Decisions seeded for this case must not clash with the next case's ticket.
        if c.decisions != nil { try store.db.execute("DELETE FROM decision_fts", []); try store.db.execute("DELETE FROM decision", []) }
        return IrisEvalResult(id: c.id, checks: checks, tokensIn: runs.first?.tokensIn ?? 0, tokensOut: runs.first?.tokensOut ?? 0, reply: recorder.last)
    }

    /// A ready ticket waits for exactly one agent task, and that task can be planned.
    private static func planReady(_ t: Ticket, project: Project, world: IrisEvalWorld, next: String?) throws -> [IrisEvalCheck] {
        var checks: [IrisEvalCheck] = []
        let tasks = try world.store.agentWork(projectId: project.id).filter { $0.ticket.id == t.id }
        checks.append(IrisEvalCheck(kind: .invariant, name: "\(t.displayNumber) waits for exactly one agent task", ok: tasks.count == 1, detail: "\(tasks.count) tasks"))
        if let task = tasks.first {
            if let next { checks.append(IrisEvalCheck(kind: .gold, name: "next is \(next)", ok: task.kind.rawValue == next, detail: "next is \(task.kind.rawValue)")) }
            checks += checkPlan(task, project: project, world: world)
        }
        return checks
    }

    private static func checkPlan(_ task: AgentTask, project: Project, world: IrisEvalWorld) -> [IrisEvalCheck] {
        var checks: [IrisEvalCheck] = []
        func check(_ kind: IrisEvalCheck.Kind, _ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            checks.append(IrisEvalCheck(kind: kind, name: name, ok: ok, detail: ok ? "" : detail()))
        }
        let store = world.store
        let t = task.ticket
        do {
            var settings = AgentSettings.initial(detect: false)
            settings.providers[0].executable = program
            let role = AgentRole.forWork(task.kind)
            let resolved = try AgentFactory.resolve(role, settings: settings, context: AgentContext())
            let config = AgentLauncher.Configuration(home: world.root.appendingPathComponent("home"), hatchPath: "/usr/bin/true", context: AgentContext())
            let plan = try AgentLauncher.plan(store: store, task: task, role: role, provider: resolved.provider, model: resolved.model, effort: resolved.effort,
                                              thinking: resolved.thinking, agent: "Agent on \(t.displayNumber)", hatch: "/usr/bin/true", config: config)

            let own = try store.repos(projectId: project.id)
            let wanted = AgentWorkspaces.roles(for: task.kind)
            let spaces = try store.workspaces(ticketId: t.id)
            let expected = own.filter { wanted.contains($0.role) && $0.localPath != nil }
            check(.invariant, "a workspace for each repo the work needs, in this project only",
                  Set(spaces.map(\.repoId)) == Set(expected.map(\.id)), "got \(spaces.count), expected \(expected.count)")
            check(.invariant, "every workspace is a worktree on the ticket's branch", spaces.allSatisfy { $0.branch == WorkspaceManager.branchName(for: t) && $0.state == "active" },
                  spaces.map(\.branch).joined(separator: ","))
            check(.invariant, "every worktree starts from the repo's base branch tip", spaces.allSatisfy { w in
                guard let r = own.first(where: { $0.id == w.repoId }), let dir = r.localPath else { return false }
                return w.baseSha == world.tips[dir]
            })
            check(.invariant, "every worktree is outside its source clone",
                  spaces.allSatisfy { w in own.first(where: { $0.id == w.repoId }).flatMap(\.localPath).map { !w.path.hasPrefix($0 + "/") } ?? false })
            check(.invariant, "the agent starts in the app, or in the notebook when the project has no app",
                  plan.workingDirectory.contains(own.contains { $0.role == .app } ? "-app" : "-notebook") && plan.workingDirectory.hasPrefix(world.root.appendingPathComponent(project.key).path),
                  plan.workingDirectory)
            check(.invariant, "every other directory it may write to belongs to the project",
                  plan.arguments.indices.filter { plan.arguments[$0] == "--add-dir" }.allSatisfy { plan.arguments[$0 + 1].hasPrefix(world.root.appendingPathComponent(project.key).path) })
            check(.invariant, "the program is Claude Code with nothing but the allowed tools", plan.arguments.contains("--strict-mcp-config") && plan.arguments.contains("dontAsk"))
            check(.invariant, "the agent is told which project", plan.environment["HATCH_PROJECT"] == project.key, plan.environment["HATCH_PROJECT"] ?? "nil")

            let b = plan.brief
            check(.invariant, "the brief names the ticket, its project and its task", b.contains(t.displayNumber) && b.contains("Project: \(project.name)") && b.contains("Task:"))
            check(.invariant, "the brief lists this project's repos and no other project's", own.allSatisfy { b.contains($0.remote) } &&
                  !world.projects.keys.filter { $0 != project.key }.contains { other in b.contains("acme/\(other)-") })
            check(.invariant, "the brief has the rules and the hatch commands to use", b.contains("## Rules for this task") && b.contains("## Next") && b.contains("hatch "))
            check(.invariant, "the brief says Hatch changes the status, not the agent", b.contains("Hatch changes the status, never you"))
            if task.kind == .build, let app = own.first(where: { $0.role == .app }), let build = app.buildCommand {
                check(.invariant, "a build brief carries the app's build command", b.contains(build))
            }
            check(.invariant, "the brief stays compact", b.count < 12_000, "\(b.count) characters")
        } catch {
            check(.invariant, "the agent can be planned", false, "\(error)")
        }
        return checks
    }

    // MARK: The scripted answer

    /// The JSON a correct Iris would send for `c`, dressed the way `c.style` says, with `c.quirks` added.
    public static func scriptedReply(for c: IrisEvalCase, seedNumbers: [String]) -> String {
        let g = c.gold
        var d: [String: Any] = ["path": g.path.rawValue, "questions": [Any](), "related": [Any](), "specTouches": [Any]()]
        if let area = g.area { d["area"] = area }
        d["rewrite"] = ["title": c.title, "body": "Reading: " + c.body, "changes": ["Put in the shape of the type"]]
        d["confidence"] = ["path": 0.9, "area": 0.9]
        let quirks = Set(c.quirks ?? [])
        switch g.outcome {
        case .asks:
            var qs: [[String: Any]] = [["text": g.question ?? "Which one do you mean?", "suggestions": ["The first", "The second"], "stakes": "high"]]
            if quirks.contains("twoQuestions") { qs.append(["text": "And another thing?", "suggestions": ["Yes"], "stakes": "high"]) }
            d["questions"] = qs
        case .split:
            d["path"] = WorkPath.split.rawValue
            d["split"] = (g.split ?? []).map { ["title": $0, "body": "", "path": WorkPath.small.rawValue] }
        case .duplicate:
            if let i = g.duplicateOf, i < seedNumbers.count {
                d["duplicateOf"] = seedNumbers[i]; d["duplicateSure"] = true; d["duplicateWhy"] = "The same screen and the same problem."
            }
        case .ready: break
        }
        if quirks.contains("urgent") { d["priority"] = "urgent" }
        if quirks.contains("unknownArea") { d["area"] = "Imaginary" }
        if quirks.contains("ghostRelated") { d["related"] = ["#99999"]; d["blocks"] = ["#88888"]; d["parent"] = "#77777" }
        if quirks.contains("lowConfidence") { d["confidence"] = ["path": 0.2, "area": 0.2] }
        var json = String(data: (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
        switch c.style {
        case "fence": json = "```json\n\(json)\n```"
        case "prose": json = "Here is my reading of the ticket {not json}.\n\(json)\nLet me know if anything is unclear."
        case "snake": json = json.replacingOccurrences(of: "\"specTouches\"", with: "\"spec_touches\"").replacingOccurrences(of: "\"duplicateOf\"", with: "\"duplicate_of\"")
                .replacingOccurrences(of: "\"duplicateSure\"", with: "\"duplicate_sure\"").replacingOccurrences(of: "\"duplicateWhy\"", with: "\"duplicate_why\"")
        default: break
        }
        return json
    }

    // MARK: Random prompts

    /// A deterministic stream, so a failing run can be repeated from its seed.
    public struct Random: RandomNumberGenerator {
        var state: UInt64
        public init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
        public mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// `count` made-up prompts: a project, a kind of work, wording and answer shape chosen at random from the pools. The gold
    /// answer is known from how each was made.
    public static func generate(seed: UInt64, count: Int) -> [IrisEvalCase] {
        var rng = Random(seed: seed)
        // Each screen belongs to one project and, where the project has a fitting area, to that area.
        let screens: [(project: String, name: String, area: String?)] = [
            ("echo", "toast", "Notifications"), ("echo", "notification banner", "Notifications"), ("echo", "sidebar", "Sidebar"),
            ("echo", "settings sheet", "Settings"), ("echo", "editor toolbar", "Editor"), ("echo", "export dialog", nil), ("echo", "menu bar item", nil),
            ("web", "login form", "Auth"), ("web", "password reset page", "Auth"), ("web", "invoice table", "Billing"), ("web", "checkout summary", "Billing"),
            ("web", "onboarding card", nil), ("docs", "install page", nil), ("docs", "home page", nil)]
        let things = ["padding", "colour", "alignment", "label", "icon", "animation", "empty state", "error text", "font size"]
        let openers = ["", "hey, ", "quick one: ", "ok so ", "Please ", "todo: "]
        var out: [IrisEvalCase] = []
        var used: Set<String> = []
        for i in 0..<count {
            // The same screen and change twice would really be a repeat, so each pair is used once.
            var screen = screens.randomElement(using: &rng)!, thing = things.randomElement(using: &rng)!
            for _ in 0..<30 where used.contains("\(screen.name)/\(thing)") { screen = screens.randomElement(using: &rng)!; thing = things.randomElement(using: &rng)! }
            used.insert("\(screen.name)/\(thing)")
            let opener = openers.randomElement(using: &rng)!
            let kind = Int.random(in: 0..<7, using: &rng)
            let id = "rand-\(seed)-\(i)"
            var seeds: [IrisEvalCase.Seed]?, decisions: [IrisEvalCase.Seed]?
            var gold: IrisEvalCase.Gold
            var title: String, body: String
            let mark = "\(seed)-\(i)"   // keeps one case's wording out of another's candidate list
            switch kind {
            case 0:
                title = "\(opener)\(thing) of the \(screen.name) is wrong (\(mark))"; body = "On the \(screen.name) changing the \(thing) twice makes the app crash. Steps: open it, change the \(thing), change it again."
                gold = .init(path: .bug, area: screen.area, alsoPaths: [.investigate])
            case 1:
                title = "\(opener)Make the \(screen.name) \(thing) bigger (\(mark))"; body = "One obvious change to the \(thing) on the \(screen.name)."
                gold = .init(path: .small, area: screen.area, alsoPaths: [.visual])
            case 2:
                title = "\(opener)How should the \(screen.name) look with a new \(thing)? (\(mark))"; body = "I want to see options for the \(thing) of the \(screen.name) before we decide."
                gold = .init(path: .visual, area: screen.area, alsoPaths: [.approaches])
            case 3:
                // A ticket that undoes an earlier decision must be asked about, never filed over it.
                decisions = [.init(title: "The \(screen.name) \(thing) stays as it is (\(mark))", body: "The owner decided the \(screen.name) \(thing) stays exactly as it is, for every window; no change.")]
                title = "\(opener)change the \(screen.name) \(thing) (\(mark))"; body = "The \(thing) of the \(screen.name) should be different."
                gold = .init(path: .small, area: screen.area, outcome: .asks, question: "This undoes a decision. Keep it or replace it?", alsoPaths: [.visual, .question, .approaches])
            case 4:
                let other = screens.randomElement(using: &rng)!
                title = "\(opener)\(screen.name) \(thing) and also the \(other.name) \(things.randomElement(using: &rng)!) (\(mark))"
                body = "Two unrelated things: the \(thing) of the \(screen.name), and a second change in the \(other.name)."
                gold = .init(path: .split, outcome: .split, split: ["Change the \(thing) of the \(screen.name)", "Change something in the \(other.name)"])
            case 5:
                let t0 = "The \(screen.name) \(thing) overlaps the next row, case \(mark)"
                let b0 = "On the \(screen.name) the \(thing) overlaps the next row when the window is narrow."
                seeds = [.init(title: t0, body: b0)]
                title = t0; body = b0
                gold = .init(path: .bug, outcome: .duplicate, duplicateOf: 0)
            default:
                title = "\(opener)Update the library behind the \(thing) of the \(screen.name) (\(mark))"; body = "Bump the library version that the \(thing) code uses."
                gold = .init(path: .chore, alsoPaths: [.small])
            }
            if gold.outcome != .duplicate { body += " (ref \(mark))" }
            var quirks: [String] = []
            if gold.outcome == .ready || gold.outcome == .asks {
                for q in ["urgent", "unknownArea", "ghostRelated", "lowConfidence"] where Bool.random(using: &rng) && Int.random(in: 0..<3, using: &rng) == 0 { quirks.append(q) }
            }
            if quirks.contains("unknownArea") { gold.area = nil }
            out.append(IrisEvalCase(id: id, project: screen.project, title: title, body: body, seeds: seeds, decisions: decisions, gold: gold,
                                    style: ["plain", "fence", "prose", "snake"].randomElement(using: &rng), quirks: quirks.isEmpty ? nil : quirks))
        }
        return out
    }

    // MARK: Corpus and report

    public static func loadCorpus(_ url: URL) throws -> [IrisEvalCase] { try JSONDecoder().decode([IrisEvalCase].self, from: Data(contentsOf: url)) }

    public struct Summary: Sendable {
        public var cases = 0
        public var casesPassed = 0
        public var invariantFailures = 0
        public var goldChecks = 0
        public var goldPassed = 0
        public var tokensIn = 0
        public var tokensOut = 0
        public var lines: [String] = []
    }

    public static func summarize(_ results: [IrisEvalResult]) -> Summary {
        var s = Summary()
        for r in results {
            s.cases += 1
            if r.failures.isEmpty { s.casesPassed += 1 }
            s.invariantFailures += r.invariantFailures.count
            let gold = r.checks.filter { $0.kind == .gold }
            s.goldChecks += gold.count; s.goldPassed += gold.filter(\.ok).count
            s.tokensIn += r.tokensIn; s.tokensOut += r.tokensOut
            for f in r.failures { s.lines.append("\(r.id) [\(f.kind.rawValue)] \(f.name)\(f.detail.isEmpty ? "" : ": " + f.detail)") }
        }
        return s
    }
}
