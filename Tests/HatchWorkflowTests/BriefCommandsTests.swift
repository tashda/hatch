import XCTest
import HatchCore
@testable import HatchAgent

/// A brief that names a command the CLI does not have costs the agent a turn and a refusal. Every `hatch <command>` in every
/// brief, for every kind of work and every ticket type, must be a real command, and every non-hatch program must be allowed.
final class BriefCommandsTests: LoopCase {
    func testEveryHatchCommandInEveryBriefExists() throws {
        var seen: Set<String> = []
        for type in TicketType.allCases {
            for kind in [AgentTaskKind.prepare, .revise, .build, .fix, .vet] {
                let t = try ticket(type, "Brief \(type) \(kind)", status: .ready)
                let brief = try BriefBuilder.brief(store: world.store, ticketId: t.id, agent: "A", kind: kind)
                let re = try NSRegularExpression(pattern: "hatch ([a-z][a-z-]*)")
                for m in re.matches(in: brief, range: NSRange(brief.startIndex..., in: brief)) { seen.insert(String(brief[Range(m.range(at: 1), in: brief)!])) }
            }
        }
        XCTAssertGreaterThan(seen.count, 6, "the briefs mention a good range of commands: \(seen.sorted())")
        for command in seen.sorted() {
            let out = run(hatch, [command, "--help"])
            XCTAssertFalse(out.contains("Unknown command"), "a brief tells the agent to run `hatch \(command)`, which does not exist")
        }
    }

    func testEveryProgramTheBriefNamesIsOneTheAgentMayRun() throws {
        let t = try ticket(.tweak, "Allowed", status: .ready)
        let brief = try BriefBuilder.brief(store: world.store, ticketId: t.id, agent: "A", kind: .build)
        let repos = try world.store.repos(projectId: project.id)
        let commands = repos.compactMap(\.buildCommand)
        let args = AgentLauncher.claudeArguments(model: nil, effort: nil, otherDirectories: [], commands: commands)
        let allowed = Set(args.drop { $0 != "--allowedTools" }.dropFirst().prefix { !$0.hasPrefix("--") })
        // Programs named in backticks or after "run": the build commands, git, hatch.
        for c in commands {
            let program = String(c.split(separator: " ")[0])
            XCTAssertTrue(allowed.contains("Bash(\(program) *)"), "the build command `\(c)` is in the brief but \(program) is not allowed")
            XCTAssertTrue(brief.contains(c), "the brief carries the build command")
        }
        XCTAssertTrue(allowed.contains("Bash(git *)") && allowed.contains("Bash(hatch *)"))
        for destructive in ["rm", "mv", "sed", "find", "tee", "curl", "sudo", "chmod"] {
            XCTAssertFalse(allowed.contains("Bash(\(destructive) *)"), "\(destructive) must stay refused")
        }
    }

    func testTheBriefNeverTellsAnAgentToChangeAStatusItself() throws {
        for type in TicketType.allCases {
            for kind in [AgentTaskKind.prepare, .revise, .build, .fix] {
                let t = try ticket(type, "Status \(type) \(kind)", status: .ready)
                let brief = try BriefBuilder.brief(store: world.store, ticketId: t.id, agent: "A", kind: kind)
                XCTAssertFalse(brief.contains("hatch admin"), "\(type) \(kind): agents never use admin commands")
                XCTAssertFalse(brief.contains("--as agent"))
                XCTAssertTrue(brief.contains("Hatch changes the status, never you"), "\(type) \(kind)")
                XCTAssertTrue(brief.contains("--suggest"), "\(type) \(kind): how to ask carries the suggestion rule")
            }
        }
    }

    func run(_ path: String, _ arguments: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        p.environment = ["HATCH_HOME": world.home.path, "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try? p.run()
        p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
