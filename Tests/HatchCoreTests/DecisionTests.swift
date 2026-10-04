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
