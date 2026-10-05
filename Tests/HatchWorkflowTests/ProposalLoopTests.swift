import XCTest
import HatchCore
@testable import HatchAgent

/// A Proposal through the real launcher and the real `hatch offer`: prepared, refused by the gate, fixed, offered, sent back by the
/// owner, revised, accepted and built. WORKFLOW.md, 4 and 5.
final class ProposalLoopTests: LoopCase {
    func manifest(revision: Int, recommend: String? = "quiet", extraChoice: Bool = false) -> ProposalManifest {
        var scenarios = StandardScenarios.all.map { ManifestScenario(id: $0.id, title: $0.title) }
        scenarios[1] = ManifestScenario(id: "hover", title: "Hover", applicable: false, notApplicableReason: "A toast has no pointer target.")
        var choices = [ManifestChoice(id: "quiet", name: "Quiet"), ManifestChoice(id: "bold", name: "Bold")]
        if extraChoice { choices.append(ManifestChoice(id: "calm", name: "Calm", addedIn: revision)) }
        return ProposalManifest(
            revision: revision, specs: ["NOTIF-1.2"], summary: "Tighter toast padding. Changes NOTIF-1.2.", asked: "Make toasts less cramped.",
            controls: [ManifestControl(id: "style", title: "Style", choices: choices, defaultChoice: "quiet",
                                       question: "Look at the toast in dark mode, then say which reads better.", recommend: recommend,
                                       why: recommend == nil ? nil : "It matches the other banners and costs no new tokens.")],
            specimens: [
                ManifestSpecimen(id: "today", title: "Today", isEchoToday: true, designWidth: 340, designHeight: 480),
                ManifestSpecimen(id: "a", title: "Tight", designWidth: 340, designHeight: 480, gain: "Fits more on screen", cost: "Feels cramped in dark mode"),
                ManifestSpecimen(id: "b", title: "Airy", designWidth: 400, designHeight: 480, gain: "Calmer and easier to read", cost: "Shows fewer toasts at once")],
            questions: [],
            exhibitTopic: ManifestTopic(question: "Which proposal do you prefer?", recommended: "a", why: "It beats Today without adding height."),
            presets: [ManifestPreset(id: "rec", name: "My recommendation", values: ["style": "quiet"], isRecommended: true)],
            scenarios: scenarios)
    }

