import XCTest
@testable import HatchCore

final class ReportsTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func run(_ ticket: Int?, _ role: String, _ model: String, _ tokens: Int, outcome: String = "ok", hours: Double = 0,
             provider: String = "Claude Code", area: String? = "Editor") -> RunRecord {
        let start = t0.addingTimeInterval(hours * 3600)
        return RunRecord(id: 0, ticketId: ticket, ticketNumber: ticket.map { "#\($0)" }, ticketTitle: ticket.map { "Ticket \($0)" },
                         ticketType: nil, area: ticket == nil ? nil : area, projectId: 1, agent: role == "iris" ? "Iris" : "Agent",
                         provider: provider, model: model, role: role, tokensIn: tokens, tokensOut: 0, cacheTokens: 0,
                         startedAt: start, endedAt: start.addingTimeInterval(60), outcome: outcome)
    }

    func testBreakdownsWasteAndModelOutcome() {
        let runs = [
            run(1, "prepare", "opus", 100, hours: 0), run(1, "prepare", "opus", 120, hours: 1),   // sent back once
            run(1, "build", "sonnet", 500, hours: 2), run(1, "fix", "sonnet", 50, hours: 3),      // needed a fix
            run(2, "build", "sonnet", 300, outcome: "stopped early (exit 1)", hours: 0),          // retried
            run(2, "build", "sonnet", 400, hours: 1),                                             // first time
            run(3, "build", "opus", 900, hours: 0, area: "Connections"),                          // first time
            run(nil, "iris", "haiku", 10, hours: 0), run(4, "iris", "haiku", 10, hours: 1),
        ]
        let r = RunReport(runs: runs, previous: [run(1, "build", "sonnet", 1195)],
                          outcomes: ReportOutcomes(finishedTickets: 2, irisQuestions: 3, irisQuestionsAnswered: 2, duplicatesLinked: 1))
        XCTAssertEqual(r.total, 2390)
        XCTAssertEqual(r.change ?? 0, 1.0, accuracy: 0.001, "twice the period before")
        XCTAssertEqual(r.perFinishedTicket, 1195)
        XCTAssertEqual(r.byTask.first?.task, "build")
        XCTAssertEqual(r.byTask.first?.runs, 4)
        XCTAssertEqual(r.byModel.first?.model, "sonnet")
        XCTAssertEqual(r.byArea.first { $0.area == "Editor" }?.tickets, 3)
        XCTAssertEqual(r.byTicket.map(\.ticketId), [3, 1, 2, 4])
        XCTAssertEqual(r.byTicket.first { $0.ticketId == 2 }?.retries, 1)
        XCTAssertEqual(r.waste.stopped, 300)
        XCTAssertEqual(r.waste.sentBack, 100, "every Prepare before the latest one")
        let sonnet = r.modelOutcomes.first { $0.model == "sonnet" }
        XCTAssertEqual(sonnet?.builds, 2)
        XCTAssertEqual(sonnet?.firstTime, 1)
        XCTAssertEqual(r.modelOutcomes.first { $0.model == "opus" }?.firstTime, 1)
        XCTAssertEqual(r.iris, RunReport.IrisValue(tokens: 20, checks: 2, questions: 3, answered: 2, duplicates: 1))
    }

    func testFiltersApplyToBothPeriods() {
        let r = RunReport(runs: [run(1, "build", "sonnet", 100), run(1, "build", "gpt", 50, provider: "Codex")],
                          previous: [run(1, "build", "gpt", 100, provider: "Codex")], provider: "Codex")
        XCTAssertEqual(r.total, 50)
        XCTAssertEqual(r.change ?? 0, -0.5, accuracy: 0.001)
        XCTAssertNil(RunReport(runs: [run(1, "build", "sonnet", 100)]).change, "nothing to compare with")
        XCTAssertEqual(RunReport(runs: [run(1, "build", "sonnet", 100), run(1, "fix", "opus", 7)], model: "opus").total, 7)
    }

    func testCSVQuotesWhatNeedsIt() {
        var r = run(5, "build", "sonnet", 12)
        r.ticketTitle = "Toast, \"spacing\""
        let lines = RunReport.csv([r]).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasPrefix("started,ended,ticket"))
        XCTAssertTrue(lines[1].contains(",#5,\"Toast, \"\"spacing\"\"\",Editor,Claude Code,sonnet,build,12,0,0,ok"))
    }

    func testOutcomesFromEvents() throws {
        let store = try HatchStore.inMemory()
        let p = try store.upsertProject(key: "echo", name: "Echo")
        let a = try store.createTicket(projectId: p.id, type: .tweak, title: "A")
        let b = try store.createTicket(projectId: p.id, type: .bug, title: "B")
        try store.record(a.id, actor: "hatch", kind: "status", payload: ["from": "toVerify", "to": "done"])
        let q = try store.ask(b.id, text: "Which window?", by: "Iris")
        _ = try store.ask(b.id, text: "Someone else asks", by: "owner")
        _ = try store.answer(questionId: q.id, text: "The main one")
        try store.resolveSuggestion(ticketId: b.id, choice: "accepted", typeChanged: false, duplicateLinked: true)
        let o = try store.reportOutcomes(since: Date().addingTimeInterval(-60), until: Date().addingTimeInterval(60))
        XCTAssertEqual(o, ReportOutcomes(finishedTickets: 1, irisQuestions: 1, irisQuestionsAnswered: 1, duplicatesLinked: 1))
        XCTAssertEqual(try store.reportOutcomes(since: Date().addingTimeInterval(-60), until: Date().addingTimeInterval(60), projectId: p.id + 1),
                       ReportOutcomes())
    }
}
