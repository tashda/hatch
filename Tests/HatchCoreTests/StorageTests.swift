import XCTest
@testable import HatchCore

final class StorageTests: XCTestCase {
    var dir: URL!
    var calendar: Calendar!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hatch-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// Noon UTC on a day in October 2026, so no time zone moves it to another date.
    func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))! }

    func fileStore(at date: Date) throws -> HatchStore {
        try HatchStore(path: dir.appendingPathComponent("hatch.sqlite").path, now: { date })
    }

    func setClock(_ store: HatchStore, _ date: Date) { store.now = { date } }

    // MARK: Backup

    func testBackUpWritesADatedCopyThatOpens() throws {
        let store = try fileStore(at: day(4))
        let project = try store.upsertProject(key: "echo", name: "Echo")
        _ = try store.createTicket(projectId: project.id, type: .bug, title: "Crash on launch")
        let backups = dir.appendingPathComponent("backups", isDirectory: true)

        let url = try store.backUp(into: backups, calendar: calendar)
        XCTAssertEqual(url.lastPathComponent, "hatch-2026-10-04.sqlite")
        let copy = try HatchStore(path: url.path)
        XCTAssertEqual(try copy.ticketCount(), 1)
        XCTAssertEqual(try copy.tickets().first?.title, "Crash on launch")
    }

    func testBackUpTheSameDayReplacesTheCopy() throws {
        let store = try fileStore(at: day(4))
        let project = try store.upsertProject(key: "echo", name: "Echo")
        let backups = dir.appendingPathComponent("backups", isDirectory: true)
        try store.backUp(into: backups, calendar: calendar)
        _ = try store.createTicket(projectId: project.id, type: .bug, title: "Second")
        let url = try store.backUp(into: backups, calendar: calendar)
        XCTAssertEqual(try HatchStore(path: url.path).ticketCount(), 1)
        XCTAssertEqual(DatabaseBackups.list(in: backups, calendar: calendar).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + ".partial"))
    }

    func testInMemoryStoreCanBeBackedUp() throws {
        let d = day(4)
        let store = try HatchStore.inMemory(now: { d })
        let url = try store.backUp(into: dir, calendar: calendar)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testPruneKeepsTheNewestAndLeavesOtherFiles() throws {
        let fm = FileManager.default
        for d in 1...9 { fm.createFile(atPath: dir.appendingPathComponent(DatabaseBackups.fileName(for: day(d), calendar: calendar)).path, contents: Data()) }
        fm.createFile(atPath: dir.appendingPathComponent("notes.txt").path, contents: Data())
        fm.createFile(atPath: dir.appendingPathComponent("hatch-old.sqlite").path, contents: Data())

        let removed = try DatabaseBackups.prune(in: dir, keep: 7, calendar: calendar)
        XCTAssertEqual(removed.map(\.lastPathComponent).sorted(), ["hatch-2026-10-01.sqlite", "hatch-2026-10-02.sqlite"])
        let left = try fm.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(left.count, 9)
        XCTAssertTrue(left.contains("notes.txt"))
        XCTAssertTrue(left.contains("hatch-old.sqlite"))
        XCTAssertEqual(DatabaseBackups.latest(in: dir, calendar: calendar), calendar.startOfDay(for: day(9)))
    }

    func testPolicyIsDue() {
        XCTAssertTrue(BackupPolicy.daily.isDue(latest: nil, now: day(4), calendar: calendar))
        XCTAssertFalse(BackupPolicy.daily.isDue(latest: day(4), now: day(4).addingTimeInterval(3600), calendar: calendar))
        XCTAssertTrue(BackupPolicy.daily.isDue(latest: day(3), now: day(4), calendar: calendar))
        XCTAssertFalse(BackupPolicy.weekly.isDue(latest: day(1), now: day(7), calendar: calendar))
        XCTAssertTrue(BackupPolicy.weekly.isDue(latest: day(1), now: day(8), calendar: calendar))
        XCTAssertFalse(BackupPolicy.off.isDue(latest: nil, now: day(4), calendar: calendar))
        XCTAssertEqual(BackupPolicy(setting: nil), .daily)
        XCTAssertEqual(BackupPolicy(setting: "weekly").keep, 4)
    }

    func testBackUpIfDueMakesOneCopyADayAndPrunes() throws {
        let store = try fileStore(at: day(1))
        let backups = dir.appendingPathComponent("backups", isDirectory: true)
        XCTAssertNotNil(try store.backUpIfDue(.daily, into: backups, calendar: calendar))
        XCTAssertNil(try store.backUpIfDue(.daily, into: backups, calendar: calendar))
        for d in 2...10 {
            setClock(store, day(d))
            try store.backUpIfDue(.daily, into: backups, calendar: calendar)
        }
        let names = DatabaseBackups.list(in: backups, calendar: calendar).map(\.url.lastPathComponent)
        XCTAssertEqual(names.count, 7)
        XCTAssertEqual(names.first, "hatch-2026-10-10.sqlite")
        XCTAssertEqual(names.last, "hatch-2026-10-04.sqlite")
        XCTAssertNil(try store.backUpIfDue(.off, into: backups, calendar: calendar))
    }

    // MARK: Clean-up selection

    func testCleanupRulesFromSettings() {
        XCTAssertEqual(CleanupRules(workspaces: nil, logs: nil), CleanupRules(workspaceDays: 7, logDays: 30))
        XCTAssertEqual(CleanupRules(workspaces: "0", logs: "90"), CleanupRules(workspaceDays: nil, logDays: 90))
        XCTAssertEqual(CleanupRules(workspaces: "junk", logs: "0"), CleanupRules(workspaceDays: 7, logDays: nil))
    }

    func testFinishedWorkspacesAreDoneOrDroppedAndOldEnough() throws {
        let store = try HatchStore.inMemory()
        setClock(store, day(1))
        let project = try store.upsertProject(key: "echo", name: "Echo", config: ProjectConfig(name: "Echo", ticketsRepo: "acme/t", repos: [
            RepoConfig(role: .app, remote: "acme/app", branch: "dev"),
        ]))
        let repo = try XCTUnwrap(store.repo(projectId: project.id, role: .app))
        func ticketWithWorkspace(_ title: String) throws -> Ticket {
            let t = try store.createTicket(projectId: project.id, type: .tweak, title: title)
            _ = try store.saveWorkspace(ticketId: t.id, repoId: repo.id, path: "/tmp/\(title)", branch: title, baseSha: nil)
            return t
        }
        let old = try ticketWithWorkspace("old-dropped")
        let open = try ticketWithWorkspace("still-open")
        let running = try ticketWithWorkspace("dropped-running")
        try store.move(old.id, to: .dropped, actor: .owner)
        try store.move(running.id, to: .dropped, actor: .owner)
        setClock(store, day(5))
        let recent = try ticketWithWorkspace("recent-dropped")
        try store.move(recent.id, to: .dropped, actor: .owner)
        let removed = try ticketWithWorkspace("already-removed")
        try store.move(removed.id, to: .dropped, actor: .owner)
        try store.setWorkspace(try XCTUnwrap(store.workspaces(ticketId: removed.id).first).id, state: "removed")

        setClock(store, day(9))
        let chosen = try store.finishedWorkspaces(olderThanDays: 7, excluding: [running.id])
        XCTAssertEqual(chosen.map(\.ticketId), [old.id])
        XCTAssertFalse(chosen.contains { $0.ticketId == open.id })
        XCTAssertEqual(Set(try store.finishedWorkspaces(olderThanDays: 1).map(\.ticketId)), [old.id, running.id, recent.id])
    }

    func testOldFilesAreChosenByModificationDate() throws {
        let fm = FileManager.default
        let now = Date()
        for (name, age) in [("a.jsonl", 40.0), ("b.jsonl", 31.0), ("c.jsonl", 2.0)] {
            let url = dir.appendingPathComponent(name)
            fm.createFile(atPath: url.path, contents: Data("x".utf8))
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age * 86_400)], ofItemAtPath: url.path)
        }
        try fm.createDirectory(at: dir.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-90 * 86_400)], ofItemAtPath: dir.appendingPathComponent("folder").path)

        XCTAssertEqual(StorageFiles.files(in: dir, olderThanDays: 30, now: now).map(\.lastPathComponent), ["a.jsonl", "b.jsonl"])
        XCTAssertEqual(StorageFiles.files(in: dir, olderThanDays: 1, now: now).count, 3)
        XCTAssertTrue(StorageFiles.files(in: dir.appendingPathComponent("missing"), olderThanDays: 1, now: now).isEmpty)
        XCTAssertGreaterThan(StorageFiles.size(of: dir), 0)
        XCTAssertEqual(StorageFiles.size(of: dir.appendingPathComponent("missing")), 0)
    }
}