    func write(_ m: ProposalManifest, as name: String) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        try enc.encode(m).write(to: world.home.appendingPathComponent(name))
    }

    func testAProposalIsRefusedThenFixedThenOfferedThenSentBackThenRevisedThenAcceptedThenBuilt() throws {
        let t = try ticket(.proposal, "Toast look")
        // A first manifest that breaks the rule "every suggestion carries one recommendation and its reason", and a good one.
        try write(manifest(revision: 1, recommend: nil), as: "bad.json")
        try write(manifest(revision: 1), as: "good-1.json")
        try write(manifest(revision: 2, extraChoice: true), as: "good-2.json")
        makeLauncher(program: try fakeClaude("""
        TASK=$(grep -m1 -o 'Task: [a-z]*' "$HATCH_HOME/last-brief-$$.md" | cut -d' ' -f2)
        echo "$TASK" >> "$HATCH_HOME/tasks.log"
        case "$(sed -n 2p "$HATCH_HOME/last-brief-$$.md")" in
          *"prepare what"*)
            hatch offer $T "$HATCH_HOME/bad.json" > "$HATCH_HOME/offer-bad.out" 2>&1 || true
            hatch offer $T "$HATCH_HOME/good-1.json" > "$HATCH_HOME/offer-1.out" 2>&1 ;;
          *"revise the offer"*)
            hatch offer $T "$HATCH_HOME/good-2.json" > "$HATCH_HOME/offer-2.out" 2>&1 ;;
          *"build the change"*)
            echo built > toast.txt && git add toast.txt && git -c user.name=A -c user.email=a@x commit -qm built
            hatch ready $T --spec unchanged > "$HATCH_HOME/ready.out" 2>&1 ;;
        esac
        """))

        // 1. Prepare: the gate refuses the first manifest and the agent fixes it.
        launcher.tick()
        XCTAssertEqual(status(t), .preparing)
        waitUntil("the offer reaches Your call") { self.status(t) == .yourCall }
        let bad = try String(contentsOf: world.home.appendingPathComponent("offer-bad.out"), encoding: .utf8)
        XCTAssertTrue(bad.contains("Not offered"), bad)
        XCTAssertTrue(bad.contains("fix:"), "the agent is told how to fix it: \(bad)")
        XCTAssertEqual(try world.store.ticket(id: t.id)?.revision, 1)
        XCTAssertNil(try world.store.ticket(id: t.id)?.takenBy)
        waitUntil("the agent ended") { self.launcher.running.isEmpty }
        launcher.tick()
        XCTAssertEqual(status(t), .yourCall, "nothing starts while the owner has the turn")

        // 2. The owner sends it back; the agent revises and may only add to the options.
        _ = try world.store.move(t.id, to: .revising, actor: .owner, reason: "one more look")
        launcher.tick()
        waitUntil("the revision reaches Your call") { self.status(t) == .yourCall && ((try? self.world.store.ticket(id: t.id)?.revision) ?? 0) == 2 }
        let kinds = try String(contentsOf: world.home.appendingPathComponent("tasks.log"), encoding: .utf8)
        XCTAssertEqual(kinds.split(separator: "\n").map(String.init), ["prepare", "revise"])
        waitUntil("the agent ended") { self.launcher.running.isEmpty }

        // 3. The owner accepts: Hatch moves it to Accepted and a build agent takes it.
        _ = try world.store.move(t.id, to: .accepted, actor: .owner, reason: "accepted")
        XCTAssertEqual(try world.store.agentWork().first?.kind, .build)
        launcher.tick()
        waitUntil("built and handed in") { self.status(t) == .toVerify }
        XCTAssertEqual(world.disturbedSources(), [])
        // Every status change in the ticket's history was made by Hatch or the owner, never by the agent's own say-so.
        let moves = try world.store.events(ticketId: t.id, kinds: ["status"])
        let byAgent = moves.filter { $0.actor == "agent" }.compactMap { $0.payload["to"]?.stringValue }
        XCTAssertTrue(Set(byAgent).isSubset(of: ["preparing", "building", "needs-answers"]), "an agent only ever takes work: \(byAgent)")
    }

    func testARevisionThatDropsAnEarlierOptionIsRefusedWithAReason() throws {
        let t = try ticket(.proposal, "Toast shape")
        try write(manifest(revision: 1), as: "m1.json")
        var dropped = manifest(revision: 2)
        dropped.controls[0].choices = [ManifestChoice(id: "bold", name: "Bold")]   // "quiet" was offered before
        dropped.controls[0].defaultChoice = "bold"; dropped.controls[0].recommend = "bold"
        dropped.presets[0].values = ["style": "bold"]
        try write(dropped, as: "m2.json")
        makeLauncher(program: try fakeClaude("""
        if [ ! -f "$HATCH_HOME/offered" ]; then touch "$HATCH_HOME/offered"; hatch offer $T "$HATCH_HOME/m1.json" > /dev/null 2>&1
        else hatch offer $T "$HATCH_HOME/m2.json" > "$HATCH_HOME/revise.out" 2>&1 || true; fi
        """))
        launcher.tick()
        waitUntil("Your call") { self.status(t) == .yourCall }
        waitUntil("ended") { self.launcher.running.isEmpty }
        _ = try world.store.move(t.id, to: .revising, actor: .owner)
        launcher.tick()
        waitUntil("the revision attempt finished") { FileManager.default.fileExists(atPath: self.world.home.appendingPathComponent("revise.out").path) && self.launcher.running.isEmpty }
        let out = try String(contentsOf: world.home.appendingPathComponent("revise.out"), encoding: .utf8)
        XCTAssertTrue(out.contains("Not offered"), out)
        XCTAssertEqual(try world.store.ticket(id: t.id)?.revision, 1, "a refused revision changes nothing")
        XCTAssertNotEqual(status(t), .yourCall, "the ticket is still the agent's: it did not hand in")
    }
}
