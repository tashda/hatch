import Foundation
import HatchCore
import HatchGit
import HatchSync
import HatchAgent
import HatchAPI
import HatchImport

/// Commands that use the other modules. Agents run take, offer, ready; people run vet, sync, serve and the imports.
enum AgentCommands {
    static let all: [String: Handler] = [
        "take": take, "offer": offer, "ready": ready, "vet": vet,
        "sync": sync, "serve": serve, "import-labs": importLabs, "spec": spec, "workspace": workspace, "preview": preview,
        "options": options, "notebook": notebook,
    ]

    // hatch options #160 --option "A|Use actors|One actor per connection" --option "B|Locks" --recommend A --why "..."
    // An agent preparing a Question offers the owner options, one recommended with its reason (decision PS16).
    static func options(_ c: Context) throws {
        let t = try c.ticket(c.args.pos(1))
        let raw = c.args.list("option")
        let usage = "Usage: hatch options #<question> --option \"A|Title|detail|gain|cost\" ... --recommend A --why \"reason\""
        guard !raw.isEmpty else { throw CLIError(usage) }
        let recommend = c.args.option("recommend")
        let options = try raw.map { line -> QuestionOption in
            let parts = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let key = parts[0]
            func part(_ i: Int) -> String? { parts.count > i && !parts[i].isEmpty ? parts[i] : nil }
            // What each option gains and costs is required, so the owner can weigh them side by side (decision DC5).
            guard let gain = part(3), let cost = part(4) else { throw CLIError("Option \(key) needs what it gains and what it costs.\n\(usage)") }
            return QuestionOption(key: key, title: part(1) ?? key, detail: part(2),
                                  recommended: key == recommend, why: key == recommend ? c.args.option("why") : nil, gain: gain, cost: cost)
        }
        guard recommend == nil || options.contains(where: { $0.key == recommend }) else { throw CLIError("--recommend \(recommend!) is not one of the options.") }
        guard recommend != nil else { throw CLIError("Recommend one option with --recommend and say why with --why (the owner's rule).") }
        try c.store.setQuestionOptions(ticketId: t.id, options)
        c.out.emit(["options": .int(options.count)], text: "\(t.displayNumber) now offers \(options.count) options, \(recommend!) recommended. Hand it in with `hatch offer \(t.displayNumber)`.")
    }

    // hatch notebook export [--no-push]  -> decisions, NOW.md and the Spec index brought in step with the notebook clone
    static func notebook(_ c: Context) throws {
        guard c.args.pos(1) == "export" else { throw CLIError("Usage: hatch notebook export [--no-push]") }
        let project = try c.project()
        let spec = try SpecIndexer.indexNotebook(project: project, store: c.store)
        guard let r = try NotebookExport.run(store: c.store, projectId: project.id, token: ProcessInfo.processInfo.environment["GITHUB_TOKEN"],
                                             push: !c.args.flag("no-push")) else {
            throw CLIError("\(project.name) has no notebook clone on this Mac.")
        }
        var text = "Notebook: \(r.decisionsWritten) decision file(s) written, \(r.imported) imported, NOW.md \(r.nowUpdated ? "updated" : "unchanged")"
        text += r.pushed ? ", pushed." : "."
        if let spec { text += " Spec: \(spec.items) item(s) from \(spec.files) file(s)." }
        if !r.waitingForTickets.isEmpty { text += " Waiting for tickets to sync: \(r.waitingForTickets.joined(separator: ", "))." }
        c.out.emit(["written": .int(r.decisionsWritten), "imported": .int(r.imported), "pushed": .bool(r.pushed)], text: text)
    }

