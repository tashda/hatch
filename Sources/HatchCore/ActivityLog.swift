import Foundation

/// One line of the Log (decision N2): a Hatch action and the GitHub sync that carried it, or a sync on its own
/// (a pull, or an operation whose action is older than the page).
public struct LogEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var at: Date
    public var ticketId: Int?
    public var event: Event?
    public var sync: SyncOp?
    public var failed: Bool { sync?.state == "failed" }
}

public extension HatchStore {
    /// Every Hatch action, newest first, each with its GitHub sync result when it caused one. An action is paired with
    /// the first operation of the same ticket and kind queued at or after it: queued changes are merged into one
    /// operation, which keeps the time of the latest change, so earlier actions find it too.
    func activityLog(projectId: Int? = nil, failedOnly: Bool = false, limit: Int = 300) throws -> [LogEntry] {
        var sql = "SELECT e.* FROM event e JOIN ticket t ON t.id = e.ticket_id"
        var params: [SQLValue] = []
        if let projectId { sql += " WHERE t.project_id = ?"; params.append(.int(projectId)) }
        let events = try db.query(sql + " ORDER BY e.at DESC, e.id DESC LIMIT ?", params + [.int(limit)]) {
            Event(id: $0.int("id")!, ticketId: $0.int("ticket_id")!, at: $0.date("at")!, actor: $0.string("actor")!,
                  kind: $0.string("kind")!, payload: JSONValue.parse($0.string("payload") ?? "{}"))
        }
        var ops = try syncLog(limit: limit * 2)
        if let projectId {
            let ids = Set(try tickets(TicketFilter(projectId: projectId)).map(\.id))
            ops = ops.filter { $0.ticketId.map(ids.contains) ?? true }
        }
        var used = Set<Int>()
        // Oldest first, so each comment (one operation per note, never merged) goes to its own note.
        var out: [LogEntry] = events.reversed().map { e in
            let families = Self.syncFamilies[e.kind] ?? []
            let oneToOne = e.kind == "note"
            let match = families.isEmpty ? nil : ops
                .filter { $0.ticketId == e.ticketId && families.contains($0.op) && $0.at.timeIntervalSince(e.at) >= -0.5
                          && !(oneToOne && used.contains($0.id)) }
                .min { ($0.at, $0.id) < ($1.at, $1.id) }
            if let match { used.insert(match.id) }
            return LogEntry(id: "e\(e.id)", at: e.at, ticketId: e.ticketId, event: e, sync: match)
        }
        out += ops.filter { !used.contains($0.id) }.map { LogEntry(id: "s\($0.id)", at: $0.at, ticketId: $0.ticketId, event: nil, sync: $0) }
        out.sort { $0.at != $1.at ? $0.at > $1.at : $0.id > $1.id }
        if failedOnly { out = out.filter(\.failed) }
        return Array(out.prefix(limit))
    }

    /// Which GitHub operations an action can cause.
    internal static let syncFamilies: [String: Set<String>] = [
        "created": ["issue.create"],
        "status": ["issue.create", "issue.labels", "issue.close", "issue.reopen"],
        "type": ["issue.labels", "issue.create"],
        "edit": ["issue.update", "issue.labels", "issue.create"],
        "note": ["issue.comment"],
    ]
}
