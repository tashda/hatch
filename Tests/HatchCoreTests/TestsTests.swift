import XCTest
@testable import HatchCore

final class TestsTests: XCTestCase {
    var store: HatchStore!
    var project: Project!

    override func setUpWithError() throws {
        store = try HatchStore.inMemory()
        project = try store.upsertProject(key: "echo", name: "Echo")
    }

    // MARK: Scanner

    func testScannerFindsXCTestAndSwiftTestingTests() {
        let source = """
        import XCTest
        import Testing
        final class FpTests: XCTestCase {
            func testPasses() { XCTAssertEqual(1, 1) }
            func testThrows() throws { }
            func helper() {}
            func testWithArgument(_ x: Int) {}
            // func testCommentedOut() {}
            func testBraceInString() { let s = "}" ; _ = s }
            func testAfterTheString() {}
        }
        @Suite struct Modern {
            @Test func works() {}
            @Test("named") func breaks() {}
            @Test
            func onNextLine() {}
            func notATest() {}
        }
        extension FpTests { func testFromExtension() {} }
        """
        let found = TestScanner.scan(source: source, bundle: "FpTests", file: "Tests/FpTests/FpTests.swift")
        XCTAssertEqual(found.filter { $0.suite == "FpTests" }.map(\.name),
                       ["testPasses", "testThrows", "testBraceInString", "testAfterTheString", "testFromExtension"])
        XCTAssertEqual(found.filter { $0.suite == "Modern" }.map(\.name), ["works", "breaks", "onNextLine"])
        XCTAssertEqual(found.first { $0.name == "works" }?.kind, "swift-testing")
        XCTAssertEqual(found.first { $0.name == "testPasses" }?.line, 4)
    }

    func testScannerNamesTheBundleFromTheFolder() {
        XCTAssertEqual(TestScanner.bundleName(for: "Tests/HatchCoreTests/A.swift"), "HatchCoreTests")
        XCTAssertEqual(TestScanner.bundleName(for: "Stage/Tests/StageCoreTests/A.swift"), "StageCoreTests")
        XCTAssertEqual(TestScanner.bundleName(for: "EchoTests/Deep/A.swift"), "EchoTests")
        XCTAssertNil(TestScanner.bundleName(for: "Sources/HatchCore/A.swift"))
    }

