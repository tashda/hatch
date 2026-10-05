import XCTest
import HatchCore
@testable import HatchAgent

/// A coding agent that runs away is the one thing that can spend a lot of someone's Claude usage, so Hatch stops it itself: at a
/// token budget per run and at the role's time limit. The ticket is Blocked with the reason, never retried by itself, and its work
/// stays in the workspace. WORKFLOW.md, 4.
final class AgentLimitTests: LoopCase {
    func usageLine(_ tokens: Int) -> String {
        #"echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}],"usage":{"input_tokens":\#(tokens),"output_tokens":10}}}'"#
    }

    func testAnAgentOverTheTokenBudgetIsStoppedAndTheTicketIsBlockedWithTheReason() throws {
        let t = try ticket(.tweak, "Runaway")
        makeLauncher(program: try fakeClaude("""
        echo partial > partial.txt
        \(usageLine(900_000))
        \(usageLine(900_000))
        sleep 60
        """))
        try launcher.setTokenBudget(1_000_000)
        launcher.tick()
        waitUntil("the ticket is blocked at the limit", timeout: 30) { self.status(t) == .blocked }
        XCTAssertNil(try world.store.ticket(id: t.id)?.takenBy)
        let notes = try world.store.notes(ticketId: t.id).map(\.body).joined(separator: "\n")
        XCTAssertTrue(notes.contains("Hatch stopped the agent"), notes)
        XCTAssertTrue(notes.contains("over the limit"), "the note says why: \(notes)")
        XCTAssertTrue(try world.store.questions(ticketId: t.id).isEmpty, "not a question the owner has to answer")
        waitUntil("no run is left") { self.launcher.running.isEmpty }
        // Not retried by itself: the ticket stays Blocked and nothing starts again.
        launcher.tick()
        XCTAssertEqual(status(t), .blocked)
        XCTAssertTrue(launcher.running.isEmpty)
        // The work is still in the workspace for whoever resumes it.
        let ws = try XCTUnwrap(world.store.workspaces(ticketId: t.id).first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ws.path + "/partial.txt") || (try? world.store.workspaces(ticketId: t.id).contains { FileManager.default.fileExists(atPath: $0.path + "/partial.txt") }) == true)
    }

    func testAnAgentWithinTheBudgetIsLeftAlone() throws {
        let t = try ticket(.tweak, "Modest")
        makeLauncher(program: try fakeClaude("""
        \(usageLine(40_000))
        echo ok > ok.txt && git add ok.txt && git -c user.name=A -c user.email=a@x commit -qm ok
        hatch ready $T --spec unchanged > /dev/null 2>&1
        """))
        try launcher.setTokenBudget(1_000_000)
        launcher.tick()
        waitUntil("handed in", timeout: 40) { self.status(t) == .toVerify }
    }

    func testABudgetOfZeroMeansNoLimit() throws {
        let t = try ticket(.tweak, "Unlimited")
        makeLauncher(program: try fakeClaude("""
        \(usageLine(9_000_000))
        echo ok > ok.txt && git add ok.txt && git -c user.name=A -c user.email=a@x commit -qm ok
        hatch ready $T --spec unchanged > /dev/null 2>&1
        """))
        try launcher.setTokenBudget(0)
        launcher.tick()
        waitUntil("handed in", timeout: 40) { self.status(t) == .toVerify }
    }

    func testTheDefaultBudgetIsGenerousButFinite() throws {
        makeLauncher(program: "/usr/bin/true")
        XCTAssertEqual(launcher.tokenBudget, AgentLauncher.defaultTokenBudget)
        XCTAssertGreaterThanOrEqual(AgentLauncher.defaultTokenBudget, 500_000, "a big change must not be cut off")
        XCTAssertLessThanOrEqual(AgentLauncher.defaultTokenBudget, 3_000_000, "a runaway must be")
        try launcher.setTokenBudget(123)
        XCTAssertEqual(launcher.tokenBudget, 123)
    }

    func testAnAgentThatRunsPastItsTimeLimitIsStoppedAndBlocked() throws {
        let t = try ticket(.tweak, "Slow")
        makeLauncher(program: try fakeClaude("sleep 120"), maxSeconds: 3)
        launcher.tick()
        waitUntil("the ticket is blocked at the time limit", timeout: 30) { self.status(t) == .blocked }
        let notes = try world.store.notes(ticketId: t.id).map(\.body).joined(separator: "\n")
        XCTAssertTrue(notes.contains("ran for more than"), notes)
        XCTAssertNil(try world.store.ticket(id: t.id)?.takenBy)
    }

    func testResumingAfterALimitStartsTheAgentAgain() throws {
        let t = try ticket(.tweak, "Resume after limit")
        makeLauncher(program: try fakeClaude("""
        if [ ! -f "$HATCH_HOME/once" ]; then touch "$HATCH_HOME/once"; \(usageLine(2_000_000)); sleep 60; fi
        echo ok > ok.txt && git add ok.txt && git -c user.name=A -c user.email=a@x commit -qm ok
        hatch ready $T --spec unchanged > /dev/null 2>&1
        """))
        try launcher.setTokenBudget(1_000_000)
        launcher.tick()
        waitUntil("blocked at the limit", timeout: 30) { self.status(t) == .blocked }
        waitUntil("run ended") { self.launcher.running.isEmpty }
        _ = try world.store.resume(t.id, actor: .owner)
        launcher.tick()
        waitUntil("the second run hands in", timeout: 40) { self.status(t) == .toVerify }
    }
}
