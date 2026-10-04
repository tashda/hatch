import XCTest
@testable import HatchCore

final class DecisionTests: XCTestCase {
    var store: HatchStore!
    var project: Project!

    override func setUpWithError() throws {
        store = try HatchStore.inMemory()
        project = try store.upsertProject(key: "echo", name: "Echo")
    }

    func testDecisionsAreSearchableAndQueuedForTheNotebook() throws {
        let t = try store.createTicket(projectId: project.id, type: .proposal, title: "Toast spacing", area: "Toasts", ghNumber: 151)
        let id = try store.recordDecision(ticketId: t.id, kind: .design, title: "Toast spacing", summary: "Chose B, 12pt.", area: "Toasts",
                                          options: [.init(key: "A", title: "8pt"), .init(key: "B", title: "12pt")], choice: "B",
                                          recommended: "B", reason: "A felt cramped at large type.")
        let other = try store.createTicket(projectId: project.id, type: .question, title: "Connection retries", ghNumber: 160)
        try store.recordDecision(ticketId: other.id, kind: .architecture, title: "Connection retries", summary: "Retry three times with backoff.")

        let hits = try store.searchDecisions(projectId: project.id, query: "toast feels cramped")
        XCTAssertEqual(hits.first?.id, id)
        XCTAssertEqual(hits.first?.options.map(\.key), ["A", "B"])
        XCTAssertEqual(hits.first?.ticketNumber, "#151")

        XCTAssertEqual(try store.decisionRecords(projectId: project.id, pendingExport: true).count, 2)
        try store.markDecisionExported(id, filePath: "decisions/0151-toast-spacing.md")
        XCTAssertEqual(try store.decisionRecords(projectId: project.id, pendingExport: true).map(\.title), ["Connection retries"])
        XCTAssertEqual(try store.decisionFilePaths(projectId: project.id), ["decisions/0151-toast-spacing.md"])
    }

    func testOldStyleDecisionsGetKindAndTitleFromTheTicket() throws {
        let t = try store.createTicket(projectId: project.id, type: .question, title: "Tabs after a crash", ghNumber: 146)
        let id = try store.recordDecision(ticketId: t.id, summary: "Restore them.")
        let d = try XCTUnwrap(store.decisionRecord(id: id))
        XCTAssertEqual(d.kind, .architecture)
        XCTAssertEqual(d.title, "Tabs after a crash")
    }

    func testQuestionOptionsNeedOneRecommendationWithAReason() throws {
        let q = try store.createTicket(projectId: project.id, type: .question, title: "How do connections retry?", ghNumber: 160)
        XCTAssertThrowsError(try store.setQuestionOptions(ticketId: q.id, [.init(key: "A", title: "x", recommended: true)]))
        XCTAssertThrowsError(try store.setQuestionOptions(ticketId: q.id, [.init(key: "A", title: "x", recommended: true, why: "w"),
                                                                           .init(key: "B", title: "y", recommended: true, why: "w")]))
        try store.setQuestionOptions(ticketId: q.id, [.init(key: "A", title: "Backoff", recommended: true, why: "Servers recover."),
                                                      .init(key: "B", title: "Fail at once")])
        XCTAssertEqual(try store.questionOptions(ticketId: q.id).map(\.key), ["A", "B"])
    }

    func testDecidingAQuestionRecordsTheChoiceAndFinishesIt() throws {
        let q = try store.createTicket(projectId: project.id, type: .question, title: "How do connections retry?", ghNumber: 160, status: .yourCall)
        try store.setQuestionOptions(ticketId: q.id, [.init(key: "A", title: "Backoff", recommended: true, why: "Servers recover."),
                                                      .init(key: "B", title: "Fail at once")])
        let result = try store.decideQuestion(ticketId: q.id, choice: "A", reason: nil)
        XCTAssertEqual(result.ticket.status, .done)
        let d = try XCTUnwrap(store.decisionRecord(id: result.decisionId))
        XCTAssertEqual(d.kind, .architecture)
        XCTAssertEqual(d.choice, "A")
        XCTAssertEqual(d.recommended, "A")
        XCTAssertEqual(d.reason, "Servers recover.", "choosing the recommendation keeps its reason")
        XCTAssertThrowsError(try store.decideQuestion(ticketId: q.id, choice: "Z", reason: nil))
    }

    func testDecisionFileRoundTrip() throws {
        let t = try store.createTicket(projectId: project.id, type: .proposal, title: "Toast spacing", area: "Toasts", ghNumber: 151)
        let id = try store.recordDecision(ticketId: t.id, kind: .design, title: "Toast spacing", summary: "Chose B, 12pt.", area: "Toasts",
                                          options: [.init(key: "A", title: "8pt"), .init(key: "B", title: "12pt")], choice: "B",
                                          recommended: "A", reason: "A felt cramped.", specCodes: ["TOAST-3"])
        let d = try XCTUnwrap(store.decisionRecord(id: id))
        XCTAssertEqual(Notebook.decisionPath(d, taken: []), "decisions/0151-toast-spacing.md")
        XCTAssertEqual(Notebook.decisionPath(d, taken: ["decisions/0151-toast-spacing.md"]), "decisions/0151-toast-spacing-2.md")
        let file = Notebook.decisionFile(d, replacesPath: nil)
        XCTAssertTrue(file.contains("- A: 8pt (recommended)"))
        XCTAssertTrue(file.contains("- B: 12pt (chosen)"))
        let parsed = try XCTUnwrap(Notebook.parseDecision(file))
        XCTAssertEqual(parsed.ticketNumber, 151)
        XCTAssertEqual(parsed.kind, .design)
        XCTAssertEqual(parsed.area, "Toasts")
        XCTAssertEqual(parsed.specCodes, ["TOAST-3"])
        XCTAssertEqual(parsed.title, "Toast spacing")
        XCTAssertEqual(parsed.summary, "Chose B, 12pt.")
        XCTAssertEqual(parsed.reason, "A felt cramped.")
        XCTAssertNil(Notebook.parseDecision("# Not a decision"))
    }

