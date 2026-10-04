import Foundation
import HatchCore
import HatchGit
import HatchAgent

/// `hatch check`: build and test while working, with only the lines that decide the next step. It never moves the
/// ticket (`hatch ready` does that), so an agent can run it as often as it likes.
enum CheckCommand {
    static let all: [String: Handler] = ["check": check]

    // hatch check #144 [--build | --tests]  -> the project's build and test commands in the ticket's workspaces, digested
    // some-command 2>&1 | hatch check -      -> the digest of any log on stdin (for a single test, a script…)
    // hatch check --file build.log           -> the digest of a saved log
    static func check(_ c: Context) throws {
        if c.args.pos(1) == "-" || c.args.option("file") != nil {
            let data = c.args.option("file").map { FileManager.default.contents(atPath: $0) ?? Data() }
                ?? FileHandle.standardInput.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
            // Piped logs carry no exit status; failure is judged from what they say.
            let failed = BuildLog.digest(text, ok: true).errors > 0 || text.contains("** BUILD FAILED **") || text.contains("** TEST FAILED **")
            let d = BuildLog.digest(text, ok: !failed, root: FileManager.default.currentDirectoryPath)
            c.out.emit(["errors": .int(d.errors), "warnings": .int(d.warnings), "digest": .string(d.text)], text: d.text)
            if failed && !c.out.json { exit(2) }
            return
        }
        let t = try c.ticket(c.args.pos(1))
        let project = try c.store.project(id: t.projectId)
        let spaces = try WorkspaceManager(store: c.store).list(ticketId: t.id).filter { $0.state == "active" }
        guard !spaces.isEmpty else { throw CLIError("No workspace for \(t.displayNumber). Run hatch take first.") }
        let repos = try c.store.repos(projectId: t.projectId)
        let only = c.args.flag("build") ? "build" : (c.args.flag("tests") ? "tests" : nil)
        var sections: [String] = [], allOK = true, ran = 0
        for ws in spaces {
            guard let repo = repos.first(where: { $0.id == ws.repoId }), let cfg = project?.config?.repo(repo.role) else { continue }
            for (kind, cmd) in [("build", cfg.buildCommand), ("tests", cfg.testCommand)] {
                guard let cmd, !cmd.isEmpty, only == nil || only == kind else { continue }
                ran += 1
                let started = Date()
                var status: Int32, log: String, runId: Int?
                if kind == "tests" {
                    // Test runs are recorded, so the app and other agents can see what was tested (section Y).
                    let outcome = try TestRecorder.run(command: cmd, workspace: ws, repo: repo, ticket: t, store: c.store)
                    (status, log) = (outcome.status, outcome.log)
                    runId = outcome.runId
                } else {
                    let r = try AgentProcess.spawn("/bin/sh", ["-c", cmd + " 2>&1"], stdin: nil, directory: URL(fileURLWithPath: ws.path),
                                                   environment: AgentProcess.environment(), timeout: 1800)
                    (status, log) = (r.status, r.stdout + r.stderr)
                }
                let d = BuildLog.digest(log, ok: status == 0, root: ws.path)
                // With recorded results the failing tests come from them; the digest still carries compiler errors.
                let report = runId.flatMap { testReport(store: c.store, runId: $0, digest: d, root: ws.path) } ?? d.text
                sections.append("\(repo.role.rawValue) \(kind) (\(Int(Date().timeIntervalSince(started))) s): \(report)")
                if status != 0 { allOK = false; break }
            }
        }
        guard ran > 0 else { throw CLIError("This project names no build or test command. Set them in Project settings.") }
        let text = sections.joined(separator: "\n\n") + (allOK ? "\nAll passed. Run `hatch ready \(t.displayNumber)` when the work is done." : "")
        c.out.emit(["ok": .bool(allOK), "report": .string(text)], text: text)
        if !allOK && !c.out.json { exit(2) }
    }

    /// "12 passed, 2 failed" and each failing test with the first line of its message, from the recorded run. Nil when
    /// the run has no results (the build broke first), so the log digest speaks instead.
    private static func testReport(store: HatchStore, runId: Int, digest: BuildLog.Digest, root: String) -> String? {
        guard let run = try? store.testRun(id: runId), run.done > 0 else { return nil }
        var lines = ["\(run.failed == 0 ? "passed" : "FAILED"): \(run.passed) passed, \(run.failed) failed, \(run.skipped) skipped (run #\(run.id))"]
        let failing = (try? store.testResults(runId: runId, problemsOnly: true)) ?? []
        for r in failing.prefix(30) {
            let first = (r.message ?? "").split(separator: "\n").first.map(String.init) ?? ""
            let at = r.file.flatMap { f in r.line.map { " (\(relative(f, to: root)):\($0))" } } ?? ""
            lines.append("failed: \(r.suite).\(r.name)\(at) \(first)")
        }
        if failing.count > 30 { lines.append("… and \(failing.count - 30) more failing tests") }
        if digest.errors > 0 { lines.append(digest.text) }
        return lines.joined(separator: "\n")
    }

    /// Xcode reports real paths (/private/tmp), the workspace may be recorded through a link (/tmp).
    private static func relative(_ file: String, to root: String) -> String {
        let real = URL(fileURLWithPath: root).resolvingSymlinksInPath().path + "/"
        for base in [root + "/", real] where file.hasPrefix(base) { return String(file.dropFirst(base.count)) }
        return file
    }
}
