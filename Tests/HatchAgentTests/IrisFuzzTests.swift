import XCTest
import HatchCore
@testable import HatchAgent

/// Whatever a model sends, Hatch never crashes, never lets the answer break a rule in WORKFLOW.md, and either files the ticket or
/// says plainly why it could not. Seeded: `HATCH_FUZZ_SEED=5 HATCH_FUZZ_COUNT=5000 swift test --filter IrisFuzzTests`.
final class IrisFuzzTests: XCTestCase {
    var seed: UInt64 { UInt64(ProcessInfo.processInfo.environment["HATCH_FUZZ_SEED"] ?? "") ?? 424242 }
    var count: Int { Int(ProcessInfo.processInfo.environment["HATCH_FUZZ_COUNT"] ?? "") ?? 400 }

    static let valid = ##"{"path":"small","title":"Toast padding","reading":"Element: toast. Change: more padding.","assumed":["It is the toast"],"area":"Notifications","priority":"normal","verify":"preview","confidence":{"path":0.9},"questions":[{"text":"Which toast?","suggestions":["Save","Error"],"stakes":"high","about":"","rerun":false}],"duplicateOf":"","duplicateSure":false,"duplicateWhy":"","split":[{"title":"A","body":"","path":"small"},{"title":"B","body":"","path":"bug"}],"specTouches":["NOTIF-1.2"],"related":[{"ticket":"#1","why":"same"}]}"##

    /// Checks everything that must hold after Iris's answer was applied to a Checking ticket, whatever the answer was.
    func assertRulesHold(_ store: HatchStore, _ ticket: Ticket, _ project: Project, context: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let t = try XCTUnwrap(store.ticket(id: ticket.id))
        XCTAssertNotEqual(t.status, .checking, "\(context): the ticket left Checking", file: file, line: line)
        XCTAssertTrue([Status.ready, .needsAnswers, .dropped].contains(t.status), "\(context): ended in \(t.status)", file: file, line: line)
        XCTAssertLessThanOrEqual(t.priority, TicketPriority.normal, "\(context): priority", file: file, line: line)
        XCTAssertEqual(t.projectId, project.id, "\(context): project", file: file, line: line)
        if let area = t.area { XCTAssertTrue(project.config?.areas.contains { $0.name == area } == true, "\(context): area \(area)", file: file, line: line) }
        XCTAssertLessThanOrEqual(try store.questions(ticketId: t.id, openOnly: true).count, 1, "\(context): questions", file: file, line: line)
        XCTAssertEqual(t.originalTitle ?? t.title, ticket.title, "\(context): the owner's title is kept", file: file, line: line)
        if t.status == .needsAnswers { XCTAssertEqual(try store.questions(ticketId: t.id, openOnly: true).count, 1, "\(context): waiting without a question", file: file, line: line) }
        if t.status == .ready { XCTAssertTrue(try store.questions(ticketId: t.id, openOnly: true).isEmpty, "\(context): ready with a question open", file: file, line: line) }
        // The workflow must still accept the ticket: it can be parked, which every open status allows.
        if t.status != .dropped { XCTAssertTrue(Workflow.isAllowed(type: t.type, from: t.status, to: .parked, actor: .owner), file: file, line: line) }
        for part in try store.tickets(TicketFilter(projectId: project.id)) where part.parentId == t.id || part.title.hasPrefix("part-") {
            XCTAssertEqual(part.projectId, project.id, file: file, line: line)
        }
    }

    func world() throws -> (HatchStore, Project) {
        let store = try HatchStore.inMemory()
        let p = try store.upsertProject(key: "echo", name: "Echo", config: ProjectConfig(name: "Echo", ticketsRepo: "a/t", repos: [],
            areas: [AreaConfig(name: "Notifications", paths: [], specPrefix: "NOTIF"), AreaConfig(name: "Settings", paths: [], specPrefix: "SET")], docs: []))
        return (store, p)
    }

    func newTicket(_ store: HatchStore, _ p: Project, _ i: Int) throws -> Ticket {
        try store.createTicket(projectId: p.id, type: .question, title: "Toast \(i)", body: "Body \(i)", ghNumber: 1000 + i, status: .checking)
    }