    /// Runs a shell command in a folder and returns (ok, the lines that matter, seconds): errors, warnings and failing
    /// tests rather than the last lines, which for xcodebuild are a list of commands, not the error.
    static func shell(_ command: String, in dir: String, timeout: TimeInterval = 1800) -> (ok: Bool, tail: String, seconds: Double) {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", command]; p.currentDirectoryURL = URL(fileURLWithPath: dir)
        p.standardOutput = pipe; p.standardError = pipe
        let start = Date()
        do { try p.run() } catch { return (false, "could not start: \(error)", 0) }
        var data = Data()
        let reader = DispatchQueue(label: "hatch.shell"); let group = DispatchGroup(); group.enter()
        reader.async { data = pipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        if p.isRunning { p.terminate() }
        group.wait()
        let text = String(decoding: data, as: UTF8.self)
        let tail = BuildLog.digest(text, ok: p.terminationStatus == 0, root: dir).text
        return (p.terminationStatus == 0, tail, Date().timeIntervalSince(start))
    }

    // hatch take #151 [--agent "Agent on #151"]  -> claims the ticket, creates workspaces, prints the brief
    static func take(_ c: Context) throws {
        let t = try c.ticket(c.args.pos(1))
        let agent = c.args.option("agent") ?? "Agent on \(t.displayNumber)"
        let task = try c.store.take(t.id, agent: agent)
        var spaces: [String] = [], notes: [String] = []
        if !AgentWorkspaces.roles(for: task.kind).isEmpty && !c.args.flag("no-workspace") {
            // The same workspaces the launcher makes, so a hand-started agent works exactly like one Hatch started.
            let made = try AgentWorkspaces.make(store: c.store, task: task)
            notes += made.notes
            for space in made.all { spaces.append("\(space.repo.role.rawValue): \(space.workspace.path)  (branch \(space.workspace.branch))") }
        }
        let brief = try BriefBuilder.brief(store: c.store, ticketId: t.id, agent: agent, kind: task.kind)
        var text = brief
        if !spaces.isEmpty { text += "\n\nYour workspaces (work only inside these folders):\n" + spaces.map { "  " + $0 }.joined(separator: "\n") }
        if !notes.isEmpty { text += "\n\n" + notes.joined(separator: "\n") }
        c.out.emit(["ticket": .string(t.displayNumber), "task": .string(task.kind.rawValue), "workspaces": .array(spaces.map { .string($0) }), "brief": .string(brief)], text: text)
    }

    // hatch offer #151 manifest.json | --sketch sketch.json | --answer "text"
    static func offer(_ c: Context) throws {
        let t = try c.ticket(c.args.pos(1))
        let service = OfferService(store: c.store, agent: t.takenBy ?? "agent")
        let result: OfferResult
        if let answer = c.args.option("answer") { result = try service.offerAnswer(ticketId: t.id, answer: answer) }
        else if let sketch = c.args.option("sketch") {
            let data = try Data(contentsOf: URL(fileURLWithPath: sketch))
            let manifest = try JSONDecoder().decode(SketchManifest.self, from: data)
            result = try service.offer(ticketId: t.id, sketch: manifest, baseDirectory: URL(fileURLWithPath: sketch).deletingLastPathComponent())
        } else {
            guard let file = c.args.pos(2) else { throw CLIError("Usage: hatch offer #151 manifest.json   |   --sketch sketch.json   |   --answer \"text\"") }
            result = try service.offer(ticketId: t.id, json: try String(contentsOfFile: file, encoding: .utf8))
        }
        switch result {
        case .offered(let ticket, let revision, let warnings):
            let text = "Offered. \(ticket.displayNumber) is now \(ticket.status.displayName) (revision \(revision)); the owner will judge it." + (warnings.isEmpty ? "" : "\nWarnings:\n" + warnings.map { "  - \($0.message)" }.joined(separator: "\n"))
            c.out.emit(["offered": true, "status": .string(ticket.status.rawValue), "revision": .int(revision), "warnings": .array(warnings.map { .string($0.message) })], text: text)
        case .rejected(let issues):
            let text = "Not offered. Fix these and run hatch offer again:\n" + issues.map { "  - [\($0.code)] \($0.message)\n      fix: \($0.fix)" }.joined(separator: "\n")
            c.out.emit(["offered": false, "issues": .array(issues.map { ["code": .string($0.code), "message": .string($0.message), "fix": .string($0.fix)] })], text: text)
            if !c.out.json { exit(2) }
        }
    }

    // hatch ready #144 -> Hatch runs merge-base, build, tests and match check and moves the ticket itself
    static func ready(_ c: Context) throws {
        let t = try c.ticket(c.args.pos(1))
        guard t.status == .building || t.status == .fixing else { throw CLIError("\(t.displayNumber) is \(t.status.displayName); ready only applies while Building or Fixing.") }
        let project = try c.store.project(id: t.projectId)
        let manager = WorkspaceManager(store: c.store)
        let spaces = try manager.list(ticketId: t.id).filter { $0.state == "active" }
        guard !spaces.isEmpty else { throw CLIError("No workspace for \(t.displayNumber). Run hatch take first.") }
        let repos = try c.store.repos(projectId: t.projectId)
        var failures: [String] = [], lines: [String] = []
        func step(_ kind: String, ok: Bool, detail: String, seconds: Double = 0) throws {
            try c.store.record(t.id, actor: "hatch", kind: kind, payload: ["ok": .bool(ok), "detail": .string(detail), "seconds": .number(seconds)])
            lines.append("\(ok ? "ok  " : "FAIL") \(kind): \(detail)")
            if !ok { failures.append("\(kind): \(detail)") }
        }
        for ws in spaces {
            guard let repo = repos.first(where: { $0.id == ws.repoId }) else { continue }
            let cfg = project?.config?.repo(repo.role)
            switch try manager.mergeBaseIntoBranch(ws) {
            case .upToDate, .merged: break
            case .conflicts(let files): try step("merge-base", ok: false, detail: "\(repo.role.rawValue) conflicts with \(repo.defaultBranch) in \(files.joined(separator: ", ")). Resolve them in the workspace and run ready again.")
            }
            let status = try manager.status(ws)
            try step("commit", ok: status.dirtyFiles.isEmpty, detail: status.dirtyFiles.isEmpty ? "\(repo.role.rawValue): \(status.commitsAhead) commit(s) ahead" : "\(repo.role.rawValue) has uncommitted files: \(status.dirtyFiles.prefix(5).joined(separator: ", ")). Commit them first.")
            let drift = try ClaimsFromDiff(store: c.store).claimDrift(t, workspace: ws)
            if drift.hasDrift { try c.store.record(t.id, actor: "hatch", kind: "claim-drift", payload: ["files": .array(drift.unclaimedChanges.map { .string($0) })]); lines.append("note: changed files outside the claim: \(drift.unclaimedChanges.prefix(5).joined(separator: ", "))") }
            // Values typed into views instead of taken from the components (decision CO6): a note, never a failure,
            // because a plain text check can over-count.
            if repo.role == .app, project?.config?.componentsLabel != nil {
                let diff = (try? manager.git.git(["diff", "-U0", "\(repo.defaultBranch)...HEAD", "--", "*.swift"], in: ws.path)) ?? ""
                let found = TypedValues.inDiff(diff, excluding: project?.config?.components?.path)
                if !found.isEmpty {
                    try c.store.record(t.id, actor: "hatch", kind: "typed-values",
                                       payload: ["count": .int(found.count), "files": .array(found.prefix(20).map { .string("\($0.file):\($0.line)") })])
                    lines.append("note: \(found.count) value(s) typed into views instead of taken from the components: "
                                 + found.prefix(5).map { "\($0.file):\($0.line)" }.joined(separator: ", ")
                                 + ". Use the components' names, or add the missing ones there.")
                }
            }
            for (kind, cmd) in [("build", cfg?.buildCommand), ("tests", cfg?.testCommand), ("match-check", cfg?.matchCommand)] {
                guard let cmd, !cmd.isEmpty else { continue }
                let r = shell(cmd, in: ws.path)
                try step(kind, ok: r.ok, detail: r.ok ? "\(repo.role.rawValue) passed" : "\(repo.role.rawValue) failed:\n\(r.tail)", seconds: r.seconds)
                if !r.ok { break }
            }
        }
        // The Spec must follow the code (decision PS13): the agent names the items it changed, or says none changed,
        // and a named change must really be on the notebook's ticket branch.
        if let notebook = repos.first(where: { $0.role == .notebook }) {
            let declared = c.args.option("spec")?.trimmingCharacters(in: .whitespaces) ?? ""
            if declared.isEmpty {
                try step("spec", ok: false, detail: "Say which Spec items you changed: --spec TOAST-3,TOAST-4, or --spec unchanged.")
            } else if declared.lowercased() == "unchanged" {
                try step("spec", ok: true, detail: "unchanged")
            } else if let ws = spaces.first(where: { $0.repoId == notebook.id }) {
                let changed = (try? manager.git.git(["diff", "--name-only", "\(notebook.defaultBranch)...HEAD", "--", Notebook.specDir], in: ws.path)) ?? ""
                try step("spec", ok: !changed.isEmpty, detail: changed.isEmpty
                         ? "--spec names \(declared), but the notebook branch changes nothing in \(Notebook.specDir)/. Edit and commit the Spec there."
                         : "\(declared) in \(changed.split(separator: "\n").joined(separator: ", "))")
            } else {
                try step("spec", ok: false, detail: "No notebook workspace for \(t.displayNumber); run hatch take again to get one.")
            }
        }
        if failures.isEmpty {
            let after = try c.store.move(t.id, to: .toVerify, actor: .hatch, reason: "build, tests and match check passed")
            c.out.emit(["ready": true, "status": .string(after.status.rawValue)], text: lines.joined(separator: "\n") + "\nAll checks passed. \(after.displayNumber) is now \(after.status.displayName); the owner will verify it in a Preview. You are done with this ticket.")
        } else {
            c.out.emit(["ready": false, "failures": .array(failures.map { .string($0) })], text: lines.joined(separator: "\n") + "\nNot ready. Fix the failures above in your workspace, commit, and run hatch ready again.")
            if !c.out.json { exit(2) }
        }
    }

    // hatch vet #151 [--model m]  -> Iris checks a ticket in Checking with the provider chosen in Settings (it costs tokens)
    static func vet(_ c: Context) throws {
        let t = try c.ticket(c.args.pos(1))
        let ctx = AgentSetupCommands.context()
        var settings = AgentSettings.load(from: c.store)
        if let claude = c.args.option("claude"), let i = settings.providers.firstIndex(where: { $0.id == settings.choice(.iris)?.providerId }) {
            settings.providers[i].executable = claude  // Older scripts pass the program's path.
        }
        var iris = try AgentFactory.resolve(.iris, settings: settings, context: ctx)
        if let m = c.args.option("model") {
            iris = try AgentFactory.make(iris.provider, model: m, effort: iris.effort, thinking: iris.thinking, context: ctx, timeout: AgentRole.iris.timeout)
        }
        var service = VettingService(store: c.store, runner: iris.runner, label: iris.label, provider: iris.provider.name, model: iris.model)
        if c.args.option("model") == nil, let unsure = try? AgentFactory.resolve(.irisUnsure, settings: settings, context: ctx), unsure.label != iris.label {
            service.unsure = .init(runner: unsure.runner, label: unsure.label, provider: unsure.provider.name, model: unsure.model)
        }
        let outcome = try service.vet(ticketId: t.id)
        switch outcome {
        case .vetted(let o): c.out.emit(["vetted": true, "questions": .int(o.questionsAsked), "suggestion": .bool(o.suggestionStored), "status": .string(o.status.rawValue)], text: "Iris checked \(t.displayNumber): \(o.questionsAsked) question(s), \(o.suggestionStored ? "a suggestion to review" : "no suggestion"). Status: \(o.status.displayName).")
        case .failed(let why): c.out.emit(["vetted": false, "error": .string(why)], text: "Iris could not check \(t.displayNumber): \(why)"); exit(1)
        }
    }

    static func tracker(_ c: Context) throws -> IssueTracker {
        if c.args.flag("dry-run") { return InMemoryTracker() }
        return GitHubClient()
    }

    // hatch sync [push|pull|all] [--repo owner/tickets] [--dry-run]
    static func sync(_ c: Context) throws {
        let p = try c.project()
        guard let repo = c.args.option("repo") ?? p.config?.ticketsRepo, !repo.isEmpty else {
            throw CLIError("This project has no tickets repository. Set one in Project settings, or pass --repo owner/name.")
        }
        let engine = SyncEngine(store: c.store, tracker: try tracker(c))
        let mode = c.args.pos(1) ?? "all"
        var parts: [String] = []
        if mode == "push" || mode == "all" {
            parts.append("push: \(try engine.pushPending(repo: repo))")
            // Screenshots to the tickets repo (decision M3), then the comments that show them.
            let sent = try engine.uploadAttachments(repo: repo, projectId: p.id, branch: p.config?.repo(.tickets)?.branch ?? "main")
            if sent > 0 { parts.append("screenshots: \(sent), comments: \(try engine.pushPending(repo: repo))") }
        }
        if mode == "pull" || mode == "all" { parts.append("pull: \(try engine.pull(repo: repo, projectId: p.id))") }
        let counts = try c.store.syncCounts()
        c.out.emit(["pending": .int(counts.pending), "failed": .int(counts.failed)], text: parts.joined(separator: "\n") + "\nQueue: \(counts.pending) pending, \(counts.failed) failed.")
    }

    // hatch serve  -> the local API for the Stage app
    static func serve(_ c: Context) throws {
        let server = StageServer(store: c.store, port: UInt16(c.args.option("port") ?? "0") ?? 0)
        try server.start()
        print("Hatch Stage API on http://127.0.0.1:\(server.port)  (token in \(HatchPaths.current().tokenFile.path))")
        RunLoop.main.run()
    }

    // hatch import-labs --file EchoLab/State/lab-state.json [--enqueue]
    static func importLabs(_ c: Context) throws {
        let p = try c.project()
        guard let file = c.args.option("file") else { throw CLIError("Usage: hatch import-labs --file <lab-state.json> [--catalog <EchoLab/Sources/EchoLab folder>] [--enqueue]") }
        var options = ImportOptions(enqueueSync: c.args.flag("enqueue"))
        if let cat = c.args.option("catalog") { options = ImportOptions(enqueueSync: options.enqueueSync, catalog: LabCatalog.load(echoLabSources: URL(fileURLWithPath: cat))) }
        let report = try LabImporter.importState(file: URL(fileURLWithPath: file), project: p, store: c.store, options: options)
        c.out.emit(["report": .string("\(report)")], text: "\(report)")
    }

    // hatch spec index [--dir <folder>]  |  hatch spec export --from <Areas dir> --to <dir>
    // Without --dir, the Spec of the project's notebook clone is indexed.
    static func spec(_ c: Context) throws {
        switch c.args.pos(1) {
        case "index":
            let project = try c.project()
            let r: SpecIndexResult
            if let dir = c.args.option("dir") {
                r = try SpecIndexer.index(directory: URL(fileURLWithPath: dir), project: project, store: c.store)
            } else if let found = try SpecIndexer.indexNotebook(project: project, store: c.store) {
                r = found
            } else {
                throw CLIError("\(project.name) has no notebook clone on this Mac. Pass --dir <folder with the Spec files>.")
            }
            c.out.emit(["result": .string("\(r)")], text: "\(r)")
        case "export":
            guard let from = c.args.option("from"), let to = c.args.option("to") else { throw CLIError("Usage: hatch spec export --from <Areas folder> --to <folder>") }
            let areas = SpecExporter.extractAll(areasDirectory: URL(fileURLWithPath: from))
            let files = try SpecExporter.write(areas, to: URL(fileURLWithPath: to))
            c.out.emit(["areas": .int(areas.count)], text: "Wrote \(files.count) spec file(s) for \(areas.count) areas.")
        default: throw CLIError("Usage: hatch spec index|export ...")
        }
    }

    // hatch workspace list|remove #151
    static func workspace(_ c: Context) throws {
        let manager = WorkspaceManager(store: c.store)
        switch c.args.pos(1) {
        case "list":
            let spaces = try manager.list().filter { $0.state == "active" }
            c.out.emit(.array(spaces.map { ["ticket": .int($0.ticketId), "path": .string($0.path), "branch": .string($0.branch)] }), text: spaces.isEmpty ? "No active workspaces." : spaces.map { "\($0.branch)  \($0.path)" }.joined(separator: "\n"))
        case "remove":
            let t = try c.ticket(c.args.pos(2))
            for ws in try manager.list(ticketId: t.id) { try manager.remove(ws, deleteBranch: c.args.flag("all")) }
            c.out.emit(["removed": .string(t.displayNumber)], text: "Removed the workspaces of \(t.displayNumber).")
        default: throw CLIError("Usage: hatch workspace list|remove #151 [--all]")
        }
    }

    // hatch preview #144 #146 ...  -> merges the tickets' branches into a throwaway Preview branch
    static func preview(_ c: Context) throws {
        let tickets = try c.args.positionals.dropFirst().map { try c.store.resolve($0) }
        guard let first = tickets.first else { throw CLIError("Usage: hatch preview #144 #146 ...") }
        guard let app = try c.store.repo(projectId: first.projectId, role: .app) else { throw CLIError("The project has no app repository configured.") }
        let result = try PreviewBuilder(workspaces: WorkspaceManager(store: c.store)).build(repo: app, tickets: tickets)
        if let conflict = result.conflict {
            let a = try c.store.ticket(id: conflict.ticketId)?.displayNumber ?? "?", b = try c.store.ticket(id: conflict.againstTicketId)?.displayNumber ?? "?"
            c.out.emit(["clean": false, "pair": [.string(a), .string(b)], "files": .array(conflict.files.map { .string($0) })], text: "\(a) conflicts with \(b) in \(conflict.files.joined(separator: ", ")). Options: drop one, stack them, or ask an agent to resolve.")
            exit(2)
        }
        c.out.emit(["clean": true, "preview": .string(result.preview.name), "path": .string(result.worktreePath ?? "")], text: "\(result.preview.name) merged cleanly at \(result.worktreePath ?? "?").")
    }
}
