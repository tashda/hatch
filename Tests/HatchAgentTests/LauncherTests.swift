import XCTest
import HatchCore
import HatchGit
@testable import HatchAgent

final class AgentStreamTests: XCTestCase {
    func testStepsTokensAndTheResult() {
        XCTAssertEqual(AgentStream.parse(#"{"type":"system","subtype":"init","model":"claude-sonnet-5-5"}"#)?.model, "claude-sonnet-5-5")
        let edit = AgentStream.parse(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/w/Sources/ToastView.swift"}}],"usage":{"input_tokens":10,"output_tokens":5}}}"#)
        XCTAssertEqual(edit?.step, "Editing ToastView.swift")
        XCTAssertEqual(edit?.tokensOut, 5)
        XCTAssertEqual(AgentStream.parse(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"swift build\nswift test"}}]}}"#)?.step, "Running swift build")
        let result = AgentStream.parse(#"{"type":"result","subtype":"success","is_error":false,"result":"Done.","usage":{"input_tokens":100,"cache_read_input_tokens":900,"output_tokens":40}}"#)
        XCTAssertEqual(result?.finished, true)
        XCTAssertEqual(result?.isError, false)
        XCTAssertEqual(result?.tokensIn, 100, "cache reads are counted apart")
        XCTAssertEqual(result?.cacheTokens, 900)
        XCTAssertNil(AgentStream.parse("not json"))
    }

    func testClaudeGetsOnlyTheToolsTheWorkNeeds() {
        let args = AgentLauncher.claudeArguments(model: "claude-opus-5-5", effort: "high", otherDirectories: ["/w/notebook"],
                                                 commands: ["xcodebuild -scheme Echo build", "swift test --filter X"])
        XCTAssertEqual(Array(args.prefix(7)), ["-p", "--output-format", "stream-json", "--verbose", "--permission-mode", "dontAsk", "--allowedTools"])
        XCTAssertTrue(args.contains("Bash(xcodebuild *)"))
        XCTAssertTrue(args.contains("Bash(swift *)"))
        XCTAssertTrue(args.contains("Bash(hatch *)"))
        XCTAssertFalse(args.contains { $0.hasPrefix("WebFetch") })
        XCTAssertEqual(args[args.firstIndex(of: "--model")! + 1], "claude-opus-5-5")
        XCTAssertEqual(args[args.firstIndex(of: "--effort")! + 1], "high")
        XCTAssertEqual(args[args.firstIndex(of: "--add-dir")! + 1], "/w/notebook")
        // Only the allowed tools are defined, and no MCP servers or skills are loaded (they cost tokens on every turn).
        let defined = args[args.firstIndex(of: "--tools")! + 1].split(separator: ",").map(String.init)
        XCTAssertEqual(defined.filter { $0 == "Bash" }.count, 1)
        XCTAssertTrue(defined.contains("Read") && defined.contains("Edit"))
        XCTAssertFalse(defined.contains { $0.contains("(") || $0 == "WebFetch" || $0 == "Agent" })
        XCTAssertTrue(args.contains("--strict-mcp-config"))
        XCTAssertTrue(args.contains("--disable-slash-commands"))
    }

    func testWorkspacesPerKindOfWork() {
        XCTAssertEqual(AgentWorkspaces.roles(for: .build), [.app, .designSystem, .notebook])
        XCTAssertEqual(AgentWorkspaces.roles(for: .revise), [.specimens, .notebook], "revising works where preparing did")
        XCTAssertTrue(AgentWorkspaces.roles(for: .vet).isEmpty)
    }
}

/// The launcher end to end with a stand-in for Claude Code: a script that reads the brief and exits.
final class AgentLauncherTests: XCTestCase {
    var tmp: URL!
    var store: HatchStore!
    var ticket: Ticket!
    let git = ProcessGit(environment: ["GIT_AUTHOR_NAME": "T", "GIT_AUTHOR_EMAIL": "t@x", "GIT_COMMITTER_NAME": "T",
                                       "GIT_COMMITTER_EMAIL": "t@x", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"])

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().appendingPathComponent("launcher-\(UUID().uuidString)")
        let app = tmp.appendingPathComponent("app").path
        try FileManager.default.createDirectory(atPath: app, withIntermediateDirectories: true)
        try git.git(["init", "-q", "-b", "dev"], in: app)
        try "x".write(toFile: app + "/README.md", atomically: true, encoding: .utf8)
        try git.git(["add", "."], in: app); try git.git(["commit", "-qm", "start"], in: app)
        store = try HatchStore.inMemory()
        let project = try store.upsertProject(key: "echo", name: "Echo", config: ProjectConfig(name: "Echo", ticketsRepo: "acme/t",
            repos: [RepoConfig(role: .app, remote: "acme/app", branch: "dev", localPath: app, buildCommand: "swift build")]))
        ticket = try store.createTicket(projectId: project.id, type: .tweak, title: "Toast spacing", ghNumber: 151, status: .ready)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// A program that prints a little stream-json and exits with `code`, after `seconds`.
    func fakeClaude(code: Int, seconds: Double = 0) throws -> String {
        let path = tmp.appendingPathComponent("fake-claude").path
        let script = """
        #!/bin/sh
        cat > /dev/null
        echo '{"type":"system","subtype":"init","model":"claude-sonnet-5-5"}'
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"README.md"}}]}}'
        sleep \(seconds)
        echo '{"type":"result","subtype":"success","is_error":false,"result":"Gave up.","usage":{"input_tokens":10,"output_tokens":3}}'
        exit \(code)
        """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func launcher(program: String) -> AgentLauncher {
        var settings = AgentSettings.initial(detect: false)
        settings.providers[0].executable = program
        let frozen = settings
        return AgentLauncher(store: store, configuration: .init(home: tmp, hatchPath: "/usr/bin/true", context: AgentContext()),
                             settings: { frozen }, onChange: {})
    }

    func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 15) {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    }

    func testAnAgentThatStopsTwiceAsksTheOwner() throws {
        let l = launcher(program: try fakeClaude(code: 1))
        l.tick()
        XCTAssertEqual(try store.ticket(id: ticket.id)?.status, .building, "taken and moved into Building")
        waitUntil { (try? store.ticket(id: ticket.id))?.status == .needsAnswers }
        let after = try XCTUnwrap(store.ticket(id: ticket.id))
        XCTAssertEqual(after.status, .needsAnswers, "a second stop puts it on the owner's Desk")
        XCTAssertNil(after.takenBy)
        XCTAssertTrue(l.running.isEmpty)
        XCTAssertEqual(try store.questions(ticketId: ticket.id, openOnly: true).count, 1)
    }

    func testAHandedInRunIsLeftAlone() throws {
        let l = launcher(program: try fakeClaude(code: 0, seconds: 1.5))
        l.tick()
        waitUntil { !l.running.isEmpty }
        XCTAssertEqual(l.running.first?.ticketNumber, "#151")
        // What `hatch ready` does while the agent works.
        _ = try store.move(ticket.id, to: .toVerify, actor: .hatch, reason: "build passed")
        waitUntil { l.running.isEmpty }
        XCTAssertEqual(try store.ticket(id: ticket.id)?.status, .toVerify)
        XCTAssertTrue(try store.questions(ticketId: ticket.id).isEmpty)
    }

    func testStopBlocksTheTicket() throws {
        let l = launcher(program: try fakeClaude(code: 0, seconds: 20))
        l.tick()
        waitUntil { !l.running.isEmpty }
        l.stop(ticket.id)
        waitUntil { l.running.isEmpty }
        XCTAssertEqual(try store.ticket(id: ticket.id)?.status, .blocked)
    }

    func testNothingStartsWhilePausedOrWithoutTheHatchCommand() throws {
        let l = launcher(program: try fakeClaude(code: 0))
        try l.setPaused(true)
        l.tick()
        XCTAssertEqual(try store.ticket(id: ticket.id)?.status, .ready)
        try l.setPaused(false)
        l.update(.init(home: tmp, hatchPath: tmp.appendingPathComponent("missing").path, context: AgentContext()))
        XCTAssertThrowsError(try l.start(ticket.id)) { XCTAssertEqual($0 as? AgentLauncher.LaunchError, .noHatchCommand) }
        XCTAssertEqual(try store.ticket(id: ticket.id)?.status, .ready, "nothing taken when it cannot start")
    }
}