    // MARK: Garbled text

    /// Truncated, wrapped, shuffled and corrupted copies of a good answer.
    func testCorruptedAnswersAreRefusedOrAppliedNeverCrash() throws {
        let (store, p) = try world()
        var rng = IrisEval.Random(seed: seed)
        var parsed = 0, refused = 0
        for i in 0..<count {
            let text = Self.mutate(Self.valid, &rng)
            let t = try newTicket(store, p, i)
            let runner = ScriptedRunner(text: text, tokensIn: 100, tokensOut: 20)
            let outcome = try VettingService(store: store, runner: runner).vet(ticketId: t.id)
            switch outcome {
            case .vetted: parsed += 1; try assertRulesHold(store, t, p, context: "case \(i) \(text.prefix(120))")
            case .failed(let why):
                refused += 1
                XCTAssertFalse(why.isEmpty)
                XCTAssertEqual(try store.ticket(id: t.id)?.status, .checking, "an unusable answer leaves the ticket in Checking (case \(i))")
                XCTAssertTrue(try store.events(ticketId: t.id, kinds: ["vetting-failed"]).count == 1, "and says so on the ticket (case \(i))")
            }
        }
        XCTAssertGreaterThan(parsed, count / 10, "some mutations still parse")
        XCTAssertGreaterThan(refused, count / 10, "some are refused")
    }

