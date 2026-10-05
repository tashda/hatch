import Foundation

// MARK: Events, notes, questions, links, attachments, search

public extension HatchStore {
    func record(_ ticketId: Int, actor: String, kind: String, payload: JSONValue = [:]) throws {
        try db.execute("INSERT INTO event(ticket_id, at, actor, kind, payload) VALUES(?,?,?,?,?)",
                       [.int(ticketId), .date(now()), .text(actor), .text(kind), .text(payload.jsonString())])
    }

    func events(ticketId: Int, kinds: [String]? = nil) throws -> [Event] {
        var sql = "SELECT * FROM event WHERE ticket_id = ?", params: [SQLValue] = [.int(ticketId)]
        if let kinds, !kinds.isEmpty { sql += " AND kind IN (\(kinds.map { _ in "?" }.joined(separator: ",")))"; params += kinds.map { .text($0) } }
        return try db.query(sql + " ORDER BY at, id", params) {
            Event(id: $0.int("id")!, ticketId: $0.int("ticket_id")!, at: $0.date("at")!, actor: $0.string("actor")!,
                  kind: $0.string("kind")!, payload: JSONValue.parse($0.string("payload") ?? "{}"))
        }
    }

    /// The latest events across tickets, newest first, for the footer's activity line and its card.
    func recentEvents(projectId: Int? = nil, kinds: [String] = ["created", "status", "take", "release", "question", "answer"],
                      limit: Int = 10) throws -> [(event: Event, ticket: Ticket)] {
        var sql = "SELECT e.id AS eid, e.ticket_id AS etid, e.at AS eat, e.actor AS eactor, e.kind AS ekind, e.payload AS epayload, t.* FROM event e JOIN ticket t ON t.id = e.ticket_id"
        var params: [SQLValue] = []
        var conditions: [String] = []
        if !kinds.isEmpty { conditions.append("e.kind IN (\(kinds.map { _ in "?" }.joined(separator: ",")))"); params += kinds.map { .text($0) } }
        if let projectId { conditions.append("t.project_id = ?"); params.append(.int(projectId)) }
        if !conditions.isEmpty { sql += " WHERE " + conditions.joined(separator: " AND ") }
        params.append(.int(limit))
        return try db.query(sql + " ORDER BY e.at DESC, e.id DESC LIMIT ?", params) {
            (Event(id: $0.int("eid")!, ticketId: $0.int("etid")!, at: $0.date("eat")!, actor: $0.string("eactor")!,
                   kind: $0.string("ekind")!, payload: JSONValue.parse($0.string("epayload") ?? "{}")), HatchStore.ticket($0))
        }
    }

    // Notes

