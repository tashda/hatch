import XCTest
import HatchCore
@testable import HatchGit

final class NotebookTests: GitTestCase {
    func testScaffoldNamesEveryPartAndTheWorkflowFollowsTheSettings() {
        var config = ProjectConfig(name: "Echo", ticketsRepo: "acme/hatch-tickets",
                                   repos: [RepoConfig(role: .app, remote: "acme/echo", branch: "dev", buildCommand: "swift build")],
                                   integrationBranch: "hatch", planApprovalFileThreshold: 8)
        config.promotion = .pullRequest
        let files = Notebook.scaffold(config: config, notebookRepo: "acme/echo-notebook", rules: nil)
        XCTAssertEqual(Set(files.keys), ["README.md", "AGENTS.md", "WORKFLOW.md", "NOW.md", "rules/AGENTS.md", "rules/areas/README.md",
                                         "spec/README.md", "decisions/README.md", "specimens/README.md"])
        XCTAssertTrue(files["README.md"]!.contains("`acme/echo`"))
        XCTAssertTrue(files["WORKFLOW.md"]!.contains("opens a pull request into `dev`"))
        XCTAssertTrue(files["WORKFLOW.md"]!.contains("`swift build`"))
        XCTAssertTrue(files["WORKFLOW.md"]!.contains("Proposal: "))
        XCTAssertEqual(Notebook.scaffold(config: config, notebookRepo: "x", rules: "# Ours\n")["rules/AGENTS.md"], "# Ours\n")
        XCTAssertEqual(Notebook.suggestedName(appRepo: "tashda/Echo"), "echo-notebook")
    }

    func testPlacedRulesAreNeverCommittedAndOwnFilesAreKept() throws {
        let dir = try makeRepo("app")
        XCTAssertEqual(try RulesPlacer.place(rules: "# Rules\n", into: dir, git: git), .placed)
        let agents = try String(contentsOfFile: dir + "/AGENTS.md", encoding: .utf8)
        XCTAssertTrue(agents.hasPrefix(Notebook.placedMarker))
        XCTAssertTrue(agents.contains("# Rules"))
        XCTAssertTrue(try String(contentsOfFile: dir + "/CLAUDE.md", encoding: .utf8).contains("@AGENTS.md"))
        XCTAssertEqual(try g(["status", "--porcelain"], dir), "", "placed files must be excluded")
        // Placing again replaces Hatch's own copy and does not repeat the exclude lines.
        XCTAssertEqual(try RulesPlacer.place(rules: "# New\n", into: dir, git: git), .placed)
        let exclude = try String(contentsOfFile: dir + "/.git/info/exclude", encoding: .utf8)
        XCTAssertEqual(exclude.components(separatedBy: "/AGENTS.md").count, 2)

        let other = try makeRepo("other")
        try write(other, "CLAUDE.md", "# Mine\n")
        XCTAssertEqual(RulesPlacer.existingRules(in: other, git: git), "# Mine\n")
        XCTAssertEqual(try RulesPlacer.place(rules: "# Rules\n", into: other, git: git), .keptLocalFile("CLAUDE.md"))

        let committed = try makeRepo("committed")
        try write(committed, "AGENTS.md", "# Team rules\n")
        try g(["add", "AGENTS.md"], committed); try g(["commit", "-qm", "rules"], committed)
        XCTAssertEqual(try RulesPlacer.place(rules: "# Rules\n", into: committed, git: git), .appHasOwn)
        XCTAssertNil(RulesPlacer.existingRules(in: committed, git: git))
    }

    func testWorktreesGetTheNotebookRules() throws {
        let notebookDir = try makeRepo("echo-notebook")
        try NotebookWriter.writeMissing(["rules/AGENTS.md": "# Echo rules\n"], in: notebookDir)
        var config = project.config!
        config.repos.append(RepoConfig(role: .notebook, remote: "acme/echo-notebook", branch: "dev", localPath: notebookDir))
        project = try store.upsertProject(key: "echo", name: "Echo", config: config)
        let ws = try manager.create(ticket: try makeTicket("Toast spacing", gh: 151), repo: app)
        XCTAssertTrue(try String(contentsOfFile: ws.path + "/AGENTS.md", encoding: .utf8).contains("# Echo rules"))
        XCTAssertFalse(try g(["status", "--porcelain"], ws.path).contains("AGENTS.md"))
    }

    func testWriteMissingNeverOverwrites() throws {
        let dir = try makeRepo("nb")
        try write(dir, "NOW.md", "kept\n")
        let written = try NotebookWriter.writeMissing(["NOW.md": "new\n", "WORKFLOW.md": "flow\n"], in: dir)
        XCTAssertEqual(written, ["WORKFLOW.md"])
        XCTAssertEqual(try String(contentsOfFile: dir + "/NOW.md", encoding: .utf8), "kept\n")
        XCTAssertTrue(try NotebookWriter.commit("Start the notebook", in: dir, git: git))
        XCTAssertFalse(try NotebookWriter.commit("Nothing new", in: dir, git: git))
    }
}
