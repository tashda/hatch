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

    func testRefusesWhatWouldBreakTheSystem() throws {
        let client = StageClient(paths: paths)
        XCTAssertThrowsError(try client.changeComponents(project: "echo", action: "look", body: ["role": "button.toolbar", "recipe": ["style": "huge"]]))
        XCTAssertThrowsError(try client.changeComponents(project: "echo", action: "answer", body: ["question": "nope", "option": 0]))
        XCTAssertEqual(try ComponentSystem.load(notebook: notebook.path)?.role("button.toolbar")?.recipe["style"], "automatic", "nothing written")
    }
}
