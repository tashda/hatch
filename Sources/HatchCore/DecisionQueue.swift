import Foundation

// Decide (decisions DC1 to DC12): everything that waits for the owner, as one queue. Nothing new is stored for it; it
// is read from tickets, Question options and plan reviews, and every answer goes through the store's own calls.

/// An agent's plan over the limit (a Bug, or more files than the project allows), waiting for the owner (decision DC8, I2).
public struct PlanReview: Identifiable, Equatable, Sendable {
    public enum State: String, Sendable { case pending, approved, sentBack = "sent-back" }
    public let id: Int
    public let ticketId: Int
    public var files: [String]
    /// Why it waits: "a Bug" or "11 files, over the limit of 8".
    public var reason: String
    public var state: State
    public var note: String?
    public var at: Date
}

/// One thing the owner decides. Quick ones are decided on the card; the others need the Stage or a Preview.
public struct PendingDecision: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// A Question with options to choose from: offered by an agent, or prepared by Hatch while still a draft.
        case pick
        /// Approve an agent's plan or send it back.
        case plan
        /// Iris's questions and suggestions on a ticket.
        case iris
        /// A Question answered in words: close it as answered.
        case answer
        /// A draft: submit it to Iris.
        case submit
        /// A Proposal or Sketch to judge, in the Stage or on the ticket.
        case judge
        /// Built work to try in a Preview.
        case verify
    }

    public var id: String
    public var kind: Kind
    public var ticket: Ticket
    public var plan: PlanReview?

    /// Decided on the card itself, without the Stage or a Preview.
    public var isQuick: Bool { kind != .judge && kind != .verify }

    /// A rough time to decide, for the session's estimate.
    public var minutes: Double {
        switch kind {
        case .pick, .plan, .iris: 1
        case .answer, .submit: 0.5
        case .judge, .verify: 2
        }
    }
}

public extension HatchStore {
    // MARK: The queue

