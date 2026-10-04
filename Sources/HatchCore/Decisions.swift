import Foundation

/// What a decision is about (decision PS15). Set from the ticket, changeable.
public enum DecisionKind: String, Codable, CaseIterable, Sendable {
    case design, architecture, workflow
    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// The kind a decided ticket starts with: visual work is design, a Question is usually about how the code is built.
    public static func `default`(for type: TicketType) -> DecisionKind { type == .question ? .architecture : .design }
}

/// One option that was weighed. `key` is short (A, B, C or a specimen id).
public struct DecisionOption: Codable, Equatable, Sendable {
    public var key: String
    public var title: String
    public var detail: String?
    public init(key: String, title: String, detail: String? = nil) { self.key = key; self.title = title; self.detail = detail }
}

/// A decision as the database keeps it: everything needed to write its notebook file or answer a search.
public struct DecisionRecord: Equatable, Sendable {
    public var id: Int
    public var ticketId: Int
    public var ticketNumber: String
    public var ticketType: TicketType
    public var projectId: Int
    public var kind: DecisionKind
    public var title: String
    public var summary: String
    public var area: String?
    public var options: [DecisionOption]
    public var choice: String?
    public var recommended: String?
    public var reason: String?
    public var specCodes: [String]
    public var replacesId: Int?
    public var filePath: String?
    public var at: Date
}

/// An option offered on a Question (decision PS16), with at most one recommended.
public struct QuestionOption: Equatable, Sendable {
    public var key: String
    public var title: String
    public var detail: String?
    public var recommended: Bool
    public var why: String?
    public init(key: String, title: String, detail: String? = nil, recommended: Bool = false, why: String? = nil) {
        self.key = key; self.title = title; self.detail = detail; self.recommended = recommended; self.why = why
    }
}

