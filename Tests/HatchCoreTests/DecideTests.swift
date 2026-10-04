import XCTest
@testable import HatchCore

final class DecideTests: XCTestCase {
    var store: HatchStore!
    var project: Project!

    override func setUpWithError() throws {
        store = try HatchStore.inMemory()
        project = try store.upsertProject(key: "echo", name: "Echo")
    }

    func testTheQueuePutsQuickDecisionsFirstAndLeavesThemesOut() throws {
        let theme = try store.createTicket(projectId: project.id, type: .theme, title: "Components for Echo")
        let draft = try store.createTicket(projectId: project.id, type: .tweak, title: "Start the components package", parentId: theme.id)
        let prepared = try store.createTicket(projectId: project.id, type: .question, title: "Two values for Color.accent", area: "Components")
        try store.setQuestionOptions(ticketId: prepared.id, [QuestionOption(key: "A", title: "Keep the package's", recommended: true, why: "Most views use it",
                                                                           gain: "One value", cost: "12 views change"),
                                                            QuestionOption(key: "B", title: "Keep the folder's", gain: "Nothing changes there", cost: "40 views change")])
        let bug = try store.createTicket(projectId: project.id, type: .bug, title: "Selection lost after sync")
        try store.requestPlanReview(ticketId: bug.id, files: (1...11).map { "File\($0).swift" }, reason: "11 files, over the limit of 8")

        let queue = try store.pendingDecisions(projectId: project.id)
        XCTAssertFalse(queue.contains { $0.ticket.id == theme.id }, "a Theme is a folder, not a decision")
        XCTAssertEqual(Set(queue.map(\.kind)), [.submit, .pick, .plan])
        XCTAssertEqual(queue.first { $0.ticket.id == prepared.id }?.kind, .pick)
        XCTAssertEqual(queue.first { $0.ticket.id == draft.id }?.kind, .submit)
        XCTAssertTrue(queue.allSatisfy(\.isQuick))
        XCTAssertEqual(store.pendingDecisionCount(projectId: project.id), 4, "the bug's own draft and its plan both wait")
        XCTAssertEqual(try store.pendingDecisions(projectId: project.id, area: "Components").map(\.ticket.id), [prepared.id])
    }

    func testAPreparedQuestionTakesItsPathAndBecomesADecision() throws {
        let q = try store.createTicket(projectId: project.id, type: .question, title: "Two values for Color.accent", area: "Components")
        try store.setQuestionOptions(ticketId: q.id, [QuestionOption(key: "A", title: "Keep the package's", recommended: true, why: "Most views use it"),
                                                     QuestionOption(key: "B", title: "Keep the folder's")])
        let (done, decisionId) = try store.decidePreparedQuestion(ticketId: q.id, choice: "B", reason: "The folder's blue matches the icon")
        XCTAssertEqual(done.status, .done)
        let record = try XCTUnwrap(store.decisionRecord(id: decisionId))
        XCTAssertEqual(record.choice, "B")
        XCTAssertEqual(record.recommended, "A")
        XCTAssertEqual(record.kind, .design)
        XCTAssertEqual(record.reason, "The folder's blue matches the icon")
        XCTAssertGreaterThanOrEqual(try store.events(ticketId: q.id).count, 6, "each move is logged")
        XCTAssertTrue(try store.pendingDecisions(projectId: project.id).isEmpty)
    }