    func testScannerReadsADirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("Tests/AppTests")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "final class A: XCTestCase { func testOne() {} }".write(to: dir.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "final class B: XCTestCase { func testNotHere() {} }".write(to: root.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let found = TestScanner.scan(root: root)
        XCTAssertEqual(found.map(\.id), ["AppTests/A/testOne"])
        XCTAssertEqual(found.first?.file, "Tests/AppTests/A.swift")
    }

    // MARK: xcresult

    /// Shaped like real `xcresulttool get test-results tests` output (Xcode 27), cut down.
    static let xcresult = """
    {"devices":[],"testPlanConfigurations":[],"testNodes":[{"name":"Fp-Package","nodeType":"Test Plan","result":"Failed","children":[
      {"name":"FpTests","nodeType":"Unit test bundle","result":"Failed","children":[
        {"name":"FpTests","nodeType":"Test Suite","result":"Failed","children":[
          {"name":"testFails()","nodeType":"Test Case","result":"Failed","durationInSeconds":0.61,"children":[
            {"name":"XCTAssertEqual failed: (\\"1\\") is not equal to (\\"2\\")","nodeType":"Failure Message","sourceLocation":{"filePath":"/x/FpTests.swift","lineNumber":6}}]},
          {"name":"testPasses()","nodeType":"Test Case","result":"Passed","durationInSeconds":0.001},
          {"name":"testSkips()","nodeType":"Test Case","result":"Skipped","durationInSeconds":0.001,"children":[
            {"name":"Test skipped - not today","nodeType":"Skip Message"}]}]},
        {"name":"SwiftTestingSuite","nodeType":"Test Suite","result":"Passed","children":[
          {"name":"works()","nodeType":"Test Case","result":"Passed","durationInSeconds":0.0002}]}]}]}]}
    """

    func testXCResultTreeBecomesResults() throws {
        let results = try XCResult.parse(Data(Self.xcresult.utf8))
        XCTAssertEqual(results.map(\.name), ["testFails", "testPasses", "testSkips", "works"])
        XCTAssertEqual(results.map(\.status), [.failed, .passed, .skipped, .passed])
        XCTAssertEqual(results[0].bundle, "FpTests")
        XCTAssertEqual(results[3].suite, "SwiftTestingSuite")
        XCTAssertEqual(results[0].line, 6)
        XCTAssertEqual(results[0].file, "/x/FpTests.swift")
        XCTAssertTrue(results[0].message?.contains("is not equal") == true)
        XCTAssertEqual(results[2].message, "Test skipped - not today")
        XCTAssertThrowsError(try XCResult.parse(Data("{}".utf8)))
    }

    // MARK: Log

    func testLogFollowerReportsStartsAndEnds() {
        var f = TestLogFollower()
        XCTAssertEqual(f.feed("Test Case '-[FpTests.FpTests testFails]' started."), .started(bundle: "FpTests", suite: "FpTests", name: "testFails"))
        XCTAssertNil(f.feed("/x/FpTests.swift:6: error: -[FpTests.FpTests testFails] : XCTAssertEqual failed: (\"1\") is not equal to (\"2\")"))
        guard case .finished(let failed)? = f.feed("Test Case '-[FpTests.FpTests testFails]' failed (0.615 seconds).") else { return XCTFail("no result") }
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.duration, 0.615)
        XCTAssertEqual(failed.line, 6)
        XCTAssertEqual(failed.file, "/x/FpTests.swift")
        XCTAssertTrue(failed.message?.hasPrefix("XCTAssertEqual failed") == true)
        guard case .finished(let ok)? = f.feed("\u{1B}[32mTest Case '-[FpTests.FpTests testPasses]' passed (0.001 seconds).\u{1B}[0m") else { return XCTFail("no result") }
        XCTAssertEqual(ok.status, .passed)
        XCTAssertNil(ok.message)
        guard case .finished(let skipped)? = f.feed("Test Case '-[FpTests.FpTests testSkips]' skipped (0.001 seconds).") else { return XCTFail("no result") }
        XCTAssertEqual(skipped.status, .skipped)
        XCTAssertNil(f.feed("Test Suite 'FpTests' started at 2026-10-04 21:26:42.631"))
    }

    // MARK: Store

    func testARunKeepsCountsAndFinishesFromItsResults() throws {
        let run = try store.startTestRun(projectId: project.id, agent: "agent-1", scope: "FpTests", pid: 1)
        try store.setRunningTest(runId: run, name: "FpTests testFails")
        XCTAssertEqual(try store.testRun(id: run)?.runningName, "FpTests testFails")
        try store.recordTestResult(TestResult(runId: run, bundle: "FpTests", suite: "FpTests", name: "testPasses()", status: .passed, duration: 0.1))
        try store.recordTestResult(TestResult(runId: run, bundle: "FpTests", suite: "FpTests", name: "testFails", status: .failed, message: "no"))
        var current = try XCTUnwrap(store.testRun(id: run))
        XCTAssertEqual(current.state, .running)
        XCTAssertEqual([current.passed, current.failed, current.total], [1, 1, 2])
        XCTAssertNil(current.runningName, "a finished test is no longer the one running")

        // The result bundle replaces what the log gave, and fixes the counts.
        try store.replaceTestResults(runId: run, with: try XCResult.parse(Data(Self.xcresult.utf8)))
        try store.finishTestRun(runId: run, resultPath: "/tmp/r.xcresult", source: "xcresult")
        current = try XCTUnwrap(store.testRun(id: run))
        XCTAssertEqual(current.state, .failed)
        XCTAssertEqual([current.passed, current.failed, current.skipped, current.total], [2, 1, 1, 4])
        XCTAssertEqual(current.source, "xcresult")
        XCTAssertNotNil(current.endedAt)
        XCTAssertEqual(try store.testResults(runId: run, problemsOnly: true).map(\.name), ["testFails"])
    }

