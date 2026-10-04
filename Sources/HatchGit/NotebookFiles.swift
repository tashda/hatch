import Foundation
import HatchCore

/// Puts the notebook's coding rules where agents look: `AGENTS.md` and a `CLAUDE.md` that imports it, at the top of a
/// clone or worktree of the code. Both are listed in the repository's `.git/info/exclude`, so they are never committed
/// and the app's own .gitignore is left alone.
public enum RulesPlacer {
    public enum Outcome: Equatable, Sendable {
        case placed
        /// The app commits its own AGENTS.md; Hatch leaves it and the rules go in the brief instead.
        case appHasOwn
        /// A file there was written by someone, not by Hatch. Left alone so nothing is lost.
        case keptLocalFile(String)
    }

    public static let files = ["AGENTS.md", "CLAUDE.md"]

    @discardableResult
    public static func place(rules: String, into dir: String, git: GitRunner = ProcessGit()) throws -> Outcome {
        if git.succeeds(["ls-files", "--error-unmatch", "AGENTS.md"], in: dir) { return .appHasOwn }
        for name in files {
            let path = (dir as NSString).appendingPathComponent(name)
            if let existing = try? String(contentsOfFile: path, encoding: .utf8), !existing.hasPrefix(Notebook.placedMarker) {
                return .keptLocalFile(name)
            }
        }
        try (Notebook.placedMarker + "\n" + rules).write(toFile: (dir as NSString).appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try (Notebook.placedMarker + "\n@AGENTS.md\n").write(toFile: (dir as NSString).appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try exclude(files, in: dir, git: git)
        return .placed
    }

    /// The project's own agent file in a clone, when it is not committed and not Hatch's copy: AGENTS.md first, then CLAUDE.md.
    /// Setup imports it into the notebook so the owner's existing rules carry over.
    public static func existingRules(in dir: String, git: GitRunner = ProcessGit()) -> String? {
        for name in files {
            let path = (dir as NSString).appendingPathComponent(name)
            guard let text = try? String(contentsOfFile: path, encoding: .utf8),
                  !text.hasPrefix(Notebook.placedMarker),
                  !git.succeeds(["ls-files", "--error-unmatch", name], in: dir),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            return text
        }
        return nil
    }

    /// Adds `names` to the shared `info/exclude` of the repository `dir` belongs to (worktrees share it).
    static func exclude(_ names: [String], in dir: String, git: GitRunner) throws {
        let common = try git.git(["rev-parse", "--git-common-dir"], in: dir)
        let commonURL = common.hasPrefix("/") ? URL(fileURLWithPath: common) : URL(fileURLWithPath: dir).appendingPathComponent(common)
        let info = commonURL.appendingPathComponent("info")
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        let file = info.appendingPathComponent("exclude")
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let present = Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        let missing = names.map { "/\($0)" }.filter { !present.contains($0) }
        guard !missing.isEmpty else { return }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "# Agent rules placed by Hatch from the project notebook\n" + missing.joined(separator: "\n") + "\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}

/// Writes files into the notebook clone and commits them.
public enum NotebookWriter {
    /// Writes each file that does not exist yet. Existing files are never overwritten. Returns the paths written.
    @discardableResult
    public static func writeMissing(_ files: [String: String], in dir: String) throws -> [String] {
        var written: [String] = []
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(path)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            written.append(path)
        }
        return written
    }

    /// Writes `files`, replacing what is there. For the files Hatch keeps current, such as NOW.md and project.json.
    public static func write(_ files: [String: String], in dir: String) throws {
        for (path, text) in files {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Commits everything that changed, if anything did. Pushing is separate, so a failed push never loses the commit.
    @discardableResult
    public static func commit(_ message: String, in dir: String, git: GitRunner = ProcessGit()) throws -> Bool {
        try git.git(["add", "-A"], in: dir)
        guard !git.succeeds(["diff", "--cached", "--quiet"], in: dir) else { return false }
        try git.git(["commit", "-m", message], in: dir)
        return true
    }

    /// Pushes the current branch over HTTPS with the token for this command only.
    public static func push(in dir: String, token: String?, git: GitRunner = ProcessGit()) throws {
        var args: [String] = []
        if let token, !token.isEmpty {
            args += ["-c", "http.extraHeader=Authorization: Basic \(Data("x-access-token:\(token)".utf8).base64EncodedString())"]
        }
        try git.git(args + ["push", "origin", "HEAD"], in: dir)
    }
}
