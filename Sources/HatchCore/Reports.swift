import Foundation

/// What happened to tickets in a period, for Reports: finished tickets and what Iris's vetting led to.
public struct ReportOutcomes: Equatable, Sendable {
    public var finishedTickets = 0
    public var irisQuestions = 0
    public var irisQuestionsAnswered = 0
    public var duplicatesLinked = 0
    public init(finishedTickets: Int = 0, irisQuestions: Int = 0, irisQuestionsAnswered: Int = 0, duplicatesLinked: Int = 0) {
        self.finishedTickets = finishedTickets; self.irisQuestions = irisQuestions
        self.irisQuestionsAnswered = irisQuestionsAnswered; self.duplicatesLinked = duplicatesLinked
    }
}

public extension HatchStore {
    /// Tickets moved to Done, Iris's questions and the duplicates linked after vetting, in a period. Read from events.
    func reportOutcomes(since: Date, until: Date, projectId: Int? = nil) throws -> ReportOutcomes {
        let project = projectId == nil ? "" : " AND t.project_id = ?"
        func count(_ sql: String, _ params: [SQLValue]) throws -> Int {
            try db.query(sql, params + (projectId.map { [SQLValue.int($0)] } ?? [])) { $0.int("n") ?? 0 }.first ?? 0
        }
        let range: [SQLValue] = [.date(since), .date(until)]
        var o = ReportOutcomes()
        o.finishedTickets = try count("""
            SELECT COUNT(DISTINCT e.ticket_id) AS n FROM event e JOIN ticket t ON t.id = e.ticket_id
            WHERE e.kind = 'status' AND json_extract(e.payload, '$.to') = 'done' AND e.at >= ? AND e.at < ?\(project)
            """, range)
        o.irisQuestions = try count("""
            SELECT COUNT(*) AS n FROM question q JOIN ticket t ON t.id = q.ticket_id
            WHERE q.asked_by = 'Iris' AND q.at >= ? AND q.at < ?\(project)
            """, range)
        o.irisQuestionsAnswered = try count("""
            SELECT COUNT(*) AS n FROM question q JOIN ticket t ON t.id = q.ticket_id
            WHERE q.asked_by = 'Iris' AND q.answer IS NOT NULL AND q.at >= ? AND q.at < ?\(project)
            """, range)
        o.duplicatesLinked = try count("""
            SELECT COUNT(*) AS n FROM event e JOIN ticket t ON t.id = e.ticket_id
            WHERE e.kind = 'vetting-resolved' AND json_extract(e.payload, '$.duplicateLinked') = 1 AND e.at >= ? AND e.at < ?\(project)
            """, range)
        return o
    }
}

/// Reports (design-review/reports.html): where model work went in a period, in tokens. Built from run records, so it
/// costs nothing to open; every number can be traced to rows in the CSV export.
public struct RunReport: Sendable {
    public struct ModelRow: Sendable, Identifiable { public var model: String; public var provider: String; public var tokens: Int; public var runs: Int; public var id: String { "\(provider)/\(model)" } }
    public struct TaskRow: Sendable, Identifiable { public var task: String; public var tokens: Int; public var runs: Int; public var id: String { task } }
    public struct AreaRow: Sendable, Identifiable { public var area: String; public var tokens: Int; public var tickets: Int; public var id: String { area } }
    public struct TicketRow: Sendable, Identifiable {
        public var ticketId: Int; public var number: String; public var title: String; public var tokens: Int
        /// Runs on the ticket that ended without handing in (stopped, failed or unusable).
        public var retries: Int
        public var id: Int { ticketId }
    }
    /// Per model, its Build runs and how many tickets needed no Fix after review: does the cheaper model do.
    public struct ModelOutcome: Sendable, Identifiable { public var model: String; public var provider: String; public var builds: Int; public var firstTime: Int; public var id: String { "\(provider)/\(model)" } }
    public struct Waste: Sendable, Equatable {
        /// Tokens on runs that ended without handing in.
        public var stopped = 0
        /// Tokens on Prepare runs whose options were sent back: every Prepare on a ticket before its latest one.
        public var sentBack = 0
        public var total: Int { stopped + sentBack }
    }
    public struct IrisValue: Sendable, Equatable {
        public var tokens = 0
        public var checks = 0
        public var questions = 0
        public var answered = 0
        public var duplicates = 0
    }

    public var runs: [RunRecord]
    public var usage: UsageSummary
    public var total: Int
    /// Change against the same length of time just before, nil when there was nothing to compare with.
    public var change: Double?
    public var finishedTickets: Int
    public var perFinishedTicket: Int? { finishedTickets > 0 ? total / finishedTickets : nil }
    public var byModel: [ModelRow]
    public var byTask: [TaskRow]
    public var byArea: [AreaRow]
    public var byTicket: [TicketRow]
    public var modelOutcomes: [ModelOutcome]
    public var waste: Waste
    public var iris: IrisValue

    public static let noArea = "No area"