    func testOverviewShowsTheLatestResultAndWhoRanIt() throws {
        try store.syncTestCatalog(projectId: project.id, repoId: nil, cases: [
            TestCaseInfo(bundle: "FpTests", suite: "FpTests", name: "testPasses"),
            TestCaseInfo(bundle: "FpTests", suite: "FpTests", name: "testNeverRun"),
        ])
        var clock = Date(timeIntervalSince1970: 1_000)
        let box = ClockBox(clock)
        store.now = { box.value }
        let first = try store.startTestRun(projectId: project.id, agent: "agent-1")
        try store.recordTestResult(TestResult(runId: first, bundle: "FpTests", suite: "FpTests", name: "testPasses", status: .failed))
        try store.finishTestRun(runId: first)
        clock.addTimeInterval(60); box.value = clock
        let second = try store.startTestRun(projectId: project.id, agent: "agent-2")
        try store.recordTestResult(TestResult(runId: second, bundle: "FpTests", suite: "FpTests", name: "testPasses", status: .passed))
        try store.finishTestRun(runId: second)

        let rows = try store.testOverview(projectId: project.id)
        let passes = try XCTUnwrap(rows.first { $0.info.name == "testPasses" })
        XCTAssertEqual(passes.lastStatus, .passed)
        XCTAssertEqual(passes.lastAgent, "agent-2")
        XCTAssertEqual(passes.lastRunId, second)
        XCTAssertNil(rows.first { $0.info.name == "testNeverRun" }?.lastStatus)
        let history = try store.testHistory(projectId: project.id, bundle: "FpTests", suite: "FpTests", name: "testPasses()")
        XCTAssertEqual(history.map(\.result.status), [.passed, .failed])
        XCTAssertEqual(history.map(\.run.agent), ["agent-2", "agent-1"])
    }

    func testAScanDropsTestsThatAreGoneAndARunAddsOnesTheScanMissed() throws {
        let t0 = ClockBox(Date(timeIntervalSince1970: 1_000))
        store.now = { t0.value }
        try store.syncTestCatalog(projectId: project.id, repoId: nil, cases: [TestCaseInfo(bundle: "B", suite: "S", name: "testOld")])
        t0.value = Date(timeIntervalSince1970: 2_000)
        try store.syncTestCatalog(projectId: project.id, repoId: nil, cases: [TestCaseInfo(bundle: "B", suite: "S", name: "testNew")])
        XCTAssertEqual(try store.testOverview(projectId: project.id).map(\.info.name), ["testNew"])

        let run = try store.startTestRun(projectId: project.id)
        try store.recordTestResult(TestResult(runId: run, bundle: "B", suite: "ObjC", name: "testGenerated", status: .passed))
        try store.finishTestRun(runId: run)
        XCTAssertEqual(Set(try store.testOverview(projectId: project.id).map(\.info.name)), ["testNew", "testGenerated"])
    }

    func testARunWhoseProcessIsGoneIsInterrupted() throws {
        let alive = try store.startTestRun(projectId: project.id, pid: 111)
        let gone = try store.startTestRun(projectId: project.id, pid: 222)
        try store.closeAbandonedTestRuns { $0 == 111 }
        XCTAssertEqual(try store.testRun(id: alive)?.state, .running)
        XCTAssertEqual(try store.testRun(id: gone)?.state, .interrupted)
        XCTAssertNotNil(try store.testRun(id: gone)?.error)
    }

    func testTheExpectedTotalComesFromTheLastFinishedRunWithTheSameScope() throws {
        let earlier = try store.startTestRun(projectId: project.id, scope: "FpTests")
        try store.replaceTestResults(runId: earlier, with: try XCResult.parse(Data(Self.xcresult.utf8)))
        try store.finishTestRun(runId: earlier, source: "xcresult")
        let now = try XCTUnwrap(store.testRun(id: try store.startTestRun(projectId: project.id, scope: "FpTests")))
        XCTAssertEqual(try store.expectedTestTotal(for: now), 4)
        let other = try XCTUnwrap(store.testRun(id: try store.startTestRun(projectId: project.id, scope: "Other")))
        XCTAssertNil(try store.expectedTestTotal(for: other))
    }
}

private final class ClockBox: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
}