    static func mutate(_ s: String, _ rng: inout IrisEval.Random) -> String {
        var t = s
        for _ in 0..<Int.random(in: 1...3, using: &rng) {
            switch Int.random(in: 0..<14, using: &rng) {
            case 0: t = String(t.prefix(Int.random(in: 0..<t.count, using: &rng)))                         // cut off
            case 1: t = "Sure! Here you go:\n```json\n\(t)\n```\nAnything else?"                          // chatty
            case 2: t = "{\"note\": \"first\"}\n" + t                                                       // an earlier object
            case 3: t = t.replacingOccurrences(of: "\"small\"", with: ["\"Small\"", "\"smal\"", "42", "null", "[]", "\"\""].randomElement(using: &rng)!)
            case 4: t = t.replacingOccurrences(of: "\"questions\":[", with: "\"questions\":[1, null, [], {}, ")
            case 5: t = t.replacingOccurrences(of: "\"priority\":\"normal\"", with: "\"priority\":\(["\"urgent\"", "9", "-3", "\"HIGH\"", "true"].randomElement(using: &rng)!)")
            case 6: t = t.replacingOccurrences(of: "\"confidence\":{\"path\":0.9}", with: "\"confidence\":\(["{\"path\":\"high\"}", "5", "[0.2]", "{\"path\":1e999}", "null"].randomElement(using: &rng)!)")
            case 7: t = t.replacingOccurrences(of: "\"split\":[", with: "\"split\":[null, 3, {\"title\":\"\"}, ")
            case 8: if let r = t.range(of: "\"reading\":\"") { t.replaceSubrange(r, with: "\"reading\":\"" + String(repeating: "x", count: Int.random(in: 1000...30000, using: &rng))) }
            case 9: t = t.replacingOccurrences(of: "Toast padding", with: ["", "\u{0}\u{1}\u{7}", "𝕋𝕠𝕒𝕤𝕥 🍞", "a\\nb\\tc", "\\u0000", "<script>alert(1)</script>", "'; DROP TABLE ticket; --"].randomElement(using: &rng)!)
            case 10: t = t.replacingOccurrences(of: "\"area\":\"Notifications\"", with: "\"area\":\(["\"NOTIF\"", "\"notifications\"", "\" Notifications \"", "[\"Notifications\"]", "7", "\"Settings\"", "\"None\""].randomElement(using: &rng)!)")
            case 11: t = t.replacingOccurrences(of: ",", with: ",,", options: [], range: t.startIndex..<t.index(t.startIndex, offsetBy: min(t.count, Int.random(in: 0..<t.count, using: &rng))))
            case 12: t = String(t.dropFirst(Int.random(in: 0..<min(30, t.count), using: &rng)))
            default: t = t.replacingOccurrences(of: "\"duplicateOf\":\"\"", with: "\"duplicateOf\":\(["\"#99999\"", "\"#1\"", "12", "null", "\"self\""].randomElement(using: &rng)!),\"duplicateSure\":true,\"duplicateWhy\":\"same\"")
            }
        }
        return t
    }

    // MARK: Well-formed but extreme

    /// Random results that are structurally fine: any number of questions and parts, odd areas, unknown references.
    func testRandomWellFormedResultsKeepTheRules() throws {
        let (store, p) = try world()
        var rng = IrisEval.Random(seed: seed &+ 1)
        let paths: [WorkPath?] = WorkPath.allCases.map { $0 } + [nil]
        for i in 0..<count {
            let t = try newTicket(store, p, i)
            var r = VettingResult()
            r.path = paths.randomElement(using: &rng)!
            r.area = [nil, "Notifications", "NOTIF", "Settings", "Nope", "", "notifications"].randomElement(using: &rng)!
            r.priority = [nil, "low", "normal", "high", "urgent", "p0"].randomElement(using: &rng)!
            r.questions = (0..<Int.random(in: 0...5, using: &rng)).map { n in
                .init(text: "Q\(n)", suggestions: (0..<Int.random(in: 0...5, using: &rng)).map { "S\($0)" },
                      about: [nil, nil, "decision #\(n)", "component Foo"].randomElement(using: &rng)!,
                      stakes: [nil, "low", "high"].randomElement(using: &rng)!, rerun: Bool.random(using: &rng))
            }
            r.split = (0..<Int.random(in: 0...15, using: &rng)).map { n in FilingChild(title: "part-\(n)", body: "", path: paths.randomElement(using: &rng)!) }
            r.related = (0..<Int.random(in: 0...4, using: &rng)).map { _ in "#\(Int.random(in: 1...3000, using: &rng))" }
            r.duplicateOf = [nil, "#\(1000 + Int.random(in: 0..<max(i, 1), using: &rng))", "#99999"].randomElement(using: &rng)!
            r.duplicateSure = Bool.random(using: &rng); r.duplicateWhy = [nil, "", "same screen"].randomElement(using: &rng)!
            r.blocks = ["#\(1000 + Int.random(in: 0..<max(i, 1), using: &rng))"]
            r.parent = "#\(1000 + Int.random(in: 0..<max(i, 1), using: &rng))"
            r.confidence = ["path": Double.random(in: 0...1, using: &rng)]
            r.specTouches = ["NOTIF-\(Int.random(in: 1...9, using: &rng))"]
            do {
                let out = try IrisApplier.apply(r, to: t.id, store: store)
                try assertRulesHold(store, t, p, context: "result \(i)")
                if r.effectivePath == .split && r.split.count >= 2 && r.split.allSatisfy({ $0.path != .split }) && out.status == .dropped {
                    XCTAssertEqual(out.split.count, r.split.count, "every part the owner asked for becomes a ticket (result \(i))")
                }
            } catch let e as StoreError {
                // A refusal is allowed, but must leave the ticket as it was.
                XCTAssertEqual(try store.ticket(id: t.id)?.status, .checking, "result \(i): refused (\(e)) but the ticket changed")
            }
        }
    }

    func testTheBriefStillBuildsForEveryTicketTheFuzzMade() throws {
        let (store, p) = try world()
        var rng = IrisEval.Random(seed: seed &+ 2)
        for i in 0..<200 {
            let t = try newTicket(store, p, i)
            let text = Self.mutate(Self.valid, &rng)
            _ = try VettingService(store: store, runner: ScriptedRunner(text: text)).vet(ticketId: t.id)
            let brief = try BriefBuilder.brief(store: store, ticketId: t.id, agent: "A")
            XCTAssertTrue(brief.contains(t.displayNumber), "case \(i)")
            XCTAssertLessThan(brief.count, 20_000, "a brief stays compact even after a hostile answer (case \(i))")
        }
    }
}