public extension HatchStore {
    /// Records a decision in full and indexes it for search. The notebook file is written later by the export.
    @discardableResult
    func recordDecision(ticketId: Int, kind: DecisionKind, title: String, summary: String, area: String? = nil,
                        options: [DecisionOption] = [], choice: String? = nil, recommended: String? = nil, reason: String? = nil,
                        specCodes: [String] = [], replaces: Int? = nil, filePath: String? = nil, at: Date? = nil) throws -> Int {
        let optionsJSON = try String(decoding: JSONEncoder().encode(options), as: UTF8.self)
        try db.execute("""
            INSERT INTO decision(ticket_id, summary, spec_codes_json, at, kind, title, area, options_json, choice, recommended, reason, replaces_id, file_path)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, [.int(ticketId), .text(summary), .text(JSONValue.array(specCodes.map { .string($0) }).jsonString()), .date(at ?? now()),
                  .text(kind.rawValue), .text(title), .opt(area), .text(optionsJSON), .opt(choice), .opt(recommended), .opt(reason),
                  .opt(replaces), .opt(filePath)])
        let id = Int(db.lastInsertRowID)
        try db.execute("INSERT INTO decision_fts(title, summary, reason, area, decision_id) VALUES(?,?,?,?,?)",
                       [.text(title), .text(summary), .text(reason ?? ""), .text(area ?? ""), .int(id)])
        return id
    }

    func decisionRecords(projectId: Int? = nil, pendingExport: Bool = false, limit: Int? = nil) throws -> [DecisionRecord] {
        var sql = "SELECT d.*, d.id AS did, d.at AS dat, t.gh_number, t.id AS tid, t.type AS ttype, t.project_id FROM decision d JOIN ticket t ON t.id = d.ticket_id WHERE 1 = 1"
        var params: [SQLValue] = []
        if let projectId { sql += " AND t.project_id = ?"; params.append(.int(projectId)) }
        if pendingExport { sql += " AND d.file_path IS NULL" }
        sql += " ORDER BY d.at DESC, d.id DESC"
        if let limit { sql += " LIMIT ?"; params.append(.int(limit)) }
        return try db.query(sql, params, map: Self.decisionRecord)
    }

    func decisionRecord(id: Int) throws -> DecisionRecord? {
        try db.query("SELECT d.*, d.id AS did, d.at AS dat, t.gh_number, t.id AS tid, t.type AS ttype, t.project_id FROM decision d JOIN ticket t ON t.id = d.ticket_id WHERE d.id = ?",
                     [.int(id)], map: Self.decisionRecord).first
    }

    /// Decisions that match `query`, best first, for briefs and Iris: free and local, so only the few that matter cost tokens.
    func searchDecisions(projectId: Int, query: String, area: String? = nil, limit: Int = 3) throws -> [DecisionRecord] {
        var words = Array(Self.tokens(query).prefix(14))
        if let area { words.append(contentsOf: Self.tokens(area)) }
        guard !words.isEmpty else { return [] }
        return try db.query("""
            SELECT d.*, d.id AS did, d.at AS dat, t.gh_number, t.id AS tid, t.type AS ttype, t.project_id
            FROM decision_fts JOIN decision d ON d.id = decision_fts.decision_id JOIN ticket t ON t.id = d.ticket_id
            WHERE decision_fts MATCH ? AND t.project_id = ? ORDER BY bm25(decision_fts) LIMIT ?
            """, [.text(words.map { "\"\($0)\"" }.joined(separator: " OR ")), .int(projectId), .int(limit)], map: Self.decisionRecord)
    }

    func markDecisionExported(_ id: Int, filePath: String) throws {
        try db.execute("UPDATE decision SET file_path = ? WHERE id = ?", [.text(filePath), .int(id)])
    }

    /// Notebook paths of the decisions already in the database, so an import adds only the missing ones.
    func decisionFilePaths(projectId: Int) throws -> Set<String> {
        Set(try db.query("SELECT d.file_path FROM decision d JOIN ticket t ON t.id = d.ticket_id WHERE t.project_id = ? AND d.file_path IS NOT NULL",
                         [.int(projectId)]) { $0.string("file_path") ?? "" })
    }

    func setDecisionKind(_ id: Int, kind: DecisionKind) throws {
        try db.execute("UPDATE decision SET kind = ? WHERE id = ?", [.text(kind.rawValue), .int(id)])
    }

    // MARK: Questions with options (decision PS16)

    /// Replaces a Question's options. At most one is recommended, and a recommended option must say why (the owner's rule).
    func setQuestionOptions(ticketId: Int, _ options: [QuestionOption]) throws {
        guard options.filter(\.recommended).count <= 1 else { throw StoreError.invalid("Recommend one option, not several.") }
        if let r = options.first(where: \.recommended), (r.why ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            throw StoreError.invalid("Say why you recommend option \(r.key).")
        }
        guard Set(options.map(\.key)).count == options.count else { throw StoreError.invalid("Each option needs its own key.") }
        try db.transaction {
            try db.execute("DELETE FROM question_option WHERE ticket_id = ?", [.int(ticketId)])
            for o in options {
                try db.execute("INSERT INTO question_option(ticket_id, key, title, detail, recommended, why) VALUES(?,?,?,?,?,?)",
                               [.int(ticketId), .text(o.key), .text(o.title), .opt(o.detail), .int(o.recommended ? 1 : 0), .opt(o.why)])
            }
        }
    }

    func questionOptions(ticketId: Int) throws -> [QuestionOption] {
        try db.query("SELECT * FROM question_option WHERE ticket_id = ? ORDER BY key", [.int(ticketId)]) {
            QuestionOption(key: $0.string("key")!, title: $0.string("title")!, detail: $0.string("detail"),
                           recommended: ($0.int("recommended") ?? 0) == 1, why: $0.string("why"))
        }
    }

    /// The owner answers a Question by choosing one of its options: the Question is done and the answer becomes a decision.
    @discardableResult
    func decideQuestion(ticketId: Int, choice key: String, reason: String?, kind: DecisionKind = .architecture) throws -> (ticket: Ticket, decisionId: Int) {
        try db.transaction {
            guard let t = try ticket(id: ticketId) else { throw StoreError.notFound("ticket \(ticketId)") }
            guard t.type == .question else { throw StoreError.invalid("Only a Question is answered by choosing an option.") }
            let options = try questionOptions(ticketId: ticketId)
            guard let chosen = options.first(where: { $0.key == key }) else { throw StoreError.invalid("\(t.displayNumber) has no option \(key).") }
            let moved = try move(ticketId, to: .done, actor: .owner, reason: "answered: \(key)")
            let recommended = options.first(where: \.recommended)
            let why = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = try recordDecision(ticketId: ticketId, kind: kind, title: t.title,
                                        summary: "Chose \(chosen.key): \(chosen.title).",
                                        area: t.area, options: options.map { DecisionOption(key: $0.key, title: $0.title, detail: $0.detail) },
                                        choice: chosen.key, recommended: recommended?.key,
                                        reason: (why?.isEmpty == false ? why : nil) ?? (recommended?.key == chosen.key ? recommended?.why : nil))
            return (moved, id)
        }
    }

    // MARK: Notebook export state

    func notebookNowHash(projectId: Int) throws -> String? {
        try db.query("SELECT now_hash FROM notebook_state WHERE project_id = ?", [.int(projectId)]) { $0.string("now_hash") }.first ?? nil
    }

    func setNotebookState(projectId: Int, nowHash: String?, pushed: Bool, error: String?) throws {
        try db.execute("""
            INSERT INTO notebook_state(project_id, now_hash, exported_at, pushed_at, error) VALUES(?,?,?,?,?)
            ON CONFLICT(project_id) DO UPDATE SET now_hash = COALESCE(excluded.now_hash, now_hash), exported_at = excluded.exported_at,
                pushed_at = COALESCE(excluded.pushed_at, pushed_at), error = excluded.error
            """, [.int(projectId), .opt(nowHash), .date(now()), pushed ? .date(now()) : .null, .opt(error)])
    }

    func notebookError(projectId: Int) throws -> String? {
        try db.query("SELECT error FROM notebook_state WHERE project_id = ?", [.int(projectId)]) { $0.string("error") }.first ?? nil
    }

    private static func decisionRecord(_ r: Row) -> DecisionRecord {
        let options = (try? JSONDecoder().decode([DecisionOption].self, from: Data((r.string("options_json") ?? "[]").utf8))) ?? []
        let tid = r.int("tid")!
        return DecisionRecord(
            id: r.int("did")!, ticketId: tid, ticketNumber: r.int("gh_number").map { "#\($0)" } ?? "new-\(tid)",
            ticketType: TicketType(rawValue: r.string("ttype") ?? "") ?? .question, projectId: r.int("project_id")!,
            kind: DecisionKind(rawValue: r.string("kind") ?? "") ?? .design, title: r.string("title") ?? "",
            summary: r.string("summary") ?? "", area: r.string("area"), options: options, choice: r.string("choice"),
            recommended: r.string("recommended"), reason: r.string("reason"),
            specCodes: (JSONValue.parse(r.string("spec_codes_json") ?? "[]").arrayValue ?? []).compactMap(\.stringValue),
            replacesId: r.int("replaces_id"), filePath: r.string("file_path"), at: r.date("dat") ?? Date())
    }
}