    func testAPlanWaitsUntilTheOwnerApprovesOrSendsItBack() throws {
        let bug = try store.createTicket(projectId: project.id, type: .bug, title: "Selection lost after sync")
        try store.requestPlanReview(ticketId: bug.id, files: ["A.swift"], reason: "a Bug")
        let second = try store.requestPlanReview(ticketId: bug.id, files: ["A.swift", "B.swift"], reason: "a Bug")
        XCTAssertEqual(try store.pendingPlanReviews(projectId: project.id).map(\.files), [["A.swift", "B.swift"]], "a new plan replaces the one still waiting")

        let back = try store.decidePlanReview(id: second.id, approve: false, note: "Fix the selection by id first")
        XCTAssertEqual(back.state, .sentBack)
        XCTAssertEqual(try store.notes(ticketId: bug.id).last?.kind, .instruction)
        XCTAssertThrowsError(try store.decidePlanReview(id: second.id, approve: true, note: nil))
        XCTAssertTrue(try store.pendingPlanReviews(projectId: project.id).isEmpty)

        let third = try store.requestPlanReview(ticketId: bug.id, files: ["A.swift"], reason: "a Bug")
        XCTAssertEqual(try store.decidePlanReview(id: third.id, approve: true, note: nil).state, .approved)
        XCTAssertEqual(try store.latestPlanReview(ticketId: bug.id)?.state, .approved)
    }

    func testOptionsKeepWhatTheyGainAndCost() throws {
        let q = try store.createTicket(projectId: project.id, type: .question, title: "History storage")
        try store.setQuestionOptions(ticketId: q.id, [QuestionOption(key: "A", title: "SQLite", recommended: true, why: "Searchable", gain: "Searchable", cost: "A migration")])
        XCTAssertEqual(try store.questionOptions(ticketId: q.id).first?.gain, "Searchable")
        XCTAssertEqual(try store.questionOptions(ticketId: q.id).first?.cost, "A migration")
    }
}

final class DecideRunTests: XCTestCase {
    func item(_ n: Int, _ kind: PendingDecision.Kind = .pick) -> PendingDecision {
        let t = Ticket(id: n, ghNumber: n, projectId: 1, type: .question, status: .yourCall, prevStatus: nil, turn: .you, title: "T\(n)", body: "",
                       originalTitle: nil, originalBody: nil, parentId: nil, priority: 0, area: nil, revision: 1, takenBy: nil,
                       createdAt: Date(), updatedAt: Date())
        return PendingDecision(id: "t\(n)", kind: kind, ticket: t, plan: nil)
    }

    func testWorkWaitsOutTheUndoWindowAndUndoCancelsIt() {
        var run = DecideRun(items: [item(1), item(2), item(3)])
        let start = Date(timeIntervalSince1970: 1000)
        var done: [String] = []
        run.decide(.chose(agreed: true), startsAgent: true, label: "one", now: start) { done.append("one") }
        run.decide(.chose(agreed: false), startsAgent: false, label: "two", now: start) { done.append("two") }
        XCTAssertEqual(run.current?.id, "t3")
        XCTAssertTrue(run.due(now: start.addingTimeInterval(9)).isEmpty, "nothing runs inside the window")
        run.undo()
        XCTAssertEqual(run.current?.id, "t2", "undo brings the card back")
        XCTAssertNil(run.records["t2"])
        run.due(now: start.addingTimeInterval(10)).forEach { $0() }
        XCTAssertEqual(done, ["one"], "the undone decision never runs")
        XCTAssertTrue(run.due(now: start.addingTimeInterval(20)).isEmpty, "each piece runs once")
    }

    func testMarksKeepOnePlacePerDecisionAndSayWhatHappened() {
        var run = DecideRun(items: [item(1), item(2), item(3)])
        run.decide(.chose(agreed: true), startsAgent: true, label: "one") {}
        run.decide(.later, startsAgent: false, label: "two") {}
        let marks = run.marks
        XCTAssertEqual(marks.map(\.id), ["t1", "t2", "t3"], "Later does not add a pill at the end")
        XCTAssertEqual(marks.map(\.mark), [.handled(startsAgent: true), .later, .current])
        run.decide(.chose(agreed: false), startsAgent: false, label: "three") {}
        XCTAssertEqual(run.marks.map(\.mark), [.handled(startsAgent: true), .current, .handled(startsAgent: false)],
                       "the decision left for later is current again in its own place")
    }