    @discardableResult
    func addNote(_ ticketId: Int, kind: NoteKind, author: String, body: String, context: JSONValue? = nil, ghCommentId: Int? = nil, at: Date? = nil) throws -> Note {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw StoreError.invalid("A note cannot be empty.") }
        return try db.transaction {
            guard let t = try ticket(id: ticketId) else { throw StoreError.notFound("ticket \(ticketId)") }
            try db.execute("INSERT INTO note(ticket_id, kind, author, body, at, gh_comment_id, context_json) VALUES(?,?,?,?,?,?,?)",
                           [.int(ticketId), .text(kind.rawValue), .text(author), .text(text), .date(at ?? now()), .opt(ghCommentId), .opt(context?.jsonString())])
            let id = Int(db.lastInsertRowID)
            try db.execute("UPDATE ticket SET updated_at = ? WHERE id = ?", [.date(now()), .int(ticketId)])
            try indexTicket(ticketId)
            try record(ticketId, actor: author, kind: "note", payload: ["kind": .string(kind.rawValue), "note": .int(id)])
            // An Ask moves the turn to the agent (decision F4); an Instruction on a Proposal becomes a revision request.
            if kind == .ask || kind == .instruction, t.status == .yourCall, t.type != .question {
                try move(ticketId, to: .revising, actor: .owner, reason: kind == .ask ? "ask" : "instruction")
            }
            if ghCommentId == nil && kind != .system && t.status != .draft {
                try enqueue(op: "issue.comment", ticketId: ticketId, payload: ["note": .int(id), "body": .string(Self.commentBody(kind: kind, author: author, text: text))])
            }
            return try notes(ticketId: ticketId).first { $0.id == id }!
        }
    }

    static func commentBody(kind: NoteKind, author: String, text: String) -> String {
        switch kind {
        case .comment: return text
        case .agent: return "**\(author)**\n\n\(text)"
        default: return "**\(kind.rawValue.capitalized) from \(author)**\n\n\(text)"
        }
    }

    func notes(ticketId: Int) throws -> [Note] {
        try db.query("SELECT * FROM note WHERE ticket_id = ? ORDER BY at, id", [.int(ticketId)]) {
            Note(id: $0.int("id")!, ticketId: $0.int("ticket_id")!, kind: NoteKind(rawValue: $0.string("kind")!) ?? .comment,
                 author: $0.string("author")!, body: $0.string("body")!, at: $0.date("at")!, ghCommentId: $0.int("gh_comment_id"),
                 context: $0.string("context_json").map(JSONValue.parse))
        }
    }

    // Questions (Needs answers, decision E4)

    @discardableResult
    func ask(_ ticketId: Int, text: String, suggestions: [String] = [], by: String, actor: Actor = .agent,
             purpose: String? = nil, payload: JSONValue? = nil) throws -> Question {
        try db.transaction {
            guard let t = try ticket(id: ticketId) else { throw StoreError.notFound("ticket \(ticketId)") }
            try db.execute("INSERT INTO question(ticket_id, text, suggestions_json, asked_by, at, purpose, payload) VALUES(?,?,?,?,?,?,?)",
                           [.int(ticketId), .text(text), .text(JSONValue.array(suggestions.map { .string($0) }).jsonString()), .text(by), .date(now()),
                            .opt(purpose), .opt(payload?.jsonString())])
            let id = Int(db.lastInsertRowID)
            try record(ticketId, actor: by, kind: "question", payload: ["question": .int(id), "text": .string(text)])
            if t.status != .needsAnswers && Workflow.isAllowed(type: t.type, from: t.status, to: .needsAnswers, actor: actor) {
                try move(ticketId, to: .needsAnswers, actor: actor, reason: "question")
            }
            return try questions(ticketId: ticketId).first { $0.id == id }!
        }
    }

    func questions(ticketId: Int, openOnly: Bool = false) throws -> [Question] {
        try db.query("SELECT * FROM question WHERE ticket_id = ?\(openOnly ? " AND answer IS NULL" : "") ORDER BY at, id", [.int(ticketId)]) {
            Question(id: $0.int("id")!, ticketId: $0.int("ticket_id")!, text: $0.string("text")!,
                     suggestions: (JSONValue.parse($0.string("suggestions_json") ?? "[]").arrayValue ?? []).compactMap { $0.stringValue },
                     askedBy: $0.string("asked_by")!, at: $0.date("at")!, answer: $0.string("answer"), answeredAt: $0.date("answered_at"),
                     purpose: $0.string("purpose"), payload: $0.string("payload").map(JSONValue.parse))
        }
    }

    /// The answers Hatch offers when an agent stopped twice before handing in (decision WF-B3, gap G27).
    static let agentStoppedTryAgain = "Try again"
    static let agentStoppedStop = "Stop working on it"

    /// Records an answer. When the last open question is answered, Hatch (not an agent) moves the ticket on: back to the
    /// work that asked, so the agent carries on where it stopped (WF-Q4); back to Checking when Iris asked, so she checks
    /// again with the answers (WF-Q2); otherwise to Ready.
    @discardableResult
    func answer(questionId: Int, text: String, by: String = "owner") throws -> Ticket {
        try db.transaction {
            guard let ticketId = try db.query("SELECT ticket_id FROM question WHERE id = ?", [.int(questionId)], map: { $0.int("ticket_id") }).first ?? nil else {
                throw StoreError.notFound("question \(questionId)")
            }
            try db.execute("UPDATE question SET answer = ?, answered_at = ? WHERE id = ?", [.text(text), .date(now()), .int(questionId)])
            try record(ticketId, actor: by, kind: "answer", payload: ["question": .int(questionId)])
            try db.execute("UPDATE ticket SET updated_at = ? WHERE id = ?", [.date(now()), .int(ticketId)])
            try indexTicket(ticketId)
            let asked = try questions(ticketId: ticketId).first { $0.id == questionId }
            // Answers Hatch understands are applied now: an area, a path, a duplicate, a split (section X).
            if let asked, try !actOnAnswer(asked, text: text) { return try ticket(id: ticketId)! }
            let t = try ticket(id: ticketId)!
            guard t.status == .needsAnswers, try questions(ticketId: ticketId, openOnly: true).isEmpty else { return t }
            let from = try statusBeforeQuestions(ticketId)
            // Iris filed the ticket before she asked. The answer is applied here and agents read it in their brief, so she
            // runs again only when an answer could change what the ticket is (decision IR13).
            if from == .checking, try roundQuestions(ticketId).allSatisfy({ QuestionPurpose.isActedOn($0.purpose) || $0.payload?["rerun"]?.boolValue != true }) {
                return try move(ticketId, to: .ready, actor: .hatch, reason: "answered; filed")
            }
            if asked?.askedBy == "Hatch", text == Self.agentStoppedStop {
                // Parked where the work was, so Resume starts it again later.
                if let from, Workflow.isAllowed(type: t.type, from: .needsAnswers, to: from, actor: .hatch) {
                    try move(ticketId, to: from, actor: .hatch, reason: "the owner stopped the work")
                }
                return try move(ticketId, to: .parked, actor: .owner, reason: "stopped after the agent failed twice")
            }
            if let from, from != .needsAnswers, Workflow.isAllowed(type: t.type, from: .needsAnswers, to: from, actor: .hatch) {
                let reason = from == .checking ? "answered; Iris checks again" : "answered; the work carries on"
                return try move(ticketId, to: from, actor: .hatch, reason: reason)
            }
            return try move(ticketId, to: .ready, actor: .hatch, reason: "all questions answered")
        }
    }

    /// The questions of the latest round: asked since the ticket entered the status it went to Needs answers from.
    func roundQuestions(_ ticketId: Int) throws -> [Question] {
        let moves = try events(ticketId: ticketId, kinds: ["status"])
        guard let i = moves.lastIndex(where: { $0.payload["to"]?.stringValue == Status.needsAnswers.rawValue }) else {
            return try questions(ticketId: ticketId)
        }
        let since = i > 0 ? moves[i - 1].at : .distantPast
        return try questions(ticketId: ticketId).filter { $0.at >= since }
    }

    /// Where the ticket was when it last went to Needs answers, from its history.
    func statusBeforeQuestions(_ ticketId: Int) throws -> Status? {
        let moves = try events(ticketId: ticketId, kinds: ["status"])
        guard let last = moves.last(where: { $0.payload["to"]?.stringValue == Status.needsAnswers.rawValue }) else { return nil }
        return last.payload["from"]?.stringValue.flatMap(Status.init(rawValue:))
    }

    // Links (decision E5)

    /// `by` is who made the link (history says so); `why` is the one line a link made by Iris carries, recorded on both tickets.
    func link(from: Int, to: Int, kind: LinkKind, by: String = "owner", why: String? = nil) throws {
        guard from != to else { throw StoreError.invalid("A ticket cannot link to itself.") }
        try db.execute("INSERT OR IGNORE INTO ticket_link(from_id, to_id, kind) VALUES(?,?,?)", [.int(from), .int(to), .text(kind.rawValue)])
        var payload: [String: JSONValue] = ["to": .int(to), "kind": .string(kind.rawValue)]
        if let why, !why.isEmpty { payload["why"] = .string(why) }
        try record(from, actor: by, kind: "link", payload: .object(payload))
        if let why, !why.isEmpty {
            try record(to, actor: by, kind: "link", payload: .object(["from": .int(from), "kind": .string(kind.rawValue), "why": .string(why)]))
        }
        // A ticket under a Goal is a sub-issue of the Goal's issue on GitHub (decision SW2).
        if kind == .parent { try enqueueParent(child: from, parent: to) }
    }

    func unlink(from: Int, to: Int, kind: LinkKind) throws {
        try db.execute("DELETE FROM ticket_link WHERE from_id = ? AND to_id = ? AND kind = ?", [.int(from), .int(to), .text(kind.rawValue)])
    }

    /// Links in both directions, with the direction made explicit.
    func links(ticketId: Int) throws -> [(link: TicketLink, outgoing: Bool)] {
        let out = try db.query("SELECT * FROM ticket_link WHERE from_id = ?", [.int(ticketId)]) { TicketLink(fromId: $0.int("from_id")!, toId: $0.int("to_id")!, kind: LinkKind(rawValue: $0.string("kind")!) ?? .related) }.map { ($0, true) }
        let inc = try db.query("SELECT * FROM ticket_link WHERE to_id = ?", [.int(ticketId)]) { TicketLink(fromId: $0.int("from_id")!, toId: $0.int("to_id")!, kind: LinkKind(rawValue: $0.string("kind")!) ?? .related) }.map { ($0, false) }
        return out + inc
    }

    /// Open tickets that block this one (a Blocks link pointing at it).
    func openBlockers(ticketId: Int) throws -> [Ticket] {
        try db.query("""
            SELECT t.* FROM ticket_link l JOIN ticket t ON t.id = l.from_id
            WHERE l.to_id = ? AND l.kind = 'blocks' AND t.status NOT IN ('done','dropped','merged')
            """, [.int(ticketId)]) { HatchStore.ticket($0) }
    }

    // Attachments (decision M3)

    @discardableResult
    func addAttachment(_ ticketId: Int, path: String, sha: String? = nil, kind: String = "screenshot", caption: String? = nil) throws -> Attachment {
        try db.execute("INSERT INTO attachment(ticket_id, path, sha, kind, caption, at) VALUES(?,?,?,?,?,?)",
                       [.int(ticketId), .text(path), .opt(sha), .text(kind), .opt(caption), .date(now())])
        try record(ticketId, actor: "owner", kind: "attachment", payload: ["path": .string(path)])
        return try attachments(ticketId: ticketId).last!
    }

    static func attachment(_ r: Row) -> Attachment {
        Attachment(id: r.int("id")!, ticketId: r.int("ticket_id")!, path: r.string("path")!, sha: r.string("sha"),
                   kind: r.string("kind") ?? "screenshot", caption: r.string("caption"), at: r.date("at")!,
                   remotePath: r.string("remote_path"), uploadedSha: r.string("uploaded_sha"), uploadError: r.string("upload_error"))
    }

    // MARK: Uploading screenshots (decision M3)

    /// The folder relative attachment paths are under: the Hatch folder, next to the database. Nil for an in-memory store.
    var attachmentsRoot: URL? {
        db.path.isEmpty || db.path == ":memory:" ? nil : URL(fileURLWithPath: db.path).deletingLastPathComponent()
    }

    /// Where Hatch keeps the HTML of a ticket's web draft, copied there at `hatch offer` so it outlives the agent's
    /// workspace (gap G11). Nil for an in-memory store.
    func sketchFolder(ticketId: Int) -> URL? {
        attachmentsRoot?.appendingPathComponent("sketches/\(ticketId)", isDirectory: true)
    }

    /// The file of an attachment on this Mac.
    func attachmentFile(_ a: Attachment, root: URL? = nil) -> URL? {
        if a.path.hasPrefix("/") { return URL(fileURLWithPath: a.path) }
        return (root ?? attachmentsRoot)?.appendingPathComponent(a.path)
    }

    /// Screenshots not yet in the tickets repository, or changed since: only for tickets that have an issue.
    func pendingUploads(projectId: Int? = nil) throws -> [Attachment] {
        var sql = """
            SELECT a.* FROM attachment a JOIN ticket t ON t.id = a.ticket_id
            WHERE t.gh_number IS NOT NULL AND (a.remote_path IS NULL OR (a.sha IS NOT NULL AND a.uploaded_sha IS NOT a.sha))
            """
        var params: [SQLValue] = []
        if let projectId { sql += " AND t.project_id = ?"; params.append(.int(projectId)) }
        return try db.query(sql + " ORDER BY a.id", params, map: Self.attachment)
    }

    func markAttachmentUploaded(_ id: Int, remotePath: String, sha: String?) throws {
        try db.execute("UPDATE attachment SET remote_path = ?, uploaded_sha = ?, upload_error = NULL WHERE id = ?",
                       [.text(remotePath), .opt(sha), .int(id)])
    }

    /// Keeps the failure for the screenshot's badge; the Log gets an event only when the error is new.
    func markAttachmentUploadFailed(_ id: Int, ticketId: Int, error: String) throws {
        let before = try db.query("SELECT upload_error FROM attachment WHERE id = ?", [.int(id)]) { $0.string("upload_error") }.first ?? nil
        try db.execute("UPDATE attachment SET upload_error = ? WHERE id = ?", [.text(error), .int(id)])
        if before != error { try record(ticketId, actor: "hatch", kind: "attachment-upload-failed", payload: ["error": .string(error)]) }
    }

    /// The issue comment that shows an uploaded screenshot, queued like every comment Hatch posts.
    func enqueueScreenshotComment(ticketId: Int, caption: String?, imageURL: String) throws {
        let alt = (caption ?? "screenshot").replacingOccurrences(of: "]", with: ")")
        _ = try enqueue(op: "issue.comment", ticketId: ticketId,
                        payload: ["body": .string(Self.commentBody(kind: .system, author: "Hatch", text: "Screenshot\n\n![\(alt)](\(imageURL))"))])
        try record(ticketId, actor: "hatch", kind: "attachment-uploaded", payload: ["url": .string(imageURL)])
    }

    /// A screenshot's file changed (marked up): its checksum follows, so a later upload sends the new image.
    func setAttachmentSha(_ id: Int, sha: String) throws {
        try db.execute("UPDATE attachment SET sha = ? WHERE id = ?", [.text(sha), .int(id)])
    }

    func attachments(ticketId: Int) throws -> [Attachment] {
        try db.query("SELECT * FROM attachment WHERE ticket_id = ? ORDER BY at, id", [.int(ticketId)]) {
            Self.attachment($0)
        }
    }

    // Search (decisions E2 and M4)

    static let stopWords: Set<String> = ["the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "is", "it", "this", "that", "with", "as", "at", "be", "by", "we", "are", "was", "not", "but", "from", "when", "how", "too", "i"]

    static func tokens(_ text: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for raw in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let w = String(raw)
            if w.count < 2 || stopWords.contains(w) || seen.contains(w) { continue }
            seen.insert(w); out.append(w)
        }
        return out
    }

    /// A user query: every word must match (prefix match on each).
    static func ftsQuery(_ text: String) -> String? {
        let t = tokens(text)
        return t.isEmpty ? nil : t.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    /// Re-reads the ticket and its notes into the search index.
    func indexTicket(_ id: Int) throws {
        guard let t = try ticket(id: id) else { return }
        let notes = try db.query("SELECT body FROM note WHERE ticket_id = ? ORDER BY at", [.int(id)]) { $0.string("body") ?? "" }.joined(separator: "\n")
        let answers = try db.query("SELECT text, answer FROM question WHERE ticket_id = ?", [.int(id)]) { "\($0.string("text") ?? "") \($0.string("answer") ?? "")" }.joined(separator: "\n")
        try db.execute("DELETE FROM ticket_fts WHERE ticket_id = ?", [.int(id)])
        try db.execute("INSERT INTO ticket_fts(title, body, notes, ticket_id) VALUES(?,?,?,?)", [.text(t.title), .text(t.body), .text(notes + "\n" + answers), .int(id)])
    }

    /// Free, local, no tokens: tickets that look like this text (composer hints and Iris's candidate list).
    func similarTickets(projectId: Int?, title: String, body: String = "", excluding: Int? = nil, limit: Int = 8) throws -> [(ticket: Ticket, score: Double)] {
        let words = Array(Self.tokens(title + " " + body).prefix(14))
        guard !words.isEmpty else { return [] }
        let match = words.map { "\"\($0)\"" }.joined(separator: " OR ")
        var sql = "SELECT t.*, bm25(ticket_fts) AS score FROM ticket_fts JOIN ticket t ON t.id = ticket_fts.ticket_id WHERE ticket_fts MATCH ?"
        var params: [SQLValue] = [.text(match)]
        if let projectId { sql += " AND t.project_id = ?"; params.append(.int(projectId)) }
        if let excluding { sql += " AND t.id != ?"; params.append(.int(excluding)) }
        sql += " ORDER BY score LIMIT ?"; params.append(.int(limit))
        return try db.query(sql, params) { (HatchStore.ticket($0), -($0.double("score") ?? 0)) }
    }

    // Specs (decision L3)

    func upsertSpecItems(projectId: Int, items: [(code: String, area: String?, text: String, source: String?)]) throws {
        try db.transaction {
            for i in items {
                try db.execute("""
                    INSERT INTO spec_item(project_id, code, area, text, source) VALUES(?,?,?,?,?)
                    ON CONFLICT(project_id, code) DO UPDATE SET area = excluded.area, text = excluded.text, source = excluded.source
                    """, [.int(projectId), .text(i.code), .opt(i.area), .text(i.text), .opt(i.source)])
                let id = try db.query("SELECT id FROM spec_item WHERE project_id = ? AND code = ?", [.int(projectId), .text(i.code)]) { $0.int("id")! }.first!
                try db.execute("DELETE FROM spec_fts WHERE spec_id = ?", [.int(id)])
                try db.execute("INSERT INTO spec_fts(code, area, text, spec_id) VALUES(?,?,?,?)", [.text(i.code), .opt(i.area), .text(i.text), .int(id)])
            }
        }
    }

    func specItems(projectId: Int, area: String? = nil) throws -> [SpecItem] {
        var sql = "SELECT * FROM spec_item WHERE project_id = ?", params: [SQLValue] = [.int(projectId)]
        if let area { sql += " AND area = ?"; params.append(.text(area)) }
        return try db.query(sql + " ORDER BY code", params, map: Self.specItem)
    }

    func searchSpec(projectId: Int, query: String, limit: Int = 8) throws -> [SpecItem] {
        let words = Array(Self.tokens(query).prefix(14))
        guard !words.isEmpty else { return [] }
        return try db.query("""
            SELECT s.* FROM spec_fts JOIN spec_item s ON s.id = spec_fts.spec_id
            WHERE spec_fts MATCH ? AND s.project_id = ? ORDER BY bm25(spec_fts) LIMIT ?
            """, [.text(words.map { "\"\($0)\"" }.joined(separator: " OR ")), .int(projectId), .int(limit)], map: Self.specItem)
    }

    private static func specItem(_ r: Row) -> SpecItem {
        SpecItem(id: r.int("id")!, projectId: r.int("project_id")!, code: r.string("code")!, area: r.string("area"), text: r.string("text")!, source: r.string("source"))
    }

    // Agent runs and cost (decision K5)

    /// Starts a run record. Provider, model and task (an `AgentRole` raw value) say what did the work, for Usage and Reports.
    func startRun(ticketId: Int?, agent: String, step: String?, provider: String? = nil, model: String? = nil, role: String? = nil) throws -> Int {
        try db.execute("INSERT INTO agent_run(ticket_id, agent, step, started_at, provider, model, role) VALUES(?,?,?,?,?,?,?)",
                       [.opt(ticketId), .text(agent), .opt(step), .date(now()), .opt(provider), .opt(model), .opt(role)])
        return Int(db.lastInsertRowID)
    }

    func endRun(_ id: Int, tokensIn: Int, tokensOut: Int, outcome: String, cacheTokens: Int = 0) throws {
        try db.execute("UPDATE agent_run SET tokens_in = ?, tokens_out = ?, ended_at = ?, outcome = ?, cache_tokens = ? WHERE id = ?",
                       [.int(tokensIn), .int(tokensOut), .date(now()), .text(outcome), .int(cacheTokens), .int(id)])
    }

    /// Records a run that already finished, at its own times: for imported history and the demo data.
    @discardableResult
    func recordRun(ticketId: Int?, agent: String, step: String?, provider: String?, model: String?, role: String?,
                   tokensIn: Int, tokensOut: Int, cacheTokens: Int = 0, outcome: String, startedAt: Date, endedAt: Date) throws -> Int {
        try db.execute("""
            INSERT INTO agent_run(ticket_id, agent, step, started_at, ended_at, provider, model, role, tokens_in, tokens_out, cache_tokens, outcome)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
            """, [.opt(ticketId), .text(agent), .opt(step), .date(startedAt), .date(endedAt), .opt(provider), .opt(model), .opt(role),
                  .int(tokensIn), .int(tokensOut), .int(cacheTokens), .text(outcome)])
        return Int(db.lastInsertRowID)
    }

    /// Run records with what they used, for Usage and Reports. Aggregation is done by the caller; a day's runs are few.
    func runRecords(since: Date, until: Date? = nil, projectId: Int? = nil) throws -> [RunRecord] {
        var sql = """
            SELECT r.*, t.project_id AS pid, t.area AS tarea, t.gh_number AS tgh, t.title AS ttitle, t.type AS ttype
            FROM agent_run r LEFT JOIN ticket t ON t.id = r.ticket_id WHERE r.started_at >= ?
            """
        var params: [SQLValue] = [.date(since)]
        if let until { sql += " AND r.started_at < ?"; params.append(.date(until)) }
        if let projectId { sql += " AND t.project_id = ?"; params.append(.int(projectId)) }
        return try db.query(sql + " ORDER BY r.started_at", params) {
            RunRecord(id: $0.int("id")!, ticketId: $0.int("ticket_id"), ticketNumber: $0.int("tgh").map { "#\($0)" },
                      ticketTitle: $0.string("ttitle"), ticketType: $0.string("ttype").flatMap(TicketType.init(rawValue:)),
                      area: $0.string("tarea"), projectId: $0.int("pid"), agent: $0.string("agent") ?? "",
                      provider: $0.string("provider"), model: $0.string("model"), role: $0.string("role"),
                      tokensIn: $0.int("tokens_in") ?? 0, tokensOut: $0.int("tokens_out") ?? 0, cacheTokens: $0.int("cache_tokens") ?? 0,
                      startedAt: $0.date("started_at")!, endedAt: $0.date("ended_at"), outcome: $0.string("outcome"))
        }
    }

    func tokenTotals(ticketId: Int? = nil, since: Date? = nil) throws -> (input: Int, output: Int) {
        var sql = "SELECT COALESCE(SUM(tokens_in),0) AS i, COALESCE(SUM(tokens_out),0) AS o FROM agent_run WHERE 1=1", params: [SQLValue] = []
        if let ticketId { sql += " AND ticket_id = ?"; params.append(.int(ticketId)) }
        if let since { sql += " AND started_at >= ?"; params.append(.date(since)) }
        return try db.query(sql, params) { ($0.int("i") ?? 0, $0.int("o") ?? 0) }.first ?? (0, 0)
    }

    // Decisions (Decisions library, decision N1)

    /// A decision with only a summary (imports and older callers): kind and title come from the ticket.
    @discardableResult
    func recordDecision(ticketId: Int, summary: String, specCodes: [String] = []) throws -> Int {
        let t = try ticket(id: ticketId)
        return try recordDecision(ticketId: ticketId, kind: t.map { DecisionKind.default(for: $0.type) } ?? .design,
                                  title: t?.title ?? "", summary: summary, area: t?.area, specCodes: specCodes)
    }

    func decisions(projectId: Int? = nil) throws -> [(ticket: Ticket, summary: String, specCodes: [String], at: Date)] {
        var sql = "SELECT d.summary, d.spec_codes_json, d.at AS dat, t.* FROM decision d JOIN ticket t ON t.id = d.ticket_id"
        var params: [SQLValue] = []
        if let projectId { sql += " WHERE t.project_id = ?"; params.append(.int(projectId)) }
        return try db.query(sql + " ORDER BY d.at DESC", params) {
            (HatchStore.ticket($0), $0.string("summary") ?? "",
             (JSONValue.parse($0.string("spec_codes_json") ?? "[]").arrayValue ?? []).compactMap { $0.stringValue }, $0.date("dat") ?? Date())
        }
    }
}


