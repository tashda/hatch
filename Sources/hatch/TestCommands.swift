import Foundation
import HatchCore
import HatchGit
import HatchAgent

/// `hatch tests`: what tests a project has, which ran when, and what failed. Agents never write test records by hand;
/// `hatch check` makes them (see `TestRecorder`).
enum TestCommands {
    static let all: [String: Handler] = ["tests": tests]

    // hatch tests                         -> the latest runs
    // hatch tests runs [--ticket #n]      -> the same, for one ticket
    // hatch tests show <run> [--all]      -> one run: failures, or every test with --all
    // hatch tests list [--failing|--never]-> the catalog with each test's last result
    // hatch tests scan                    -> reads the test sources again
    // hatch tests record <x.xcresult> [--ticket #n] [--agent name] -> adds a run made elsewhere
    static func tests(_ c: Context) throws {
        switch c.args.pos(1) {
        case nil, "runs": try runs(c)
        case "show": try show(c)
        case "list": try list(c)
        case "scan": try scan(c)
        case "record": try record(c)
        case let other?: throw CLIError("Unknown: hatch tests \(other). Use runs, show, list, scan or record.")
        }
    }

    private static func runs(_ c: Context) throws {
        let project = try c.project()
        let ticketId = try c.args.option("ticket").map { try c.ticket($0).id }
        let list = try c.store.testRuns(projectId: project.id, ticketId: ticketId, limit: Int(c.args.option("limit") ?? "") ?? 15)
        let text = list.isEmpty ? "No test runs yet. `hatch check #n` records one." : list.map { describe($0, store: c.store) }.joined(separator: "\n")
        c.out.emit(.array(list.map(json)), text: text)
    }

    private static func show(_ c: Context) throws {
        guard let id = c.args.pos(2).flatMap(Int.init), let run = try c.store.testRun(id: id) else { throw CLIError("Usage: hatch tests show <run number>") }
        let results = try c.store.testResults(runId: id, problemsOnly: !c.args.flag("all"))
        var lines = [describe(run, store: c.store)]
        if let error = run.error { lines.append(error) }
        for r in results {
            lines.append("\(r.status.rawValue.uppercased()) \(r.bundle)/\(r.suite)/\(r.name)" + (r.line.map { " (\(r.file ?? ""):\($0))" } ?? ""))
            if let m = r.message, r.status != .passed { lines.append("    " + m.replacingOccurrences(of: "\n", with: "\n    ")) }
        }
        if results.isEmpty && !c.args.flag("all") { lines.append("No failing tests.") }
        c.out.emit(.object(["run": json(run), "results": .array(results.map { r in
            .object(["bundle": .string(r.bundle), "suite": .string(r.suite), "name": .string(r.name), "status": .string(r.status.rawValue),
                     "message": r.message.map { .string($0) } ?? .null])
        })]), text: lines.joined(separator: "\n"))
    }

    private static func list(_ c: Context) throws {
        let project = try c.project()
        var rows = try c.store.testOverview(projectId: project.id)
        if c.args.flag("failing") { rows = rows.filter { $0.lastStatus == .failed } }
        if c.args.flag("never") { rows = rows.filter { $0.lastStatus == nil } }
        let text = rows.map { r in
            let last = r.lastStatus.map { "\($0.rawValue)" + (r.lastAgent.map { " by \($0)" } ?? "") } ?? "never run"
            return "\(r.info.bundle)/\(r.info.suite)/\(r.info.name): \(last)"
        }.joined(separator: "\n")
        c.out.emit(.array(rows.map { r in
            .object(["test": .string(r.info.id), "last": r.lastStatus.map { .string($0.rawValue) } ?? .null, "agent": r.lastAgent.map { .string($0) } ?? .null])
        }), text: text.isEmpty ? "No tests in the catalog. Run `hatch tests scan`." : text)
    }

    private static func scan(_ c: Context) throws {
        let project = try c.project()
        let repos = try c.store.repos(projectId: project.id).filter { $0.role == .app && $0.localPath != nil }
        guard let repo = repos.first, let path = repo.localPath else { throw CLIError("The app repository has no local path. Set it in Project settings.") }
        let found = TestScanner.scan(root: URL(fileURLWithPath: path))
        try c.store.syncTestCatalog(projectId: project.id, repoId: repo.id, cases: found)
        let bundles = Set(found.map(\.bundle)).count
        c.out.emit(["tests": .int(found.count), "bundles": .int(bundles)], text: "\(found.count) tests in \(bundles) bundles.")
    }

    private static func record(_ c: Context) throws {
        guard let path = c.args.pos(2) else { throw CLIError("Usage: hatch tests record <x.xcresult> [--ticket #n] [--agent name]") }
        let project = try c.project()
        let ticket = try c.args.option("ticket").map { try c.ticket($0) }
        let results = try XCResult.read(path: path)
        let id = try c.store.startTestRun(projectId: project.id, ticketId: ticket?.id, agent: c.args.option("agent") ?? ticket?.takenBy,
                                          command: "recorded from \((path as NSString).lastPathComponent)")
        try c.store.replaceTestResults(runId: id, with: results)
        try c.store.finishTestRun(runId: id, resultPath: path, source: "xcresult")
        let run = try c.store.testRun(id: id)!
        c.out.emit(json(run), text: describe(run, store: c.store))
    }

    // MARK: Output

    static func describe(_ r: TestRun, store: HatchStore) -> String {
        let who = r.agent ?? "manual"
        let ticket = r.ticketId.flatMap { try? store.ticket(id: $0) }.map { " on \($0.displayNumber)" } ?? ""
        let counts = r.state == .running ? "\(r.done) done, \(r.failed) failed" : "\(r.passed) passed, \(r.failed) failed, \(r.skipped) skipped"
        let time = r.duration.map { String(format: " in %.0f s", $0) } ?? ""
        return "#\(r.id) \(r.state.rawValue) \(counts)\(time), \(who)\(ticket)" + (r.scope.map { " [\($0)]" } ?? "")
    }

