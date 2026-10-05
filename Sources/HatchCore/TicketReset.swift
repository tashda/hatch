import Foundation

/// "Reset this ticket" (decision IR16), for debugging: the ticket starts again from the owner's first prompt, as if it
/// had just been captured. Everything built on it goes: Iris's filing and questions, notes, links, plans, claims, proposals
/// and the history after capture. What stays: the prompt, the screenshots, the run records (they are cost history) and
/// the ticket's number and GitHub issue, whose title, text and labels are brought back to match.
public extension HatchStore {
    /// Tables whose rows belong to one ticket and are removed on a reset.
    private static let resetTables = ["question", "question_option", "note", "pinned_note", "proposal", "revision", "pick", "verdict",
                                      "plan_review", "claim", "preview_ticket", "stage_session"]
    /// History kept: how the ticket began.
    private static let keptEvents: Set<String> = ["created", "captured", "attachment", "attachment-uploaded"]

    /// The database half. Workspaces on disk and a running agent are the caller's to stop and remove first (`TicketReset`
    /// in HatchGit does that). The parts of a split are dropped; a part keeps its parent.
    @discardableResult
    func resetTicket(_ id: Int, by: String = "owner") throws -> Ticket {
        try db.transaction {
            guard let t = try ticket(id: id) else { throw StoreError.notFound("ticket \(id)") }
            guard let title = t.originalTitle, !title.isEmpty else { throw StoreError.invalid("\(t.displayNumber) has no original prompt to go back to.") }
            let body = t.originalBody ?? ""

            // The parts of a split are dropped with it: they were made from a reading the reset throws away.
            let parts = try tickets(TicketFilter(parentId: id)) + (try splitParts(of: id).compactMap { try ticket(id: $0) })
            for part in parts where part.status != .dropped {
                try db.execute("UPDATE ticket SET status = ?, turn = ?, prev_status = NULL, taken_by = NULL, updated_at = ? WHERE id = ?",
                               [.text(Status.dropped.rawValue), .text(Status.dropped.turn.rawValue), .date(now()), .int(part.id)])
                try record(part.id, actor: by, kind: "status", payload: ["from": .string(part.status.rawValue), "to": .string(Status.dropped.rawValue), "reason": .string("parent \(t.displayNumber) was reset")])
                if part.status != .draft { try enqueueLabels(part.id) }
            }

            for table in Self.resetTables { try db.execute("DELETE FROM \(table) WHERE ticket_id = ?", [.int(id)]) }
            // Links go, except the one to the Theme this ticket is a part of.
            try db.execute("DELETE FROM ticket_link WHERE (from_id = ? OR to_id = ?) AND kind != 'parent'", [.int(id), .int(id)])
            try db.execute("DELETE FROM ticket_link WHERE to_id = ? AND kind = 'parent'", [.int(id)])
            let kept = Self.keptEvents.map { "'\($0)'" }.joined(separator: ",")
            try db.execute("DELETE FROM event WHERE ticket_id = ? AND kind NOT IN (\(kept))", [.int(id)])

            try db.execute("""
                UPDATE ticket SET title = ?, body = ?, type = ?, status = ?, turn = ?, prev_status = NULL, taken_by = NULL, path = NULL, verify = NULL,
                       area = NULL, priority = 0, revision = 1, updated_at = ? WHERE id = ?
                """, [.text(title), .text(body), .text(TicketType.question.rawValue), .text(Status.checking.rawValue), .text(Status.checking.turn.rawValue),
                      .date(now()), .int(id)])
            try record(id, actor: by, kind: "reset", payload: ["from": .string(t.status.rawValue)])
            try record(id, actor: "hatch", kind: "status", payload: ["from": .string(t.status.rawValue), "to": .string(Status.checking.rawValue), "reason": .string("reset; Iris files it again")])
            try indexTicket(id)
            if t.ghNumber != nil || t.status != .draft {
                try enqueueUpdate(id, title: title, body: body)
                try enqueueLabels(id)
            }
            return try ticket(id: id)!
        }
    }
}