    /// Everything waiting for the owner: quick decisions first, oldest first within each; then the ones that need
    /// the Stage or a Preview. A Theme is a folder, not a decision, so its drafts are left out (its children are in).
    func pendingDecisions(projectId: Int? = nil, area: String? = nil) throws -> [PendingDecision] {
        var out: [PendingDecision] = []
        let mine = try tickets(TicketFilter(projectId: projectId, statuses: [.yourCall, .needsAnswers, .toVerify, .draft], turn: .you))
        for t in mine where area == nil || t.area == area {
            let kind: PendingDecision.Kind?
            switch t.status {
            case .needsAnswers: kind = .iris
            case .toVerify: kind = .verify
            case .draft:
                let prepared = t.type == .question ? !(try questionOptions(ticketId: t.id)).isEmpty : false
                kind = t.type == .theme ? nil : (prepared ? .pick : .submit)
            case .yourCall:
                if t.type == .question { kind = (try questionOptions(ticketId: t.id)).isEmpty ? .answer : .pick }
                else { kind = .judge }
            default: kind = nil
            }
            if let kind { out.append(PendingDecision(id: "t\(t.id)", kind: kind, ticket: t, plan: nil)) }
        }
        for review in try pendingPlanReviews(projectId: projectId) {
            guard let t = try ticket(id: review.ticketId), area == nil || t.area == area else { continue }
            out.append(PendingDecision(id: "p\(review.id)", kind: .plan, ticket: t, plan: review))
        }
        func rank(_ d: PendingDecision) -> Int { d.isQuick ? 0 : 1 }
        return out.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : ($0.ticket.updatedAt, $0.id) < ($1.ticket.updatedAt, $1.id) }
    }

    /// The one number the Desk row, the toolbar button and the Dock badge all show (decision DC12).
    func pendingDecisionCount(projectId: Int? = nil) -> Int {
        (try? pendingDecisions(projectId: projectId).count) ?? 0
    }

    // MARK: Questions Hatch prepared

    /// The owner chooses an option on a Question Hatch prepared as a draft (decision CO11). The ticket takes its
    /// normal path, each move validated and logged, then is answered like any Question; the GitHub issue is made when
    /// it leaves Draft, as for every ticket.
    @discardableResult
    func decidePreparedQuestion(ticketId: Int, choice: String, reason: String?, kind: DecisionKind? = nil) throws -> (ticket: Ticket, decisionId: Int) {
        try db.transaction {
            guard let t = try ticket(id: ticketId) else { throw StoreError.notFound("ticket \(ticketId)") }
            guard t.type == .question, !(try questionOptions(ticketId: ticketId)).isEmpty else {
                throw StoreError.invalid("\(t.displayNumber) is not a Question with options.")
            }
            if t.status == .draft {
                try move(ticketId, to: .checking, actor: .owner, reason: "chosen in Decide")
                for next in [Status.ready, .preparing, .yourCall] {
                    try move(ticketId, to: next, actor: .hatch, reason: "prepared by Hatch: options ready")
                }
            }
            return try decideQuestion(ticketId: ticketId, choice: choice, reason: reason, kind: kind ?? (t.area == ComponentsSetup.area ? .design : .architecture))
        }
    }

    // MARK: Plan reviews

    /// Asks the owner to approve a plan. A plan still waiting is replaced by the new one.
    @discardableResult
    func requestPlanReview(ticketId: Int, files: [String], reason: String) throws -> PlanReview {
        try db.transaction {
            try db.execute("DELETE FROM plan_review WHERE ticket_id = ? AND state = 'pending'", [.int(ticketId)])
            try db.execute("INSERT INTO plan_review(ticket_id, files_json, reason, at) VALUES(?,?,?,?)",
                           [.int(ticketId), .text(JSONValue.array(files.map { .string($0) }).jsonString()), .text(reason), .date(now())])
            let id = Int(db.lastInsertRowID)
            try record(ticketId, actor: "hatch", kind: "plan-waiting", payload: ["files": .int(files.count), "reason": .string(reason)])
            return try planReview(id: id)!
        }
    }

    func planReview(id: Int) throws -> PlanReview? {
        try db.query("SELECT * FROM plan_review WHERE id = ?", [.int(id)], map: Self.planReview).first
    }

    /// The latest plan review of a ticket, decided or not.
    func latestPlanReview(ticketId: Int) throws -> PlanReview? {
        try db.query("SELECT * FROM plan_review WHERE ticket_id = ? ORDER BY id DESC LIMIT 1", [.int(ticketId)], map: Self.planReview).first
    }

    func pendingPlanReviews(projectId: Int? = nil) throws -> [PlanReview] {
        var sql = "SELECT r.* FROM plan_review r JOIN ticket t ON t.id = r.ticket_id WHERE r.state = 'pending'"
        var params: [SQLValue] = []
        if let projectId { sql += " AND t.project_id = ?"; params.append(.int(projectId)) }
        return try db.query(sql + " ORDER BY r.at", params, map: Self.planReview)
    }

    /// The owner approves the plan or sends it back. A note goes to the agent as an instruction either way.
    @discardableResult
    func decidePlanReview(id: Int, approve: Bool, note: String?) throws -> PlanReview {
        try db.transaction {
            guard let review = try planReview(id: id) else { throw StoreError.notFound("plan review \(id)") }
            guard review.state == .pending else { throw StoreError.invalid("That plan was already decided.") }
            let text = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            try db.execute("UPDATE plan_review SET state = ?, note = ?, decided_at = ? WHERE id = ?",
                           [.text(approve ? PlanReview.State.approved.rawValue : PlanReview.State.sentBack.rawValue), .opt(text?.isEmpty == false ? text : nil),
                            .date(now()), .int(id)])
            try record(review.ticketId, actor: "owner", kind: approve ? "plan-approved" : "plan-sent-back",
                       payload: text?.isEmpty == false ? ["note": .string(text!)] : [:])
            if let text, !text.isEmpty {
                try addNote(review.ticketId, kind: .instruction, author: "owner", body: text,
                            context: ["plan": .string(approve ? "approved" : "sent back")])
            }
            return try planReview(id: id)!
        }
    }

    private static func planReview(_ r: Row) -> PlanReview {
        PlanReview(id: r.int("id")!, ticketId: r.int("ticket_id")!,
                   files: (JSONValue.parse(r.string("files_json") ?? "[]").arrayValue ?? []).compactMap(\.stringValue),
                   reason: r.string("reason") ?? "", state: PlanReview.State(rawValue: r.string("state") ?? "") ?? .pending,
                   note: r.string("note"), at: r.date("at") ?? Date())
    }
}
