import XCTest
import HatchCore
@testable import HatchGit

final class StorageCleanupTests: GitTestCase {
    func testCleanupRemovesCleanWorkspacesOfFinishedTicketsAndKeepsDirtyOnes() throws {
        let clean = try makeTicket("Clean", gh: 21)
        let dirty = try makeTicket("Dirty", gh: 22)
        let open = try makeTicket("Open", gh: 23)
        let cleanWs = try manager.create(ticket: clean, repo: app)
        let dirtyWs = try manager.create(ticket: dirty, repo: app)
        let openWs = try manager.create(ticket: open, repo: app)
        try write(dirtyWs.path, "notes.txt", "not committed")
        try store.move(clean.id, to: .dropped, actor: .owner)
        try store.move(dirty.id, to: .dropped, actor: .owner)
        let later = Date().addingTimeInterval(10 * 86_400)
        store.now = { later }

        let logs = URL(fileURLWithPath: tmp).appendingPathComponent("runs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let oldLog = logs.appendingPathComponent("21-1.jsonl"), newLog = logs.appendingPathComponent("23-2.jsonl")
        FileManager.default.createFile(atPath: oldLog.path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: newLog.path, contents: Data("{}".utf8))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-40 * 86_400)], ofItemAtPath: oldLog.path)
        // The log cutoff is counted from the store's clock, which is ten days ahead here.
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: newLog.path)

        let plan = StorageCleanup.plan(store: store, rules: CleanupRules(workspaceDays: 7, logDays: 30), logsFolder: logs)
        XCTAssertEqual(Set(plan.workspaces.map(\.ticketId)), [clean.id, dirty.id])
        XCTAssertEqual(plan.logs.map(\.lastPathComponent), ["21-1.jsonl"])
        XCTAssertGreaterThan(plan.workspaceBytes, 0)

        let result = StorageCleanup.run(plan, store: store, git: git)
        XCTAssertEqual(result.removedWorkspaces, 1)
        XCTAssertEqual(result.removedLogs, 1)
        XCTAssertEqual(result.keptDirty.map(\.ticketId), [dirty.id])
        XCTAssertTrue(result.problems.isEmpty, "\(result.problems)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanWs.path))
        XCTAssertTrue(git.branchExists(cleanWs.branch, in: app.localPath!), "the ticket branch is kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyWs.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: openWs.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldLog.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newLog.path))
        XCTAssertEqual(Set(try store.workspaces().map(\.ticketId)), [dirty.id, open.id])
    }

    func testNeverMeansNothingIsPlanned() throws {
        let t = try makeTicket("Done long ago", gh: 31)
        _ = try manager.create(ticket: t, repo: app)
        try store.move(t.id, to: .dropped, actor: .owner)
        let later = Date().addingTimeInterval(400 * 86_400)
        store.now = { later }
        let plan = StorageCleanup.plan(store: store, rules: CleanupRules(workspaceDays: nil, logDays: nil),
                                       logsFolder: URL(fileURLWithPath: tmp).appendingPathComponent("runs"))
        XCTAssertTrue(plan.isEmpty)
    }
}