    func testLaterMovesTheCardToTheEndAndClosingRunsEverything() {
        var run = DecideRun(items: [item(1), item(2, .judge)])
        var done = 0
        run.decide(.later, startsAgent: false, label: "later") { done += 100 }
        XCTAssertEqual(run.items.map(\.id), ["t1", "t2", "t1"])
        XCTAssertEqual(run.current?.id, "t2")
        run.decide(.refined, startsAgent: true, label: "refine") { done += 1 }
        run.decide(.chose(agreed: true), startsAgent: false, label: "pick") { done += 1 }
        XCTAssertNil(run.current)
        run.due(all: true).forEach { $0() }
        XCTAssertEqual(done, 2, "later has no work")
        XCTAssertEqual(run.agreed, 1)
        XCTAssertEqual(run.refined, 1)
        XCTAssertEqual(run.later, 0, "the card decided after Later counts as decided")
        XCTAssertEqual(run.agentsStarted, 1)
    }
}

final class SpecBeforeVerifyTests: XCTestCase {
    func testBuiltWorkNeedsTheSpecStepWhenTheProjectHasANotebook() throws {
        let store = try HatchStore.inMemory()
        var config = ProjectConfig(name: "Echo", ticketsRepo: "acme/tickets",
                                   repos: [RepoConfig(role: .notebook, remote: "acme/echo-notebook", branch: "main")])
        let project = try store.upsertProject(key: "echo", name: "Echo", config: config)
        let t = try store.createTicket(projectId: project.id, type: .tweak, title: "Rename Run")
        for (s, a) in [(Status.checking, Actor.owner), (.ready, .hatch), (.building, .hatch)] { try store.move(t.id, to: s, actor: a) }
        XCTAssertThrowsError(try store.move(t.id, to: .toVerify, actor: .hatch))
        try store.record(t.id, actor: "hatch", kind: "spec", payload: ["ok": .bool(true), "detail": "unchanged"])
        XCTAssertEqual(try store.move(t.id, to: .toVerify, actor: .hatch).status, .toVerify)
        // A fix is new work: it needs its own Spec step.
        try store.move(t.id, to: .fixing, actor: .owner)
        XCTAssertThrowsError(try store.move(t.id, to: .toVerify, actor: .hatch))

        // Without a notebook there is no Spec to keep, so nothing is checked.
        config.repos = []
        let other = try store.upsertProject(key: "plain", name: "Plain", config: config)
        let u = try store.createTicket(projectId: other.id, type: .bug, title: "Crash")
        for (s, a) in [(Status.checking, Actor.owner), (.ready, .hatch), (.building, .hatch), (.toVerify, .hatch)] { try store.move(u.id, to: s, actor: a) }
        XCTAssertEqual(try store.ticket(id: u.id)?.status, .toVerify)
    }
}

final class ActivityLogTests: XCTestCase {
    func testActionsCarryTheirSyncResult() throws {
        let store = try HatchStore.inMemory()
        let project = try store.upsertProject(key: "echo", name: "Echo")
        let t = try store.createTicket(projectId: project.id, type: .tweak, title: "Rename Run")
        try store.move(t.id, to: .checking, actor: .owner)
        _ = try store.addNote(t.id, kind: .note, author: "owner", body: "Keep the shortcut")
        try store.record(t.id, actor: "hatch", kind: "take", payload: [:])
        let log = try store.activityLog(projectId: project.id)
        let status = try XCTUnwrap(log.first { $0.event?.kind == "status" })
        XCTAssertEqual(status.sync?.op, "issue.create", "leaving Draft makes the issue")
        XCTAssertEqual(log.first { $0.event?.kind == "note" }?.sync?.op, "issue.comment")
        XCTAssertNil(log.first { $0.event?.kind == "take" }?.sync, "an action that does not touch GitHub has no sync")
        XCTAssertEqual(log.filter { $0.event == nil }.count, 0, "every operation found its action")

        let comment = try XCTUnwrap(log.first { $0.event?.kind == "note" }?.sync)
        try store.db.execute("UPDATE sync_log SET state = 'failed', error = 'Not found' WHERE id = ?", [.int(comment.id)])
        let failed = try store.activityLog(projectId: project.id, failedOnly: true)
        XCTAssertEqual(failed.map { $0.event?.kind }, ["note"])
    }
}