    func testAcceptingAProposalRecordsAFullDecision() throws {
        let t = try store.createTicket(projectId: project.id, type: .proposal, title: "Toast spacing", ghNumber: 151, status: .yourCall)
        let r = try store.acceptProposal(ticketId: t.id, choices: ["spacing": "B"])
        let d = try XCTUnwrap(store.decisionRecord(id: r.decisionId))
        XCTAssertEqual(d.kind, .design)
        XCTAssertEqual(d.title, "Toast spacing")
        XCTAssertEqual(d.choice, "spacing = B")
        XCTAssertEqual(try store.searchDecisions(projectId: project.id, query: "toast").count, 1)
    }
}

final class RecentEventsTests: XCTestCase {
    func testNewestFirstAcrossTickets() throws {
        let store = try HatchStore.inMemory()
        let p = try store.upsertProject(key: "echo", name: "Echo")
        let a = try store.createTicket(projectId: p.id, type: .tweak, title: "A", ghNumber: 1)
        let b = try store.createTicket(projectId: p.id, type: .tweak, title: "B", ghNumber: 2)
        _ = try store.move(a.id, to: .checking, actor: .owner)
        _ = try store.move(b.id, to: .checking, actor: .owner)
        let recent = try store.recentEvents(projectId: p.id, limit: 3)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.first?.ticket.title, "B")
        XCTAssertEqual(recent.first?.event.kind, "status")
    }
}

final class RunRecordTests: XCTestCase {
    func testRunsRecordProviderModelTaskAndCache() throws {
        let store = try HatchStore.inMemory()
        let p = try store.upsertProject(key: "echo", name: "Echo")
        let t = try store.createTicket(projectId: p.id, type: .tweak, title: "Toast", area: "Notifications", ghNumber: 151)
        let id = try store.startRun(ticketId: t.id, agent: "Agent on #151", step: "Build", provider: "Claude Code", model: "claude-sonnet-5-5", role: "build")
        try store.endRun(id, tokensIn: 1200, tokensOut: 300, outcome: "ok", cacheTokens: 9000)
        _ = try store.startRun(ticketId: nil, agent: "ask", step: nil)
        let runs = try store.runRecords(since: Date().addingTimeInterval(-60))
        XCTAssertEqual(runs.count, 2)
        let r = try XCTUnwrap(runs.first)
        XCTAssertEqual(r.provider, "Claude Code")
        XCTAssertEqual(r.role, "build")
        XCTAssertEqual(r.cacheTokens, 9000)
        XCTAssertEqual(r.tokens, 1500)
        XCTAssertEqual(r.area, "Notifications")
        XCTAssertEqual(r.ticketNumber, "#151")
        XCTAssertNil(runs[1].provider, "a run without a provider is still listed")
    }
}

final class UsageTests: XCTestCase {
    func run(_ provider: String?, _ model: String?, _ role: String?, agent: String = "a", _ tokens: Int, daysAgo: Int = 0) -> RunRecord {
        RunRecord(id: 0, ticketId: nil, ticketNumber: nil, ticketTitle: nil, ticketType: nil, area: nil, projectId: nil, agent: agent,
                  provider: provider, model: model, role: role, tokensIn: tokens, tokensOut: 0, cacheTokens: 10,
                  startedAt: Date().addingTimeInterval(Double(-daysAgo) * 86_400), endedAt: nil, outcome: nil)
    }

    func testSumsPerDayTaskAndModel() {
        let runs = [run("Claude Code", "opus", "build", 1000), run("Claude Code", "haiku", nil, agent: "Iris", 50),
                    run("Codex", "gpt", "build", 300, daysAgo: 1), run(nil, nil, nil, agent: "ask", 20)]
        let all = UsageSummary(runs: runs)
        XCTAssertEqual(all.total, 1370)
        XCTAssertEqual(all.cache, 40)
        XCTAssertEqual(all.byTask.first?.key, "build")
        XCTAssertEqual(all.byTask.first?.tokens, 1300)
        XCTAssertEqual(Set(all.byTask.map(\.key)), ["build", "iris", "ask"], "old runs are told apart by their agent")
        XCTAssertEqual(Set(all.days.map(\.key)), ["Claude Code", "Codex", UsageSummary.unknownProvider])
        let claude = UsageSummary(runs: runs, provider: "Claude Code")
        XCTAssertEqual(claude.total, 1050)
        XCTAssertEqual(Set(claude.days.map(\.key)), ["opus", "haiku"], "one provider's chart is split by model")
    }

    func testLimits() {
        let l = UsageLimits(warnAbove: 1000, pauseAbove: 5000)
        XCTAssertEqual(l.level(today: 999), .fine)
        XCTAssertEqual(l.level(today: 1000), .warn)
        XCTAssertEqual(l.level(today: 6000), .pause)
        XCTAssertEqual(UsageLimits().level(today: .max), .fine, "zero is off")
    }
}
