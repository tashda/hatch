import Foundation

/// Starting agent programs. An app opened from the Finder gets a short PATH (`/usr/bin:/bin:...`), so a program that
/// works in Terminal is not found, or starts but cannot find `node`. Hatch therefore looks in the usual install places
/// and asks the login shell once, and gives the child the same PATH.
public enum AgentProcess {
    public struct Result: Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String
    }

    /// Places programs are installed that a Finder-launched app does not have on its PATH.
    static var knownDirectories: [String] {
        let home = NSHomeDirectory()
        return [home + "/.local/bin", home + "/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
                home + "/.npm-global/bin", home + "/.bun/bin", home + "/.volta/bin", home + "/.cargo/bin",
                home + "/.opencode/bin", "/usr/bin", "/bin"]
    }

    private static let pathLock = NSLock()
    nonisolated(unsafe) private static var cachedLoginPath: String??

    /// PATH as the login shell sets it (asked once, with a short timeout), or nil.
    static func loginShellPath() -> String? {
        pathLock.lock(); defer { pathLock.unlock() }
        if let cached = cachedLoginPath { return cached }
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        var found: String?
        if FileManager.default.isExecutableFile(atPath: shell),
           let r = try? spawn(shell, ["-lc", "printf %s \"$PATH\""], stdin: nil, directory: nil, environment: nil, timeout: 5), r.status == 0 {
            let text = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { found = text }
        }
        cachedLoginPath = .some(found)
        return found
    }

    /// The PATH children get: the login shell's, this process's, then the known places, without duplicates.
    public static func searchPath() -> String {
        var parts: [String] = []
        let sources: [String?] = [loginShellPath(), ProcessInfo.processInfo.environment["PATH"], knownDirectories.joined(separator: ":")]
        for source in sources {
            for p in (source ?? "").split(separator: ":").map(String.init) where !p.isEmpty && !parts.contains(p) { parts.append(p) }
        }
        return parts.joined(separator: ":")
    }

    /// Absolute path of a program. A path in `configured` wins if it is executable; a bare name is searched for.
    public static func locate(_ name: String, configured: String? = nil) -> String? {
        let fm = FileManager.default
        if let c = configured?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            if c.contains("/") { return fm.isExecutableFile(atPath: c) ? c : nil }
            return locate(c)
        }
        if name.contains("/") { return fm.isExecutableFile(atPath: name) ? name : nil }
        for dir in searchPath().split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// This process's environment with the full PATH, minus `removing`, plus `adding`.
    public static func environment(removing: [String] = [], adding: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath()
        for k in removing { env.removeValue(forKey: k) }
        for (k, v) in adding { env[k] = v }
        return env
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
        var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    }

    /// Runs a program to the end, or stops it after `timeout` seconds. Stdin is empty unless `stdin` is given.
    public static func spawn(_ program: String, _ args: [String], stdin: String?, directory: URL?, environment: [String: String]?,
                             timeout: TimeInterval) throws -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: program)
        p.arguments = args
        if let directory { p.currentDirectoryURL = directory }
        if let environment { p.environment = environment }
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = err
        p.standardInput = stdin == nil ? FileHandle.nullDevice : inp
        let outC = Collector(), errC = Collector()
        let group = DispatchGroup()
        for (pipe, collector) in [(out, outC), (err, errC)] {
            group.enter()
            DispatchQueue.global().async {
                // Reading to the end in a thread keeps a chatty child from filling the pipe and blocking.
                collector.append(pipe.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
        }
        let finished = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in finished.signal() }
        do { try p.run() } catch { throw AgentRunnerError.executableNotFound(program) }
        if let stdin {
            DispatchQueue.global().async {
                try? inp.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
                try? inp.fileHandleForWriting.close()
            }
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = finished.wait(timeout: .now() + 2)
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            throw AgentRunnerError.timedOut(seconds: timeout)
        }
        group.wait()
        return Result(status: p.terminationStatus, stdout: outC.string, stderr: errC.string)
    }
}