    /// `previous` is the period just before, for the change. Filters on provider and model apply to both.
    public init(runs all: [RunRecord], previous: [RunRecord] = [], outcomes: ReportOutcomes = ReportOutcomes(),
                provider: String? = nil, model: String? = nil, calendar: Calendar = .current) {
        func keep(_ r: RunRecord) -> Bool {
            (provider == nil || (r.provider ?? UsageSummary.unknownProvider) == provider) && (model == nil || (r.model ?? "Default model") == model)
        }
        let runs = all.filter(keep)
        self.runs = runs
        usage = UsageSummary(runs: runs, provider: provider, calendar: calendar)
        total = usage.total
        let before = previous.filter(keep).reduce(0) { $0 + $1.tokens }
        change = before > 0 ? Double(total - before) / Double(before) : nil
        finishedTickets = outcomes.finishedTickets

        var models: [String: ModelRow] = [:], tasks: [String: TaskRow] = [:]
        var areas: [String: (tokens: Int, tickets: Set<Int>)] = [:], tickets: [Int: TicketRow] = [:]
        for r in runs {
            let p = r.provider ?? UsageSummary.unknownProvider, m = r.model ?? "Default model"
            models["\(p)/\(m)", default: ModelRow(model: m, provider: p, tokens: 0, runs: 0)].tokens += r.tokens
            models["\(p)/\(m)"]!.runs += 1
            let task = UsageSummary.task(of: r)
            tasks[task, default: TaskRow(task: task, tokens: 0, runs: 0)].tokens += r.tokens
            tasks[task]!.runs += 1
            if let id = r.ticketId {
                let area = (r.area?.isEmpty == false ? r.area : nil) ?? Self.noArea
                areas[area, default: (0, [])].tokens += r.tokens
                areas[area]!.tickets.insert(id)
                tickets[id, default: TicketRow(ticketId: id, number: r.ticketNumber ?? "#\(id)", title: r.ticketTitle ?? "", tokens: 0, retries: 0)].tokens += r.tokens
                if Self.endedEarly(r) { tickets[id]!.retries += 1 }
            }
        }
        byModel = models.values.sorted { $0.tokens > $1.tokens }
        byTask = tasks.values.sorted { $0.tokens > $1.tokens }
        byArea = areas.map { AreaRow(area: $0.key, tokens: $0.value.tokens, tickets: $0.value.tickets.count) }.sorted { $0.tokens > $1.tokens }
        byTicket = tickets.values.sorted { $0.tokens > $1.tokens }

        var waste = Waste()
        let perTicket = Dictionary(grouping: runs.filter { $0.ticketId != nil }, by: { $0.ticketId! })
        for r in runs where Self.endedEarly(r) { waste.stopped += r.tokens }
        var outcomesByModel: [String: ModelOutcome] = [:]
        for (_, ticketRuns) in perTicket {
            let prepares = ticketRuns.filter { UsageSummary.task(of: $0) == "prepare" && !Self.endedEarly($0) }.sorted { $0.startedAt < $1.startedAt }
            waste.sentBack += prepares.dropLast().reduce(0) { $0 + $1.tokens }
            // The first build that handed in, and whether a Fix followed it.
            guard let build = ticketRuns.filter({ UsageSummary.task(of: $0) == "build" && $0.outcome == "ok" }).min(by: { $0.startedAt < $1.startedAt }) else { continue }
            let fixed = ticketRuns.contains { UsageSummary.task(of: $0) == "fix" && $0.startedAt > build.startedAt }
            let p = build.provider ?? UsageSummary.unknownProvider, m = build.model ?? "Default model"
            outcomesByModel["\(p)/\(m)", default: ModelOutcome(model: m, provider: p, builds: 0, firstTime: 0)].builds += 1
            if !fixed { outcomesByModel["\(p)/\(m)"]!.firstTime += 1 }
        }
        self.waste = waste
        modelOutcomes = outcomesByModel.values.sorted { $0.builds > $1.builds }

        let irisRuns = runs.filter { UsageSummary.task(of: $0) == "iris" }
        iris = IrisValue(tokens: irisRuns.reduce(0) { $0 + $1.tokens }, checks: irisRuns.filter { $0.outcome == "ok" }.count,
                         questions: outcomes.irisQuestions, answered: outcomes.irisQuestionsAnswered, duplicates: outcomes.duplicatesLinked)
    }

    /// A run that ended without handing in. Runs still going, or recorded before outcomes were, do not count.
    static func endedEarly(_ r: RunRecord) -> Bool {
        guard r.endedAt != nil, let o = r.outcome else { return false }
        return o != "ok"
    }

    /// The runs as CSV, one row each, for a spreadsheet. Dates are ISO 8601 in UTC.
    public static func csv(_ runs: [RunRecord]) -> String {
        let iso = ISO8601DateFormatter()
        func field(_ s: String?) -> String {
            guard let s, !s.isEmpty else { return "" }
            return s.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var lines = ["started,ended,ticket,title,area,provider,model,task,tokens_in,tokens_out,cache_tokens,outcome"]
        for r in runs {
            lines.append([iso.string(from: r.startedAt), r.endedAt.map(iso.string) ?? "", field(r.ticketNumber), field(r.ticketTitle),
                          field(r.area), field(r.provider), field(r.model), UsageSummary.task(of: r),
                          String(r.tokensIn), String(r.tokensOut), String(r.cacheTokens), field(r.outcome)].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
