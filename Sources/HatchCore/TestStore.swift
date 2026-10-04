import Foundation

/// Xcode tests in the store (section Y): the catalog read from the sources, the runs agents and people make, and each
/// test's result per run. Writes come from `hatch check` and `hatch tests`; the app only reads.
public extension HatchStore {
    // MARK: Runs

    @discardableResult
    func startTestRun(projectId: Int, repoId: Int? = nil, ticketId: Int? = nil, agent: String? = nil, command: String? = nil,
                      scope: String? = nil, branch: String? = nil, commit: String? = nil, pid: Int? = nil) throws -> Int {
        try db.transaction {
            try db.execute("""
                INSERT INTO test_run(project_id, repo_id, ticket_id, agent, command, scope, branch, commit_sha, pid, started_at)
                VALUES(?,?,?,?,?,?,?,?,?,?)
                """, [.int(projectId), .opt(repoId), .opt(ticketId), .opt(agent), .opt(command), .opt(scope), .opt(branch), .opt(commit),
                      .opt(pid), .date(now())])
            return try db.scalarInt("SELECT last_insert_rowid()")
        }
    }

    /// A result arrives while the run is going. The run's counts follow.
    func recordTestResult(_ r: TestResult) throws {
        try db.transaction {
            try insertResult(r)
            try refreshTestCounts(runId: r.runId)
            try db.execute("UPDATE test_run SET running_name = NULL WHERE id = ?", [.int(r.runId)])
        }
    }

    func setRunningTest(runId: Int, name: String?) throws {
        try db.execute("UPDATE test_run SET running_name = ? WHERE id = ?", [.opt(name), .int(runId)])
    }

    /// The result bundle is the authority: it replaces what was read from the output while the run went.
    func replaceTestResults(runId: Int, with results: [TestResult]) throws {
        try db.transaction {
            try db.execute("DELETE FROM test_result WHERE run_id = ?", [.int(runId)])
            for var r in results { r.runId = runId; try insertResult(r) }
            try refreshTestCounts(runId: runId)
        }
    }

    /// Ends a run. `state` is derived from the counts when nil: failed when any test failed or the run broke.
    func finishTestRun(runId: Int, state: TestRunState? = nil, resultPath: String? = nil, source: String? = nil, error: String? = nil) throws {
        try db.transaction {
            try refreshTestCounts(runId: runId)
            let failed = try db.scalarInt("SELECT failed FROM test_run WHERE id = ?", [.int(runId)])
            let final = state ?? ((failed > 0 || error != nil) ? .failed : .passed)
            try db.execute("""
                UPDATE test_run SET state = ?, ended_at = ?, running_name = NULL, result_path = COALESCE(?, result_path),
                    source = COALESCE(?, source), error = COALESCE(?, error) WHERE id = ?
                """, [.text(final.rawValue), .date(now()), .opt(resultPath), .opt(source), .opt(error), .int(runId)])
            try addResultsToCatalog(runId: runId)
        }
    }

    /// Runs that say "running" although their process is gone (a crash, a closed terminal) become "interrupted".
    func closeAbandonedTestRuns(isAlive: (Int) -> Bool) throws {
        let open: [(Int, Int?)] = try db.query("SELECT id, pid FROM test_run WHERE state = 'running'") { ($0.int("id")!, $0.int("pid")) }
        for (id, pid) in open {
            // Without a pid there is nothing to ask; a run older than a day is certainly over.
            let dead = pid.map { !isAlive($0) } ?? false
            let stale = try db.scalarInt("SELECT COUNT(*) FROM test_run WHERE id = ? AND started_at < ?", [.int(id), .date(now().addingTimeInterval(-86_400))]) > 0
            if dead || stale { try finishTestRun(runId: id, state: .interrupted, error: "The process ended before the run finished.") }
        }
    }

    func testRun(id: Int) throws -> TestRun? {
        try db.query("SELECT * FROM test_run WHERE id = ?", [.int(id)], map: Self.testRun).first
    }