/// One run of a model, with what it used. Tokens only: plans have no per-token price (decision on Reports).
public struct RunRecord: Equatable, Sendable {
    public var id: Int
    public var ticketId: Int?
    public var ticketNumber: String?
    public var ticketTitle: String?
    public var ticketType: TicketType?
    public var area: String?
    public var projectId: Int?
    public var agent: String
    /// The provider's name; nil for runs recorded before providers were.
    public var provider: String?
    public var model: String?
    /// An `AgentRole` raw value (iris, ask, prepare, build, fix).
    public var role: String?
    public var tokensIn: Int
    public var tokensOut: Int
    public var cacheTokens: Int
    public var startedAt: Date
    public var endedAt: Date?
    public var outcome: String?
    public var tokens: Int { tokensIn + tokensOut }
}

// MARK: Landing (gap G23)

public extension HatchStore {
    /// After the integration branch reached the base branch on green CI, every Merged ticket of the project is in it, so
    /// Hatch moves them to Done (decision WF-L3). Themes whose last child this was finish too, through `move`.
    @discardableResult
    func finishLanded(projectId: Int, reason: String) throws -> [Ticket] {
        try db.transaction {
            try tickets(TicketFilter(projectId: projectId, statuses: [.merged])).map {
                try move($0.id, to: .done, actor: .hatch, reason: reason)
            }
        }
    }
}
