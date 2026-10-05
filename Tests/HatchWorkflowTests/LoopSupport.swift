import XCTest
import HatchCore
import HatchGit
@testable import HatchAgent

/// The whole loop with nothing faked but the model: the real launcher makes the workspaces and starts a stand-in "Claude"
/// (a shell script) that works in its worktree and calls the real `hatch` command, which changes the same database. What an
/// agent may do, and what Hatch does about it, is checked at the status each step leaves the ticket in. See WORKFLOW.md, 3 and 4.
class LoopCase: XCTestCase {
    var world: IrisEvalWorld!
    var project: Project!
    var launcher: AgentLauncher!
    var hatch: String!

    override func setUpWithError() throws {
        // The command is built beside the test bundle because the test target depends on it.
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let path = products.appendingPathComponent("hatch").path
        guard FileManager.default.isExecutableFile(atPath: path) else { throw XCTSkip("hatch is not built next to the tests (\(path))") }
        hatch = path
        world = try IrisEvalWorld(fileBacked: true, buildCommand: "true")
        project = world.projects["echo"]!
    }

    override func tearDownWithError() throws {
        launcher?.setPausedQuietly()
        // A failing test shows what the agent's hatch commands said, which is usually the whole story.
        if (testRun?.failureCount ?? 0) > 0, let home = world?.home, let files = try? FileManager.default.contentsOfDirectory(atPath: home.path) {
            for f in files.sorted() where f.hasSuffix(".out") {
                print("---- \(f)\n" + ((try? String(contentsOfFile: home.appendingPathComponent(f).path, encoding: .utf8)) ?? ""))
            }
        }
        world?.tearDown()
    }

    /// A "Claude" that runs `body` (shell) in its workspace with the ticket number in $T. The brief on stdin is kept in $HATCH_HOME/last-brief.
    func fakeClaude(_ body: String) throws -> String {
        let path = world.root.appendingPathComponent("fake-claude-\(UUID().uuidString.prefix(6))").path
        let script = """
        #!/bin/bash
        cd "$(pwd)"
        cat > "$HATCH_HOME/last-brief-$$.md"
        T=$(head -1 "$HATCH_HOME/last-brief-$$.md" | sed -E 's/^# (#[0-9]+).*/\\1/')
        echo '{"type":"system","subtype":"init","model":"claude-sonnet-5-5"}'
        \(body)
        echo '{"type":"result","subtype":"success","is_error":false,"result":"done","usage":{"input_tokens":10,"output_tokens":3}}'
        """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func makeLauncher(program: String, maxSeconds: TimeInterval? = nil) {
        var settings = AgentSettings.initial(detect: false)
        settings.providers[0].executable = program
        let frozen = settings
        launcher = AgentLauncher(store: world.store, configuration: .init(home: world.home, hatchPath: hatch, context: AgentContext(), maxSeconds: maxSeconds),
                                 settings: { frozen }, onChange: {})
    }

    func waitUntil(_ what: String, timeout: TimeInterval = 40, _ condition: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        XCTAssertTrue(condition(), "timed out waiting for: \(what)")
    }

    func ticket(_ type: TicketType, _ title: String, status: Status = .ready) throws -> Ticket {
        try world.store.createTicket(projectId: project.id, type: type, title: title, body: "A change.", area: "Notifications", ghNumber: world.number(), status: status)
    }
    func status(_ t: Ticket) -> Status? { try? world.store.ticket(id: t.id)?.status }
}

extension AgentLauncher {
    func setPausedQuietly() { try? setPaused(true) }
}