    /// Newest first.
    func testRuns(projectId: Int? = nil, ticketId: Int? = nil, limit: Int = 50) throws -> [TestRun] {
        var sql = "SELECT * FROM test_run WHERE 1=1", params: [SQLValue] = []
        if let projectId { sql += " AND project_id = ?"; params.append(.int(projectId)) }
        if let ticketId { sql += " AND ticket_id = ?"; params.append(.int(ticketId)) }
        sql += " ORDER BY started_at DESC, id DESC LIMIT ?"; params.append(.int(limit))
        return try db.query(sql, params, map: Self.testRun)
    }

    /// How many tests the run is expected to have, guessed from the last finished run with the same scope in the
    /// project. Nil when there is none (the bar then has no end to fill toward).
    func expectedTestTotal(for run: TestRun) throws -> Int? {
        let n = try db.query("""
            SELECT total FROM test_run WHERE project_id = ? AND id != ? AND state IN ('passed','failed') AND total > 0
                AND COALESCE(scope,'') = COALESCE(?,'') AND source = 'xcresult' ORDER BY started_at DESC LIMIT 1
            """, [.int(run.projectId), .int(run.id), .opt(run.scope)]) { $0.int("total") }
        return n.first.flatMap { $0 }
    }

    func testResults(runId: Int, problemsOnly: Bool = false) throws -> [TestResult] {
        let sql = "SELECT * FROM test_result WHERE run_id = ?" + (problemsOnly ? " AND status = 'failed'" : "") + " ORDER BY bundle, suite, name"
        return try db.query(sql, [.int(runId)], map: Self.testResult)
    }

    /// What one test did in each run, newest first.
    func testHistory(projectId: Int, bundle: String, suite: String, name: String, limit: Int = 20) throws -> [(result: TestResult, run: TestRun)] {
        try db.query("""
            SELECT r.*, u.id AS run_id2 FROM test_result r JOIN test_run u ON u.id = r.run_id
            WHERE u.project_id = ? AND r.bundle = ? AND r.suite = ? AND r.name = ? ORDER BY u.started_at DESC LIMIT ?
            """, [.int(projectId), .text(bundle), .text(suite), .text(TestName.normalized(name)), .int(limit)]) { row in
            (Self.testResult(row), try self.testRun(id: row.int("run_id")!)!)
        }
    }

    // MARK: Catalog

    /// Replaces the catalog of a project with what the scan found. Tests that are no longer in the sources go.
    func syncTestCatalog(projectId: Int, repoId: Int?, cases: [TestCaseInfo]) throws {
        let at = now()
        try db.transaction {
            for c in cases {
                try db.execute("""
                    INSERT INTO test_case(project_id, repo_id, bundle, suite, name, kind, file, line, seen_at) VALUES(?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(project_id, bundle, suite, name) DO UPDATE SET repo_id = excluded.repo_id, kind = excluded.kind,
                        file = excluded.file, line = excluded.line, seen_at = excluded.seen_at
                    """, [.int(projectId), .opt(repoId), .text(c.bundle), .text(c.suite), .text(c.name), .text(c.kind), .opt(c.file), .opt(c.line), .date(at)])
            }
            try db.execute("DELETE FROM test_case WHERE project_id = ? AND seen_at < ?", [.int(projectId), .date(at)])
        }
    }

