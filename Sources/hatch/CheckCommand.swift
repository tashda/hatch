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
                let r = try AgentProcess.spawn("/bin/sh", ["-c", cmd + " 2>&1"], stdin: nil, directory: URL(fileURLWithPath: ws.path),
                                               environment: AgentProcess.environment(), timeout: 1800)
                let d = BuildLog.digest(r.stdout + r.stderr, ok: r.status == 0, root: ws.path)
                sections.append("\(repo.role.rawValue) \(kind) (\(Int(Date().timeIntervalSince(started))) s): \(d.text)")
                if r.status != 0 { allOK = false; break }
            }
        }
        guard ran > 0 else { throw CLIError("This project names no build or test command. Set them in Project settings.") }
        let text = sections.joined(separator: "\n\n") + (allOK ? "\nAll passed. Run `hatch ready \(t.displayNumber)` when the work is done." : "")
        c.out.emit(["ok": .bool(allOK), "report": .string(text)], text: text)
        if !allOK && !c.out.json { exit(2) }
    }
}
