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

final class NotebookExportTests: GitTestCase {
    /// A notebook clone with a bare remote, so the export's push is real.
    func makeNotebook() throws -> String {
        let remote = tmp + "/remote-notebook.git"
        try g(["init", "-q", "--bare", "-b", "dev", remote], tmp)
        let dir = try makeRepo("echo-notebook")
        try g(["remote", "add", "origin", remote], dir)
        try g(["push", "-q", "-u", "origin", "dev"], dir)
        var config = project.config!
        config.repos.append(RepoConfig(role: .notebook, remote: "acme/echo-notebook", branch: "dev", localPath: dir))
        project = try store.upsertProject(key: "echo", name: "Echo", config: config)
        return dir
    }

    func testExportWritesDecisionsAndNowAndPushes() throws {
        let dir = try makeNotebook()
        let t = try store.createTicket(projectId: project.id, type: .proposal, title: "Toast spacing", ghNumber: 151)
        try store.recordDecision(ticketId: t.id, kind: .design, title: "Toast spacing", summary: "Chose B.", reason: "Less cramped.")
        _ = try store.createTicket(projectId: project.id, type: .bug, title: "Crash on timeout", ghNumber: 152)

        let r = try XCTUnwrap(NotebookExport.run(store: store, projectId: project.id, token: nil, git: git))
        XCTAssertEqual(r.decisionsWritten, 1)
        XCTAssertTrue(r.nowUpdated)
        XCTAssertTrue(r.pushed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/decisions/0151-toast-spacing.md"))
        XCTAssertTrue(try String(contentsOfFile: dir + "/NOW.md", encoding: .utf8).contains("#152 Bug: Crash on timeout"))
        XCTAssertTrue(try String(contentsOfFile: dir + "/decisions/README.md", encoding: .utf8).contains("[#151 Toast spacing](0151-toast-spacing.md)"))
        XCTAssertEqual(try g(["rev-list", "--count", "@{u}..HEAD"], dir), "0")

        // Nothing changed: no new commit.
        let again = try XCTUnwrap(NotebookExport.run(store: store, projectId: project.id, token: nil, git: git))
        XCTAssertEqual(again.decisionsWritten, 0)
        XCTAssertFalse(again.nowUpdated)
        XCTAssertFalse(again.committed)
    }

    func testDecisionFilesComeBackIntoANewDatabase() throws {
        let dir = try makeNotebook()
        let t = try store.createTicket(projectId: project.id, type: .question, title: "Retries", ghNumber: 160)
        try store.recordDecision(ticketId: t.id, kind: .architecture, title: "Retries", summary: "Back off.", reason: "Servers recover.")
        try NotebookExport.run(store: store, projectId: project.id, token: nil, push: false, git: git)

        // A fresh database that knows the ticket (synced from GitHub) but not the decision: picking up on a new Mac.
        let fresh = try HatchStore.inMemory()
        let p = try fresh.upsertProject(key: "echo", name: "Echo", config: project.config)
        _ = try fresh.createTicket(projectId: p.id, type: .question, title: "Retries", ghNumber: 160)
        let r = try XCTUnwrap(NotebookExport.run(store: fresh, projectId: p.id, token: nil, push: false, git: git))
        XCTAssertEqual(r.imported, 1)
        XCTAssertEqual(r.decisionsWritten, 0, "an imported decision already has its file")
        let found = try fresh.searchDecisions(projectId: p.id, query: "servers recover")
        XCTAssertEqual(found.first?.kind, .architecture)
        XCTAssertEqual(found.first?.reason, "Servers recover.")
        _ = dir
    }
}