    /// The catalog with each test's latest result, for the tree.
    func testOverview(projectId: Int) throws -> [TestOverviewRow] {
        try db.query("""
            SELECT c.bundle, c.suite, c.name, c.kind, c.file, c.line, r.status, r.run_id, r.message, u.started_at, u.agent, u.ticket_id
            FROM test_case c
            LEFT JOIN test_result r ON r.rowid = (
                SELECT r2.rowid FROM test_result r2 JOIN test_run u2 ON u2.id = r2.run_id
                WHERE r2.bundle = c.bundle AND r2.suite = c.suite AND r2.name = c.name AND u2.project_id = c.project_id
                    AND r2.status != 'running' ORDER BY u2.started_at DESC, u2.id DESC LIMIT 1)
            LEFT JOIN test_run u ON u.id = r.run_id
            WHERE c.project_id = ? ORDER BY c.bundle, c.suite, c.name
            """, [.int(projectId)]) { r in
            TestOverviewRow(info: TestCaseInfo(bundle: r.string("bundle")!, suite: r.string("suite")!, name: r.string("name")!,
                                               kind: r.string("kind") ?? "xctest", file: r.string("file"), line: r.int("line")),
                            lastStatus: r.string("status").flatMap(TestStatus.init(rawValue:)), lastRunId: r.int("run_id"),
                            lastAt: r.date("started_at"), lastAgent: r.string("agent"), lastTicketId: r.int("ticket_id"),
                            lastMessage: r.string("message"))
        }
    }

    // MARK: Private

    private func insertResult(_ r: TestResult) throws {
        try db.execute("""
            INSERT OR REPLACE INTO test_result(run_id, bundle, suite, name, status, duration, message, file, line) VALUES(?,?,?,?,?,?,?,?,?)
            """, [.int(r.runId), .text(r.bundle), .text(r.suite), .text(r.name), .text(r.status.rawValue), .opt(r.duration),
                  .opt(r.message), .opt(r.file), .opt(r.line)])
    }

    private func refreshTestCounts(runId: Int) throws {
        try db.execute("""
            UPDATE test_run SET
                passed = (SELECT COUNT(*) FROM test_result WHERE run_id = ?1 AND status = 'passed'),
                failed = (SELECT COUNT(*) FROM test_result WHERE run_id = ?1 AND status = 'failed'),
                skipped = (SELECT COUNT(*) FROM test_result WHERE run_id = ?1 AND status = 'skipped'),
                total = (SELECT COUNT(*) FROM test_result WHERE run_id = ?1 AND status != 'running')
            WHERE id = ?1
            """, [.int(runId)])
    }

    /// A test that ran but the scan did not find (an Objective-C test, a generated one) still belongs in the catalog.
    private func addResultsToCatalog(runId: Int) throws {
        guard let run = try testRun(id: runId) else { return }
        try db.execute("""
            INSERT OR IGNORE INTO test_case(project_id, repo_id, bundle, suite, name, kind, file, line, seen_at)
            SELECT ?, ?, bundle, suite, name, 'xctest', file, line, ? FROM test_result WHERE run_id = ?
            """, [.int(run.projectId), .opt(run.repoId), .date(now()), .int(runId)])
    }

    private static func testRun(_ r: Row) -> TestRun {
        TestRun(id: r.int("id")!, projectId: r.int("project_id")!, repoId: r.int("repo_id"), ticketId: r.int("ticket_id"),
                agent: r.string("agent"), command: r.string("command"), scope: r.string("scope"), branch: r.string("branch"),
                commit: r.string("commit_sha"), pid: r.int("pid"), state: r.string("state").flatMap(TestRunState.init(rawValue:)) ?? .failed,
                total: r.int("total") ?? 0, passed: r.int("passed") ?? 0, failed: r.int("failed") ?? 0, skipped: r.int("skipped") ?? 0,
                runningName: r.string("running_name"), startedAt: r.date("started_at") ?? Date(), endedAt: r.date("ended_at"),
                resultPath: r.string("result_path"), source: r.string("source") ?? "log", error: r.string("error"))
    }

    private static func testResult(_ r: Row) -> TestResult {
        TestResult(runId: r.int("run_id")!, bundle: r.string("bundle")!, suite: r.string("suite")!, name: r.string("name")!,
                   status: r.string("status").flatMap(TestStatus.init(rawValue:)) ?? .failed, duration: r.double("duration"),
                   message: r.string("message"), file: r.string("file"), line: r.int("line"))
    }
}
