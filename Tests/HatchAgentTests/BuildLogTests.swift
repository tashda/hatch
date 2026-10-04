import XCTest
@testable import HatchAgent

/// Lines taken from real SwiftPM, xcodebuild, XCTest and Swift Testing output on the owner's Mac.
final class BuildLogTests: XCTestCase {
    let root = "/w/ticket-12/app"

    func testCompileErrorKeepsTheDiagnosticAndDropsTheNoise() {
        let log = """
        Building for debugging...
        error: SwiftCompile normal arm64 /w/ticket-12/app/Sources/Lib/Lib.swift failed with a nonzero exit code. Command line:     cd /w
        \u{1B}[1m/w/ticket-12/app/Sources/Lib/Lib.swift:2:54: \u{1B}[1;31merror: \u{1B}[1;39mcannot convert return expression of type 'String' to return type 'Int'\u{1B}[0;0m
          \u{1B}[0;36m|\u{1B}[0;0m                                 `- \u{1B}[1;31merror: \u{1B}[1;39mcannot convert return expression of type 'String' to return type 'Int'\u{1B}[0;0m
        /usr/bin/swift-frontend -frontend -c \(String(repeating: "-Xcc -I/some/long/path ", count: 80))
        /w/ticket-12/app/Sources/Lib/Lib.swift:2:54: error: cannot convert return expression of type 'String' to return type 'Int'
        error: Build failed
        """
        let d = BuildLog.digest(log, ok: false, root: root)
        XCTAssertEqual(d.errors, 1, "the repeated copy of the same error counts once")
        XCTAssertEqual(d.text, """
        FAILED: 1 error, 0 warnings
        error Sources/Lib/Lib.swift:2:54 cannot convert return expression of type 'String' to return type 'Int'
        error: Build failed
        """)
    }

    func testWarningsLoseTheirDocumentationLinkAndAreCountedOnce() {
        let w = "/w/ticket-12/app/Sources/A.swift:4:35: \u{1B}[1;33mwarning: \u{1B}[1;39minitialization of immutable value 'unused' was never used\u{1B}[0;0m [#]8;;https://docs.swift.org/x\u{1B}\\NoUsage]8;;\u{1B}\\]"
        let d = BuildLog.digest([w, w, "** BUILD SUCCEEDED **"].joined(separator: "\n"), ok: true, root: root)
        XCTAssertEqual(d.warnings, 1)
        XCTAssertEqual(d.text, "passed: 0 errors, 1 warning\nwarning Sources/A.swift:4:35 initialization of immutable value 'unused' was never used\n** BUILD SUCCEEDED **")
    }

    func testFailingTestsAndTheSummary() {
        let log = """
        /w/ticket-12/app/Tests/LibTests/LibTests.swift:5: error: -[LibTests.LibTests testAdd] : XCTAssertEqual failed: ("3") is not equal to ("4")
        Test Case '-[LibTests.LibTests testAdd]' failed (0.264 seconds).
        Test Case '-[LibTests.LibTests testOK]' passed (0.000 seconds).
        Test Suite 'LibTests' failed at 2026-10-04 20:11:28.751.
        \t Executed 2 tests, with 1 failure (0 unexpected) in 0.264 (0.264) seconds
        Test Suite 'All tests' failed at 2026-10-04 20:11:28.751.
        \t Executed 2 tests, with 1 failure (0 unexpected) in 0.264 (0.273) seconds
        􀢄  Test swiftTestingAdd() recorded an issue at LibTests.swift:8:32: Expectation failed: add(2, 2) == 5
        􀢄  Test run with 1 test in 0 suites failed after 0.001 seconds with 1 issue.
        """
        let d = BuildLog.digest(log, ok: false, root: root)
        XCTAssertTrue(d.text.contains("error Tests/LibTests/LibTests.swift:5 -[LibTests.LibTests testAdd] : XCTAssertEqual failed"))
        XCTAssertTrue(d.text.contains("failed: -[LibTests.LibTests testAdd]"))
        XCTAssertFalse(d.text.contains("testOK"))
        XCTAssertTrue(d.text.contains("recorded an issue at LibTests.swift:8:32: Expectation failed"))
        XCTAssertEqual(d.text.components(separatedBy: "Executed ").count - 1, 1, "one test summary, not one per suite")
        XCTAssertTrue(d.text.contains("Test run with 1 test in 0 suites failed"))
    }

    func testSeveralBundlesGetOneTotalCountingSkipsRight() {
        let log = """
        Test Suite 'All tests' passed at 2026-10-04 19:00:00.000.
        \t Executed 50 tests, with 0 failures (0 unexpected) in 0.3 (0.3) seconds
        Test Suite 'All tests' passed at 2026-10-04 19:00:01.000.
        \t Executed 56 tests, with 16 tests skipped and 0 failures (0 unexpected) in 0.1 (0.1) seconds
        """
        XCTAssertTrue(BuildLog.digest(log, ok: true).text.hasSuffix("Executed 106 tests in 2 bundles, with 0 failures"))
    }

    func testOtherToolchainsAndAnUnrecognisedFailure() {
        let npm = "npm ERR! code ELIFECYCLE\nsome output\nFAIL src/app.test.js"
        let d = BuildLog.digest(npm, ok: false)
        XCTAssertEqual(d.errors, 2)
        let odd = (1...50).map { "line \($0)" }.joined(separator: "\n")
        let fallback = BuildLog.digest(odd, ok: false).text
        XCTAssertTrue(fallback.contains("no error lines recognised"))
        XCTAssertTrue(fallback.contains("line 50") && fallback.contains("line 21") && !fallback.contains("line 20\n"), "the last 30 lines")
    }

    func testLongLogsAreCapped() {
        let many = (1...200).map { "/w/ticket-12/app/F\($0).swift:1:1: error: problem \($0)" }.joined(separator: "\n")
        let d = BuildLog.digest(many, ok: false, root: root)
        XCTAssertEqual(d.errors, 200)
        XCTAssertTrue(d.text.contains("… and 160 more errors"))
        XCTAssertLessThan(d.text.count, 8200)
    }

    func testPathsWithSpacesAndFatalErrors() {
        let d = BuildLog.digest("/Users/k/My Project/A.swift:3:1: fatal error: module 'X' not found", ok: false)
        XCTAssertEqual(d.text, "FAILED: 1 error, 0 warnings\nerror /Users/k/My Project/A.swift:3:1 module 'X' not found")
    }
}
