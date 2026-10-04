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
