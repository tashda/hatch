import XCTest
@testable import HatchAPI
import HatchCore

/// The Components Designer reads and changes the design system only through Hatch (decisions DS1, DS2).
final class ComponentsAPITests: APITestCase {
    var notebook: URL!
    var commits: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        notebook = home.appendingPathComponent("notebook", isDirectory: true)
        try FileManager.default.createDirectory(at: notebook, withIntermediateDirectories: true)
        var config = ProjectConfig(name: "Echo", ticketsRepo: "o/t")
        config.repos.append(RepoConfig(role: .notebook, remote: "o/echo-notebook", branch: "main", localPath: notebook.path))
        _ = try store.upsertProject(key: "echo", name: "Echo", config: config)
        var system = ComponentTemplates.glass.system(name: "Echo")
        system.questions = [ComponentQuestion(id: "look.button.inRow", kind: .look, role: "button.inRow", title: "Rows",
                                              options: [.init(title: "plain", recipe: ["style": "plain"], count: 3, effect: "x"),
                                                        .init(title: "Not sure yet", effect: "y")], reason: "most used")]
        try system.write(notebook: notebook.path)
        server.commitNotebook = { [unowned self] _, message in self.commits.append(message) }
    }

    func testReadAnswerChangeAndApply() throws {
        let client = StageClient(paths: paths)
        var system = try client.components(project: "echo")
        XCTAssertEqual(system.questions.count, 1)

        system = try client.changeComponents(project: "echo", action: "answer", body: ["question": "look.button.inRow", "option": 0, "decision": "#4"])
        XCTAssertEqual(system.role("button.inRow")?.recipe, ["style": "plain"])
        XCTAssertEqual(system.role("button.inRow")?.status, .agreed)
        XCTAssertTrue(system.questions.isEmpty)
        XCTAssertEqual(try ComponentSystem.load(notebook: notebook.path)?.role("button.inRow")?.decision, "#4", "written to the notebook")
        XCTAssertTrue(FileManager.default.fileExists(atPath: notebook.appendingPathComponent(ComponentSystem.readmePath).path))

        // An agreed role gets a draft, not a silent change.
        system = try client.changeComponents(project: "echo", action: "look", body: ["role": "button.inRow", "recipe": ["style": "bordered", "size": "small"]])
        XCTAssertEqual(system.role("button.inRow")?.recipe, ["style": "plain"])
        XCTAssertEqual(system.role("button.inRow")?.draft, ["style": "bordered", "size": "small"])
        XCTAssertEqual(system.role("button.inRow")?.status, .inRedesign)

        system = try client.changeComponents(project: "echo", action: "apply", body: [:])
        XCTAssertEqual(system.version, 2, "applying a redesign starts the next baseline")
        XCTAssertEqual(system.role("button.inRow")?.recipe["style"], "bordered")
        XCTAssertEqual(commits.count, 3)
        XCTAssertTrue(commits[2].contains("baseline v2"))
    }

    func testLikeThisAndMakeItASetting() throws {
        let client = StageClient(paths: paths)
        let system = try client.changeComponents(project: "echo", action: "answer", body: ["question": "look.button.inRow", "option": 0, "setting": true])
        XCTAssertTrue(system.role("button.inRow")!.configurable)
        var filter = TicketFilter(); filter.projectId = projectId
        let drafts = try store.tickets(filter).filter { $0.title.contains("a setting") }
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.status, .draft)
        XCTAssertTrue(drafts.first!.body.contains("button.inRow"))
        _ = try client.changeComponents(project: "echo", action: "setting", body: ["id": "menuIcons"])
        XCTAssertTrue(try ComponentSystem.load(notebook: notebook.path)!.rules.first { $0.kind == "menuIcons" }!.configurable)
        XCTAssertTrue(commits.last!.contains("(draft "), commits.last!)
    }

    /// Open questions are prepared Questions in Decide; answering one anywhere keeps both in step (DC9).
    func testQuestionsAreInDecide() throws {
        var system = try ComponentSystem.load(notebook: notebook.path)!
        system.questions.append(ComponentQuestion(id: "look.button.secondary", kind: .look, role: "button.secondary", title: "Other action",
                                                  options: [.init(title: "glass", recipe: ["style": "glass"], count: 4, effect: "x"),
                                                            .init(title: "Follow macOS", follow: true, effect: "y")], reason: "most used"))
        try system.write(notebook: notebook.path)
        XCTAssertEqual(try store.syncComponentQuestions(projectId: projectId, system: system).added, 2)
        XCTAssertEqual(try store.syncComponentQuestions(projectId: projectId, system: system).added, 0, "once per question")
        let pending = try store.pendingDecisions(projectId: projectId).filter { $0.ticket.area == ComponentsSetup.area }
        XCTAssertEqual(pending.map(\.kind), [.pick, .pick])
        let options = try store.questionOptions(ticketId: pending[0].ticket.id)
        XCTAssertTrue(options.allSatisfy { $0.gain != nil && $0.cost != nil })

        // Answered in the Designer: its ticket leaves Decide.
        _ = try StageClient(paths: paths).changeComponents(project: "echo", action: "answer", body: ["question": "look.button.inRow", "option": 0])
        let left = try store.pendingDecisions(projectId: projectId).filter { $0.ticket.area == ComponentsSetup.area }
        XCTAssertEqual(left.count, 1)

        // Answered in Decide: the system takes the answer.
        let ticket = left[0].ticket
        _ = try store.decidePreparedQuestion(ticketId: ticket.id, choice: "1", reason: nil)
        system = try ComponentSystem.load(notebook: notebook.path)!
        XCTAssertTrue(try system.applyDecided(ticketBody: ticket.body, choice: "1", decision: ticket.displayNumber))
        XCTAssertTrue(system.role("button.secondary")!.followsMacOS)
        XCTAssertFalse(try system.applyDecided(ticketBody: ticket.body, choice: "1", decision: nil), "already answered")
    }

    func testRefusesWhatWouldBreakTheSystem() throws {
        let client = StageClient(paths: paths)
        XCTAssertThrowsError(try client.changeComponents(project: "echo", action: "look", body: ["role": "button.toolbar", "recipe": ["style": "huge"]]))
        XCTAssertThrowsError(try client.changeComponents(project: "echo", action: "answer", body: ["question": "nope", "option": 0]))
        let toolbar = try ComponentSystem.load(notebook: notebook.path)?.role("button.toolbar")
        XCTAssertNil(toolbar?.draft, "nothing written")
        XCTAssertTrue(toolbar?.followsMacOS == true)
    }
}
