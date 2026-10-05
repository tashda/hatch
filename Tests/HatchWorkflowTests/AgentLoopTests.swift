import XCTest
import HatchCore
import HatchGit
@testable import HatchAgent

/// Build, ask, crash and run side by side: see LoopSupport.swift for how the loop is set up. WORKFLOW.md, 3 and 4.
final class AgentLoopTests: LoopCase {
    // MARK: Building

    func testABuildAgentCommitsAndHandsInSoHatchMovesTheTicketToToVerify() throws {
        let t = try ticket(.tweak, "Toast padding")
        makeLauncher(program: try fakeClaude("""
        echo change > padding.txt && git add padding.txt && git -c user.name=A -c user.email=a@x commit -qm "Toast padding"
        hatch ready $T --spec unchanged > "$HATCH_HOME/ready.out" 2>&1
        """))
        launcher.tick()
        XCTAssertEqual(status(t), .building, "taken and moved to Building before the agent starts")
        waitUntil("the ticket reaches To verify") { self.status(t) == .toVerify }
        let after = try XCTUnwrap(world.store.ticket(id: t.id))
        XCTAssertNil(after.takenBy, "the agent's claim ends when it hands in")
        let ready = try String(contentsOf: world.home.appendingPathComponent("ready.out"), encoding: .utf8)
        XCTAssertTrue(ready.contains("All checks passed"), ready)
        // Hatch, not the agent, moved the status, and recorded why.
        let moves = try world.store.events(ticketId: t.id, kinds: ["status"]).compactMap { $0.payload["to"]?.stringValue }
        XCTAssertEqual(moves.suffix(2), ["building", "to-verify"])
        // The agent worked in a worktree on the ticket's branch, and the source clone was not touched.
        XCTAssertEqual(world.disturbedSources(), [])
        let ws = try world.store.workspaces(ticketId: t.id)
        XCTAssertTrue(try ws.contains { try world.git.git(["log", "--oneline", "-1"], in: $0.path).contains("Toast padding") }, "the commit is in the worktree")
    }

    func testReadyRefusesWhileTheWorkIsUncommittedAndTheTicketStaysBuilding() throws {
        let t = try ticket(.tweak, "Toast margin")
        makeLauncher(program: try fakeClaude("""
        echo change > margin.txt
        hatch ready $T --spec unchanged > "$HATCH_HOME/ready.out" 2>&1 || true
        """))
        launcher.tick()
        waitUntil("the agent finished") { self.launcher.running.isEmpty && FileManager.default.fileExists(atPath: self.world.home.appendingPathComponent("ready.out").path) }
        let out = try String(contentsOf: world.home.appendingPathComponent("ready.out"), encoding: .utf8)
        XCTAssertTrue(out.contains("Commit or stash"), "the agent is told what to do: \(out)")
        XCTAssertNotEqual(status(t), .toVerify, "an agent cannot reach To verify with uncommitted work")
    }

    func testAnAgentCannotMoveItsOwnTicketWithAnyCommand() throws {
        let t = try ticket(.tweak, "Toast corner")
        makeLauncher(program: try fakeClaude("""
        hatch admin move $T to-verify --as agent > "$HATCH_HOME/move.out" 2>&1 || true
        hatch admin move $T done --as agent >> "$HATCH_HOME/move.out" 2>&1 || true
        """))
        launcher.tick()
        waitUntil("the agent finished") { self.launcher.running.isEmpty && FileManager.default.fileExists(atPath: self.world.home.appendingPathComponent("move.out").path) }
        XCTAssertNotEqual(status(t), .toVerify)
        XCTAssertNotEqual(status(t), .done)
    }

    // MARK: Asking

