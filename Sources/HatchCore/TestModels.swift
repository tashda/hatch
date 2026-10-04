import Foundation

/// How one test ended. `running` is only used while a run is in flight.
public enum TestStatus: String, Codable, CaseIterable, Sendable {
    case passed, failed, skipped, running

    /// Reads xcresulttool's "Passed", "Failed", "Skipped", "Expected Failure" and the like.
    public init(xcresult text: String) {
        switch text.lowercased() {
        case "passed", "expected failure": self = .passed
        case "failed": self = .failed
        default: self = .skipped
        }
    }
}

public enum TestRunState: String, Codable, Sendable {
    case running, passed, failed
    /// The process that ran it ended without a result (a crash, or it was stopped).
    case interrupted
}

/// A test as the sources declare it (the catalog).
public struct TestCaseInfo: Identifiable, Equatable, Hashable, Sendable {
    public var bundle: String
    public var suite: String
    public var name: String
    /// "xctest" or "swift-testing".
    public var kind: String
    public var file: String?
    public var line: Int?
    public var id: String { "\(bundle)/\(suite)/\(name)" }

    public init(bundle: String, suite: String, name: String, kind: String = "xctest", file: String? = nil, line: Int? = nil) {
        self.bundle = bundle; self.suite = suite; self.name = TestName.normalized(name); self.kind = kind; self.file = file; self.line = line
    }
}

/// One test's outcome in one run.
public struct TestResult: Identifiable, Equatable, Sendable {
    public var runId: Int
    public var bundle: String
    public var suite: String
    public var name: String
    public var status: TestStatus
    public var duration: Double?
    public var message: String?
    public var file: String?
    public var line: Int?
    public var id: String { "\(runId)/\(bundle)/\(suite)/\(name)" }

    public init(runId: Int = 0, bundle: String, suite: String, name: String, status: TestStatus, duration: Double? = nil,
                message: String? = nil, file: String? = nil, line: Int? = nil) {
        self.runId = runId; self.bundle = bundle; self.suite = suite; self.name = TestName.normalized(name)
        self.status = status; self.duration = duration; self.message = message; self.file = file; self.line = line
    }
}

public struct TestRun: Identifiable, Equatable, Sendable {
    public var id: Int
    public var projectId: Int
    public var repoId: Int?
    public var ticketId: Int?
    /// Who ran it: the agent that holds the ticket, or nil for a run recorded by hand.
    public var agent: String?
    public var command: String?
    /// What was asked for: a test plan, a target or a filter. Nil means everything the command runs.
    public var scope: String?
    public var branch: String?
    public var commit: String?
    public var pid: Int?
    public var state: TestRunState
    public var total: Int
    public var passed: Int
    public var failed: Int
    public var skipped: Int
    /// The test running now, while the run is in flight.
    public var runningName: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var resultPath: String?
    /// "xcresult" when the counts come from the result bundle, "log" when they were read from the output.
    public var source: String
    public var error: String?

    public var finished: Bool { state != .running }
    public var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
    /// Tests that have a result so far.
    public var done: Int { passed + failed + skipped }
}

/// A catalog entry with the latest result of that test, for the page's tree.
public struct TestOverviewRow: Identifiable, Equatable, Sendable {
    public var info: TestCaseInfo
    public var lastStatus: TestStatus?
    public var lastRunId: Int?
    public var lastAt: Date?
    public var lastAgent: String?
    public var lastTicketId: Int?
    public var lastMessage: String?
    public var id: String { info.id }
}

public enum TestName {
    /// `testFoo()` and `testFoo` are the same test; xcresult adds the parentheses, the log and the sources do not.
    public static func normalized(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespaces)
        if n.hasSuffix("()") { n.removeLast(2) }
        return n
    }
}
