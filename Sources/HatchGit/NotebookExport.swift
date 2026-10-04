import Foundation
import HatchCore

/// Keeps a project's notebook in step with the database (decisions PS9, PS14). The database is the working record:
/// fast, searchable and complete. The notebook is the lasting one: plain files anyone can read later. This brings
/// decision files the database lacks back in (picking up on a new Mac), writes decisions that have no file yet, and
/// refreshes NOW.md and the decision index. No model is involved, so it costs no tokens.
public enum NotebookExport {
    public struct Result: Equatable, Sendable {
        public var imported = 0
        public var decisionsWritten = 0
        public var nowUpdated = false
        public var committed = false
        public var pushed = false
        /// Decision files that name a ticket this Mac does not know yet; they are imported once the ticket syncs.
        public var waitingForTickets: [String] = []
    }

    /// Nil when the project has no notebook clone on this Mac.
    @discardableResult
    public static func run(store: HatchStore, projectId: Int, token: String?, push: Bool = true,
                           git: GitRunner = ProcessGit()) throws -> Result? {
        guard let project = try store.project(id: projectId),
              let dir = try store.repo(projectId: projectId, role: .notebook)?.localPath,
              FileManager.default.fileExists(atPath: dir + "/.git") else { return nil }
        var result = Result()
        let fm = FileManager.default
        let decisionsURL = URL(fileURLWithPath: dir).appendingPathComponent(Notebook.decisionsDir)

        // 1. Files the database does not have: written on another Mac, or before this database existed.
        var known = try store.decisionFilePaths(projectId: projectId)
        let files = ((try? fm.contentsOfDirectory(atPath: decisionsURL.path)) ?? []).filter { $0.hasSuffix(".md") && $0 != "README.md" }.sorted()
        for name in files {
            let path = "\(Notebook.decisionsDir)/\(name)"
            guard !known.contains(path), let text = try? String(contentsOf: decisionsURL.appendingPathComponent(name), encoding: .utf8),
                  let parsed = Notebook.parseDecision(text) else { continue }
            guard let ticket = try store.ticket(ghNumber: parsed.ticketNumber, projectId: projectId) else {
                result.waitingForTickets.append(path); continue
            }
            try store.recordDecision(ticketId: ticket.id, kind: parsed.kind, title: parsed.title, summary: parsed.summary, area: parsed.area,
                                     reason: parsed.reason, specCodes: parsed.specCodes, filePath: path, at: parsed.decided)
            known.insert(path)
            result.imported += 1
        }

        // 2. Decisions without a file, oldest first so a replacement can point at the file it replaces.
        var written: [(id: Int, path: String)] = []
        var taken = known.union(files.map { "\(Notebook.decisionsDir)/\($0)" })
        for d in try store.decisionRecords(projectId: projectId, pendingExport: true).reversed() {
            let path = Notebook.decisionPath(d, taken: taken)
            let replaces = try d.replacesId.flatMap { try store.decisionRecord(id: $0)?.filePath }
            try NotebookWriter.write([path: Notebook.decisionFile(d, replacesPath: replaces)], in: dir)
            taken.insert(path)
            written.append((d.id, path))
        }
        // A decision's kind can be changed later; its file follows. Nothing else in a written decision changes.
        for d in try store.decisionRecords(projectId: projectId) {
            guard let path = d.filePath, let text = try? String(contentsOfFile: dir + "/" + path, encoding: .utf8),
                  let parsed = Notebook.parseDecision(text), parsed.kind != d.kind else { continue }
            try NotebookWriter.write([path: text.replacingOccurrences(of: "kind: \(parsed.kind.rawValue)\n", with: "kind: \(d.kind.rawValue)\n")], in: dir)
        }
        result.decisionsWritten = written.count

        // 3. The index and NOW.md, made from the database. NOW.md is compared by hash, so an unchanged state writes nothing.
        let all = try store.decisionRecords(projectId: projectId)
        let withPaths = all.map { d -> DecisionRecord in
            var d = d
            if d.filePath == nil { d.filePath = written.first { $0.id == d.id }?.path }
            return d
        }
        try NotebookWriter.write(["\(Notebook.decisionsDir)/README.md": Notebook.decisionIndex(withPaths)], in: dir)
        let open = try store.tickets(TicketFilter(projectId: projectId)).filter { !$0.status.isTerminal }
            .sorted { ($0.ghNumber ?? $0.id) < ($1.ghNumber ?? $1.id) }
        let now = Notebook.now(projectName: project.name, open: open,
                               decisions: withPaths.prefix(10).map { ($0.ticketNumber, $0.title.isEmpty ? $0.summary : $0.title) })
        let nowChanged = try stableHash(now) != store.notebookNowHash(projectId: projectId)
        if nowChanged { try NotebookWriter.write(["NOW.md": now], in: dir) }

        // 4. One commit for the lot, then mark the decisions written: a failed commit leaves them queued.
        result.committed = try NotebookWriter.commit(commitMessage(result, nowChanged: nowChanged), in: dir, git: git)
        for w in written { try store.markDecisionExported(w.id, filePath: w.path) }
        result.nowUpdated = nowChanged && result.committed

        // 5. Push whatever is ahead of the remote, including commits a failed push left behind.
        var pushError: String?
        if push, (Int((try? git.git(["rev-list", "--count", "@{u}..HEAD"], in: dir)) ?? "1") ?? 1) > 0 {
            do { try NotebookWriter.push(in: dir, token: token, git: git); result.pushed = true }
            catch { pushError = "\(error)" }
        }
        try store.setNotebookState(projectId: projectId, nowHash: stableHash(now), pushed: result.pushed, error: pushError)
        return result
    }

    /// A hash that is the same on every run (Swift's `hashValue` is not), so NOW.md is only rewritten when it changed.
    static func stableHash(_ text: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    static func commitMessage(_ r: Result, nowChanged: Bool) -> String {
        var parts: [String] = []
        if r.decisionsWritten > 0 { parts.append("Record \(r.decisionsWritten) decision\(r.decisionsWritten == 1 ? "" : "s")") }
        if nowChanged { parts.append(parts.isEmpty ? "Update NOW.md" : "update NOW.md") }
        return parts.isEmpty ? "Update the notebook" : parts.joined(separator: ", ")
    }
}