    func testAnAgentThatAsksWaitsForTheOwnerAndWorkResumesWhereItStopped() throws {
        let t = try ticket(.tweak, "Toast duration")
        // First run asks; second run (after the answer) finishes. The script decides from a marker file.
        makeLauncher(program: try fakeClaude("""
        if [ ! -f "$HATCH_HOME/asked" ]; then
          touch "$HATCH_HOME/asked"
          hatch ask $T "Should the toast last 3 or 5 seconds?" --suggest "3 seconds" --suggest "5 seconds" > "$HATCH_HOME/ask.out" 2>&1
        else
          echo done > duration.txt && git add duration.txt && git -c user.name=A -c user.email=a@x commit -qm duration
          hatch ready $T --spec unchanged > "$HATCH_HOME/ready.out" 2>&1
        fi
        """))
        launcher.tick()
        waitUntil("the ticket waits for an answer") { self.status(t) == .needsAnswers }
        waitUntil("the first run ended") { self.launcher.running.isEmpty }
        let open = try world.store.questions(ticketId: t.id, openOnly: true)
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open.first?.suggestions.first, "3 seconds", "the recommendation comes first")
        XCTAssertNil(try world.store.ticket(id: t.id)?.takenBy, "an agent that waits for the owner holds no claim")
        launcher.tick()
        XCTAssertEqual(status(t), .needsAnswers, "nothing starts while a question is open")

        try world.store.answer(questionId: open[0].id, text: "3 seconds", by: "owner")
        XCTAssertEqual(status(t), .building, "the answer returns the ticket to where it was")
        launcher.tick()
        waitUntil("the second run hands in") { self.status(t) == .toVerify }
        let brief = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: world.home.path).filter { $0.hasPrefix("last-brief") }.sorted().last
            .map { try String(contentsOfFile: world.home.appendingPathComponent($0).path, encoding: .utf8) })
        XCTAssertTrue(brief.contains("3 seconds"), "the owner's answer is in the next brief")
    }

    func testAQuestionWithNoSuggestionIsRefused() throws {
        let t = try ticket(.tweak, "Toast fade")
        makeLauncher(program: try fakeClaude("""
        hatch ask $T "What do you want?" > "$HATCH_HOME/ask.out" 2>&1 || true
        """))
        launcher.tick()
        waitUntil("the agent finished") { self.launcher.running.isEmpty && FileManager.default.fileExists(atPath: self.world.home.appendingPathComponent("ask.out").path) }
        XCTAssertTrue(try world.store.questions(ticketId: t.id).isEmpty, "IR17: a question needs a suggested answer")
    }

    // MARK: Failing

    func testAnAgentThatCrashesIsRetriedOnceThenBlockedWithItsLastLinesInTheThread() throws {
        let t = try ticket(.tweak, "Toast shadow")
        makeLauncher(program: try fakeClaude("""
        echo "something broke in the build" >&2
        exit 3
        """))
        launcher.tick()
        waitUntil("the ticket is blocked", timeout: 60) { self.status(t) == .blocked }
        let notes = try world.store.notes(ticketId: t.id).map(\.body).joined(separator: "\n")
        XCTAssertTrue(notes.contains("stopped before handing in"), "the retry is announced")
        XCTAssertTrue(notes.contains("something broke"), "the last lines of the log are on the ticket")
        XCTAssertTrue(try world.store.questions(ticketId: t.id).isEmpty)
        XCTAssertNil(try world.store.ticket(id: t.id)?.takenBy)
    }

    // MARK: Two agents

    func testTwoTicketsRunSideBySideInSeparateWorktreesAndNeitherSeesTheOther() throws {
        let a = try ticket(.tweak, "Toast alpha"), b = try ticket(.tweak, "Toast beta")
        makeLauncher(program: try fakeClaude("""
        echo "$T" > mine.txt && git add mine.txt && git -c user.name=A -c user.email=a@x commit -qm "$T"
        sleep 1
        ls > "$HATCH_HOME/ls-${T#\\#}.out"
        hatch ready $T --spec unchanged > /dev/null 2>&1
        """))
        launcher.tick()
        waitUntil("both hand in", timeout: 60) { self.status(a) == .toVerify && self.status(b) == .toVerify }
        for t in [a, b] {
            let listing = try String(contentsOf: world.home.appendingPathComponent("ls-\(t.displayNumber.dropFirst()).out"), encoding: .utf8)
            XCTAssertTrue(listing.contains("mine.txt"))
        }
        let paths = try [a, b].map { try world.store.workspaces(ticketId: $0.id).map(\.path) }
        XCTAssertTrue(Set(paths[0]).isDisjoint(with: Set(paths[1])), "no worktree is shared")
        XCTAssertEqual(world.disturbedSources(), [])
    }
}

