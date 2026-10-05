import XCTest
import HatchCore
@testable import HatchAgent

/// Two agents that want the same file take turns: the second is told to stop, its ticket waits, and it resumes by itself when the
/// first hands in. WORKFLOW.md, 4 (the claim system, WF-B2).
final class ClaimLoopTests: LoopCase {
    func testTwoAgentsOnTheSameFileTakeTurnsWithoutAnyoneAskingTheOwner() throws {
        let a = try ticket(.tweak, "Toast first"), b = try ticket(.tweak, "Toast second")
        makeLauncher(program: try fakeClaude("""
        hatch plan $T --files "Echo/Toast/ToastView.swift" > "$HATCH_HOME/plan-${T#\\#}-$$.out" 2>&1
        if grep -q "Claim granted" "$HATCH_HOME/plan-${T#\\#}-$$.out"; then
          touch "$HATCH_HOME/holding-${T#\\#}"
          for i in $(seq 1 120); do [ -f "$HATCH_HOME/go" ] && break; sleep 0.5; done
          echo "$T" > "toast-${T#\\#}.txt" && git add . && git -c user.name=A -c user.email=a@x commit -qm "$T"
          hatch ready $T --spec unchanged > "$HATCH_HOME/ready-${T#\\#}.out" 2>&1
        fi
        """))
        launcher.tick()
        // One holds the claim; the other was told to stop and its ticket waits.
        waitUntil("one ticket is blocked behind the other", timeout: 40) { [self.status(a), self.status(b)].contains(.blocked) }
        let (holder, waiting) = status(a) == .blocked ? (b, a) : (a, b)
        waitUntil("the holder is working") { FileManager.default.fileExists(atPath: self.world.home.appendingPathComponent("holding-\(holder.displayNumber.dropFirst())").path) }
        XCTAssertEqual(status(holder), .building)
        XCTAssertTrue(try world.store.questions(ticketId: waiting.id).isEmpty, "waiting for files is not a question for the owner")
        let note = try world.store.events(ticketId: waiting.id, kinds: ["status"]).last?.payload["reason"]?.stringValue ?? ""
        XCTAssertFalse(note.isEmpty)

        // The holder finishes; Hatch releases its claim and the waiting ticket resumes by itself.
        FileManager.default.createFile(atPath: world.home.appendingPathComponent("go").path, contents: Data())
        waitUntil("the holder hands in", timeout: 60) { self.status(holder) == .toVerify }
        waitUntil("the waiting ticket is back in Building without anyone resuming it", timeout: 30) { self.status(waiting) == .building }
        launcher.tick()
        waitUntil("and its agent finishes too", timeout: 60) { self.status(waiting) == .toVerify }
        XCTAssertEqual(world.disturbedSources(), [])
    }
}