    private static func json(_ r: TestRun) -> JSONValue {
        .object(["id": .int(r.id), "state": .string(r.state.rawValue), "passed": .int(r.passed), "failed": .int(r.failed), "skipped": .int(r.skipped),
                 "total": .int(r.total), "agent": r.agent.map { .string($0) } ?? .null, "ticket": r.ticketId.map { .int($0) } ?? .null,
                 "scope": r.scope.map { .string($0) } ?? .null])
    }
}

/// Wraps the project's test command for `hatch check`: starts a run record, asks xcodebuild for a result bundle, follows
/// the output while it goes (so the app shows progress) and, at the end, replaces the live numbers with the bundle's.
enum TestRecorder {
    struct Outcome { var status: Int32; var log: String; var runId: Int }

    static func run(command: String, workspace ws: Workspace, repo: Repo, ticket: Ticket, store: HatchStore) throws -> Outcome {
        let dir = URL(fileURLWithPath: Home.directory + "/test-runs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let commit = (try? ProcessGit().git(["rev-parse", "--short", "HEAD"], in: ws.path))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = try store.startTestRun(projectId: ticket.projectId, repoId: repo.id, ticketId: ticket.id, agent: ticket.takenBy, command: command,
                                        scope: scope(of: command), branch: ws.branch, commit: commit, pid: Int(getpid()))
        let logURL = dir.appendingPathComponent("run-\(id).log"), bundle = dir.appendingPathComponent("run-\(id).xcresult")
        let wrapped = withResultBundle(command, path: bundle.path)
        let tail = LogTail(url: logURL, runId: id, store: store)
        tail.start()
        var status: Int32 = 0
        do {
            // The exit status of the test command, not of the redirect around it.
            let r = try AgentProcess.spawn("/bin/sh", ["-c", "(\(wrapped)) > '\(logURL.path)' 2>&1"], stdin: nil,
                                           directory: URL(fileURLWithPath: ws.path), environment: AgentProcess.environment(), timeout: 1800)
            status = r.status
        } catch {
            status = 124
            tail.stop()
            try? store.finishTestRun(runId: id, error: "The test command did not finish: \(error)")
            return Outcome(status: status, log: (try? String(contentsOf: logURL, encoding: .utf8)) ?? "", runId: id)
        }
        tail.stop()
        var source = "log"
        if FileManager.default.fileExists(atPath: bundle.path) {
            do {
                try store.replaceTestResults(runId: id, with: try XCResult.read(path: bundle.path))
                source = "xcresult"
            } catch { /* the live numbers stay; the bundle could not be read */ }
        }
        let counted = try store.testRun(id: id)?.done ?? 0
        let failure: String? = status != 0 && counted == 0 ? "The command failed (exit \(status)) before any test had a result." : nil
        try store.finishTestRun(runId: id, resultPath: source == "xcresult" ? bundle.path : nil, source: source, error: failure)
        return Outcome(status: status, log: (try? String(contentsOf: logURL, encoding: .utf8)) ?? "", runId: id)
    }

    /// An xcodebuild test command gets a result bundle unless it already names one.
    static func withResultBundle(_ command: String, path: String) -> String {
        let words = command.split(separator: " ")
        guard words.contains("xcodebuild"), words.contains("test"), !command.contains("-resultBundlePath") else { return command }
        return command + " -resultBundlePath '\(path)'"
    }

    /// What the command was asked to run: plan, targets and filters, so runs of the same thing can be compared.
    static func scope(of command: String) -> String? {
        let words = command.split(separator: " ").map(String.init)
        var parts: [String] = []
        for (i, w) in words.enumerated() {
            if w.hasPrefix("-only-testing:") { parts.append(String(w.dropFirst("-only-testing:".count))) }
            else if ["-testPlan", "-scheme", "--filter"].contains(w), i + 1 < words.count { parts.append(words[i + 1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Reads a growing log file once a second and tells the store what the XCTest lines say.
private final class LogTail: @unchecked Sendable {
    private let url: URL, runId: Int, store: HatchStore
    private let lock = NSLock()
    private var running = false, offset: UInt64 = 0, partial = "", follower = TestLogFollower()
    private var thread: Thread?

    init(url: URL, runId: Int, store: HatchStore) { self.url = url; self.runId = runId; self.store = store }

    func start() {
        running = true
        let t = Thread { [self] in
            while true {
                lock.lock(); let go = running; lock.unlock()
                drain()
                if !go { return }
                Thread.sleep(forTimeInterval: 0.7)
            }
        }
        thread = t
        t.start()
    }

    /// Stops after one last read of whatever is left.
    func stop() {
        lock.lock(); running = false; lock.unlock()
        while thread?.isFinished == false { Thread.sleep(forTimeInterval: 0.05) }
    }

    private func drain() {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        offset += UInt64(data.count)
        var text = partial + String(decoding: data, as: UTF8.self)
        guard let lastNewline = text.lastIndex(of: "\n") else { partial = text; return }
        partial = String(text[text.index(after: lastNewline)...])
        text = String(text[..<lastNewline])
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            switch follower.feed(String(line)) {
            case .started(let b, let s, let n)?: try? store.setRunningTest(runId: runId, name: "\(b)/\(s)/\(n)")
            case .finished(var r)?: r.runId = runId; try? store.recordTestResult(r)
            case nil: break
            }
        }
    }
}
