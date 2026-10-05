import XCTest
import HatchCore
@testable import HatchAgent

/// Every Claude turn re-sends the brief, so its size is a running cost. A quiet ticket stays small, and a busy one is capped.
final class BriefSizeTests: LoopCase {
    func testAQuietTicketsBriefIsSmallForEveryKindOfWork() throws {
        for type in TicketType.allCases {
            for kind in [AgentTaskKind.prepare, .build, .fix, .revise] {
                let t = try ticket(type, "Size \(type) \(kind)", status: .ready)
                let b = try BriefBuilder.brief(store: world.store, ticketId: t.id, agent: "A", kind: kind)
                XCTAssertLessThan(b.count, 5_500, "\(type) \(kind): about \(b.count / 4) tokens on every turn")
            }
        }
    }

    func testABusyTicketsBriefIsCappedWhateverPilesUp() throws {
        let store = world.store
        let t = try store.createTicket(projectId: project.id, type: .tweak, title: "Busy toast", body: String(repeating: "A long description. ", count: 400),
                                       area: "Notifications", ghNumber: world.number(), status: .ready)
        // Twenty answered questions, forty notes, a dozen related tickets and links, ten decisions on the same words.
        for i in 0..<20 {
            let q = try store.ask(t.id, text: "Question number \(i) about the toast, with a fairly long text to see whether it is cut " + String(repeating: "x", count: 300),
                                  suggestions: ["Yes", "No"], by: "Iris", actor: .agent)
            try store.answer(questionId: q.id, text: "Answer \(i) " + String(repeating: "y", count: 400))
        }
        for i in 0..<40 { _ = try store.addNote(t.id, kind: .note, author: "owner", body: "Note \(i): " + String(repeating: "z", count: 500)) }
        for i in 0..<12 {
            let other = try store.createTicket(projectId: project.id, type: .tweak, title: "Related toast ticket \(i)", body: "Toast padding words " + String(repeating: "w", count: 200),
                                               area: "Notifications", ghNumber: world.number(), status: .ready)
            try? store.link(from: t.id, to: other.id, kind: .related, by: "Iris", why: "same toast")
            let host = try store.createTicket(projectId: project.id, type: .question, title: "Toast decision \(i)", ghNumber: world.number(), status: .done)
            try store.recordDecision(ticketId: host.id, kind: .design, title: "Toast decision \(i) about padding", summary: "Toast padding " + String(repeating: "d", count: 400), reason: String(repeating: "r", count: 400))
        }
        try store.take(t.id, agent: "A")
        let b = try BriefBuilder.brief(store: store, ticketId: t.id, agent: "A", kind: .build)
        XCTAssertTrue(b.contains("12 earlier answers are on the ticket"), "the oldest answers are left out and the brief says so")
        XCTAssertLessThan(b.count, 14_000, "a busy ticket's brief is \(b.count) characters (about \(b.count / 4) tokens) on every turn")
        XCTAssertTrue(b.contains("## Rules for this task") && b.contains("## Next"), "the rules and the commands are never the part that gets cut")
    }
}
