import XCTest
@testable import HatchCore

/// Contract tests for WORKFLOW.md: the whole transition table as a golden file, a seeded random walk over `HatchStore.move`
/// that may never leave the table, and each kind of ticket walked from start to finish.
final class WorkflowLifecycleTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func makeStore() throws -> (HatchStore, Project) {
        let store = try HatchStore.inMemory()
        let p = try store.upsertProject(key: "t", name: "T", config: ProjectConfig(name: "T", ticketsRepo: "a/t", repos: [], areas: [], docs: []))
        return (store, p)
    }

    // MARK: The table as a golden file

    /// Every move anyone may make, per type: `<type> <actor> <from> -> <to>`. A change to the workflow shows up here as a diff.
    /// Update WORKFLOW.md (section 1 to 5 and "What each branch is covered by") in the same commit, then regenerate:
    /// `HATCH_UPDATE_GOLDEN=1 swift test --filter WorkflowLifecycleTests/testTheTransitionTableMatchesTheGoldenFile`.
    func testTheTransitionTableMatchesTheGoldenFile() throws {
        var lines: [String] = []
        for type in TicketType.allCases {
            for actor in [Actor.owner, .agent, .hatch] {
                for from in Status.allCases {
                    for to in Status.allCases where from != to && Workflow.isAllowed(type: type, from: from, to: to, actor: actor) {
                        lines.append("\(type.rawValue) \(actor.rawValue) \(from.rawValue) -> \(to.rawValue)")
                    }
                }
            }
        }
        let actual = lines.joined(separator: "\n") + "\n"
        let file = Self.root.appendingPathComponent("Tests/HatchCoreTests/workflow-transitions.golden.txt")
        if ProcessInfo.processInfo.environment["HATCH_UPDATE_GOLDEN"] != nil { try actual.write(to: file, atomically: true, encoding: .utf8); return }
        let expected = try String(contentsOf: file, encoding: .utf8)
        if expected != actual {
            let e = Set(expected.split(separator: "\n")), a = Set(actual.split(separator: "\n"))
            XCTFail("The workflow changed. Added: \(a.subtracting(e).sorted().prefix(8)). Removed: \(e.subtracting(a).sorted().prefix(8)). "
                    + "Update WORKFLOW.md, then regenerate the golden file (see the comment on this test).")
        }
    }

    /// The agent may only do what WORKFLOW.md lists for it: ask, file, hand an offer in, take work. It never verifies, merges, accepts or lands.
    func testAnAgentCanOnlyMakeTheMovesTheDocumentListsForIt() {
        let allowed: Set<String> = [
            "checking -> needs-answers", "checking -> ready", "ready -> preparing", "ready -> building", "preparing -> your-call",
            "preparing -> needs-answers", "revising -> your-call", "revising -> needs-answers", "accepted -> building",
            "building -> needs-answers", "fixing -> needs-answers"]
        for type in TicketType.allCases {
            for from in Status.allCases {
                for to in Status.allCases where from != to && Workflow.isAllowed(type: type, from: from, to: to, actor: .agent) {
                    XCTAssertTrue(allowed.contains("\(from.rawValue) -> \(to.rawValue)"), "an agent may not move a \(type) \(from) -> \(to)")
                }
            }
        }
    }

    func testOnlyHatchMovesWorkIntoToVerifyMergedAndDone() {
        for type in TicketType.allCases {
            // From Blocked or Parked the owner resumes to wherever the ticket was; that is `resume`, not a move into these.
            for from in Status.allCases where from != .blocked && from != .parked {
                for actor in [Actor.owner, .agent] {
                    XCTAssertFalse(Workflow.isAllowed(type: type, from: from, to: .merged, actor: actor), "\(actor) → merged")
                    if from != .toVerify { XCTAssertFalse(Workflow.isAllowed(type: type, from: from, to: .toVerify, actor: actor), "\(actor) → to-verify") }
                }
            }
        }
    }

    func testEveryStatusAndTypeIsDescribedInTheDocument() throws {
        let doc = try String(contentsOf: Self.root.appendingPathComponent("WORKFLOW.md"), encoding: .utf8)
        for s in Status.allCases { XCTAssertTrue(doc.contains(s.displayName), "WORKFLOW.md does not mention the status \(s.displayName)") }
        for t in TicketType.allCases { XCTAssertTrue(doc.contains(t.displayName), "WORKFLOW.md does not mention the type \(t.displayName)") }
        for k in ["vet", "prepare", "build", "revise", "fix"] { XCTAssertTrue(doc.contains(k), "WORKFLOW.md does not mention the task \(k)") }
    }

    // MARK: A random walk over the store

    func testARandomWalkNeverLeavesTheTable() throws {
        let (store, p) = try makeStore()
        var rng = SplitMix(seed: UInt64(ProcessInfo.processInfo.environment["HATCH_WALK_SEED"] ?? "") ?? 20261006)
        var tickets: [Ticket] = []
        for (i, type) in TicketType.allCases.enumerated() {
            tickets.append(try store.createTicket(projectId: p.id, type: type, title: "T\(i)", ghNumber: 100 + i))
        }
        let released: Set<Status> = [.ready, .yourCall, .toVerify, .draft, .needsAnswers, .blocked, .parked]
        var moves = 0
        for step in 0..<4000 {
            let t = try XCTUnwrap(try store.ticket(id: tickets.randomElement(using: &rng)!.id))
            let actor = [Actor.owner, .agent, .hatch].randomElement(using: &rng)!
            if (t.status == .blocked || t.status == .parked), Int.random(in: 0..<4, using: &rng) == 0 {
                let back = try? store.resume(t.id, actor: actor == .agent ? .hatch : actor)
                if let back { XCTAssertEqual(back.status, t.prevStatus, "resume goes back to where it was (step \(step))"); moves += 1 }
                continue
            }
            if (t.status == .done || t.status == .dropped), Int.random(in: 0..<3, using: &rng) != 0 { continue }   // let work be reopened less often
            let to = Status.allCases.randomElement(using: &rng)!
            let before = try store.events(ticketId: t.id, kinds: ["status"]).count
            let allowed = Workflow.isAllowed(type: t.type, from: t.status, to: to, actor: actor)
            do {
                let after = try store.move(t.id, to: to, actor: actor)
                // move may refuse for reasons beyond the table (the Spec check), but it never allows more than the table.
                XCTAssertTrue(allowed || t.status == to, "step \(step): \(actor) moved a \(t.type) \(t.status) -> \(to), which the table refuses")
                if t.status != to { moves += 1; XCTAssertEqual(try store.events(ticketId: t.id, kinds: ["status"]).count, before + 1, "one event per move") }
                XCTAssertEqual(after.turn, after.status.turn)
                if released.contains(after.status) || after.status.isTerminal { XCTAssertNil(after.takenBy) }
                if after.status == .blocked || after.status == .parked { XCTAssertNotNil(after.prevStatus, "something to resume to") }
            } catch {
                XCTAssertFalse(allowed && t.status != to && !(error is StoreError), "an allowed move failed with \(error)")
                XCTAssertEqual(try store.ticket(id: t.id)?.status, t.status, "a refused move changes nothing")
                XCTAssertEqual(try store.events(ticketId: t.id, kinds: ["status"]).count, before, "a refused move logs nothing")
            }
            if let again = try store.ticket(id: t.id), step % 50 == 0 { XCTAssertEqual(again.turn, again.status.turn) }
        }
        XCTAssertGreaterThan(moves, 150, "the walk made real moves, not just refusals")
    }

    // MARK: Each kind of ticket, start to finish

    @discardableResult
    func walk(_ store: HatchStore, _ id: Int, _ steps: [(Status, Actor)], file: StaticString = #filePath, line: UInt = #line) throws -> Ticket {
        var t = try XCTUnwrap(store.ticket(id: id))
        for (to, actor) in steps {
            t = try store.move(id, to: to, actor: actor)
            XCTAssertEqual(t.status, to, file: file, line: line)
            XCTAssertEqual(t.turn, to.turn, "whose turn it is follows the status", file: file, line: line)
        }
        return t
    }

    func testAProposalFromPromptToDoneWithEveryTurnAndEveryTask() throws {
        let (store, p) = try makeStore()
        let t = try store.createTicket(projectId: p.id, type: .proposal, title: "Toast look", ghNumber: 200)
        try walk(store, t.id, [(.checking, .owner), (.ready, .hatch)])
        XCTAssertEqual(try store.agentWork().first?.kind, .prepare, "a Proposal waits for a prepare task")
        try store.take(t.id, agent: "A")
        XCTAssertEqual(try store.ticket(id: t.id)?.status, .preparing)
        XCTAssertTrue(try store.agentWork().isEmpty, "a taken ticket is nobody else's work")
        try walk(store, t.id, [(.yourCall, .hatch), (.revising, .owner)])
        XCTAssertEqual(try store.agentWork().first?.kind, .revise)
        try walk(store, t.id, [(.yourCall, .hatch), (.accepted, .owner)])
        XCTAssertEqual(try store.agentWork().first?.kind, .build, "an accepted Proposal waits for a build")
        try store.take(t.id, agent: "A")
        try walk(store, t.id, [(.toVerify, .hatch), (.fixing, .owner)])
        XCTAssertEqual(try store.agentWork().first?.kind, .fix)
        try store.take(t.id, agent: "A")
        let done = try walk(store, t.id, [(.toVerify, .hatch), (.merged, .hatch), (.done, .hatch)])
        XCTAssertNil(done.takenBy)
        XCTAssertTrue(try store.agentWork().isEmpty)
    }

    func testATweakSkipsExploringAndABugToo() throws {
        let (store, p) = try makeStore()
        for type in [TicketType.tweak, .bug] {
            let t = try store.createTicket(projectId: p.id, type: type, title: "\(type)", ghNumber: 300 + (type == .bug ? 1 : 0))
            try walk(store, t.id, [(.checking, .owner), (.ready, .hatch)])
            XCTAssertEqual(try store.agentWork().first { $0.ticket.id == t.id }?.kind, .build, "\(type) goes straight to a build")
            try store.take(t.id, agent: "A")
            XCTAssertEqual(try store.ticket(id: t.id)?.status, .building)
            XCTAssertThrowsError(try store.move(t.id, to: .yourCall, actor: .hatch), "\(type) has no Your call")
            try walk(store, t.id, [(.toVerify, .hatch), (.merged, .hatch), (.done, .hatch)])
        }
    }

    func testAQuestionEndsAtYourCallAndIsClosedByTheOwner() throws {
        let (store, p) = try makeStore()
        let t = try store.createTicket(projectId: p.id, type: .question, title: "Why?", ghNumber: 400)
        try walk(store, t.id, [(.checking, .owner), (.ready, .hatch)])
        XCTAssertEqual(try store.agentWork().first?.kind, .prepare)
        try store.take(t.id, agent: "A")
        try walk(store, t.id, [(.yourCall, .hatch)])
        XCTAssertThrowsError(try store.move(t.id, to: .accepted, actor: .owner), "a Question is not accepted, it is answered")
        try walk(store, t.id, [(.done, .owner)])
    }

    func testAnAgentsQuestionReturnsTheTicketToWhereItWas() throws {
        let (store, p) = try makeStore()
        for (type, working): (TicketType, Status) in [(.tweak, .building), (.proposal, .preparing)] {
            let t = try store.createTicket(projectId: p.id, type: type, title: "Q \(type)", ghNumber: 500 + (type == .tweak ? 0 : 1))
            try walk(store, t.id, [(.checking, .owner), (.ready, .hatch)])
            try store.take(t.id, agent: "A")
            XCTAssertEqual(try store.ticket(id: t.id)?.status, working)
            let q = try store.ask(t.id, text: "Which?", suggestions: ["A", "B"], by: "A", actor: .agent)
            XCTAssertEqual(try store.ticket(id: t.id)?.status, .needsAnswers)
            XCTAssertNil(try store.ticket(id: t.id)?.takenBy)
            try store.answer(questionId: q.id, text: "A", by: "owner")
            XCTAssertEqual(try store.ticket(id: t.id)?.status, working, "\(type): the answer returns it to \(working)")
        }
    }

    func testBlockedAndParkedComeBackToTheStatusTheyLeft() throws {
        let (store, p) = try makeStore()
        let t = try store.createTicket(projectId: p.id, type: .tweak, title: "B", ghNumber: 600)
        try walk(store, t.id, [(.checking, .owner), (.ready, .hatch), (.building, .agent), (.blocked, .hatch)])
        XCTAssertTrue(try store.agentWork().isEmpty, "a Blocked ticket is nobody's work until resumed")
        XCTAssertEqual(try store.resume(t.id, actor: .owner).status, .building)
        try walk(store, t.id, [(.parked, .owner)])
        XCTAssertThrowsError(try store.resume(t.id, actor: .hatch), "Hatch does not resume what the owner parked")
        XCTAssertEqual(try store.resume(t.id, actor: .owner).status, .building)
    }

    func testDoneAndDroppedCanBeReopenedOnlyByTheOwner() throws {
        let (store, p) = try makeStore()
        let t = try store.createTicket(projectId: p.id, type: .theme, title: "G", ghNumber: 700)
        try walk(store, t.id, [(.done, .owner)])
        XCTAssertThrowsError(try store.move(t.id, to: .draft, actor: .hatch))
        try walk(store, t.id, [(.draft, .owner)])
        try walk(store, t.id, [(.dropped, .owner)])
        XCTAssertThrowsError(try store.move(t.id, to: .draft, actor: .agent))
        try walk(store, t.id, [(.draft, .owner)])
    }

    func testAgentWorkRespectsPriorityThenAgeAndNeverOffersATakenTicket() throws {
        let (store, p) = try makeStore()
        var made: [Ticket] = []
        for i in 0..<4 {
            let t = try store.createTicket(projectId: p.id, type: .tweak, title: "W\(i)", ghNumber: 800 + i)
            try walk(store, t.id, [(.checking, .owner), (.ready, .hatch)])
            made.append(t)
        }
        try store.update(made[2].id, actor: .owner, priority: TicketPriority.high)
        XCTAssertEqual(try store.agentWork().first?.ticket.id, made[2].id, "higher priority first")
        XCTAssertEqual(try store.agentWork().dropFirst().map(\.ticket.id), [made[0].id, made[1].id, made[3].id].sorted { a, b in
            (try? store.ticket(id: a)!.updatedAt) ?? .distantPast < (try? store.ticket(id: b)!.updatedAt) ?? .distantPast }, "then the oldest")
        try store.take(made[2].id, agent: "A")
        XCTAssertFalse(try store.agentWork().contains { $0.ticket.id == made[2].id })
    }
}

struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
