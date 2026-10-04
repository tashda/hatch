import Foundation
import HatchCore

/// What a clone on this Mac looks like right now, read from git without touching the network. The Health page uses it
/// to show where each repository stands; ahead and behind are against the last fetch.
public struct RepoProbe: Equatable, Sendable {
    public struct Commit: Equatable, Sendable {
        public var sha: String
        public var subject: String
        public var author: String
        public var date: Date
    }

    public var path: String
    public var exists: Bool
    /// The clone points at the repository the project names.
    public var matchesRemote: Bool
    public var branch: String?
    public var dirtyFiles: Int
    public var ahead: Int?
    public var behind: Int?
    public var recent: [Commit]
    /// Local `ticket/…` branches: work in progress on this Mac.
    public var ticketBranches: [String]
    /// Branches asked about by the caller (for example the integration branch), and whether each exists here or on origin.
    public var knownBranches: [String: Bool]

    public static func run(path: String, remote: String, branches: [String] = [], commits: Int = 5, git: GitRunner = ProcessGit()) -> RepoProbe {
        var p = RepoProbe(path: path, exists: false, matchesRemote: false, branch: nil, dirtyFiles: 0, ahead: nil, behind: nil,
                          recent: [], ticketBranches: [], knownBranches: [:])
        guard FileManager.default.fileExists(atPath: path + "/.git") else { return p }
        p.exists = true
        let config = (try? String(contentsOfFile: path + "/.git/config", encoding: .utf8)) ?? ""
        p.matchesRemote = LocalClones.configPoints(config, at: remote)
        p.branch = try? git.git(["rev-parse", "--abbrev-ref", "HEAD"], in: path)
        p.dirtyFiles = ((try? git.git(["status", "--porcelain"], in: path)) ?? "").split(separator: "\n").count
        if let counts = try? git.git(["rev-list", "--left-right", "--count", "HEAD...@{u}"], in: path) {
            let parts = counts.split(whereSeparator: { $0 == "\t" || $0 == " " }).compactMap { Int($0) }
            if parts.count == 2 { p.ahead = parts[0]; p.behind = parts[1] }
        }
        let sep = "\u{1f}"
        let log = (try? git.git(["log", "-n", String(commits), "--format=%h\(sep)%s\(sep)%an\(sep)%ct"], in: path)) ?? ""
        p.recent = log.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: sep)
            guard f.count == 4, let t = Double(f[3]) else { return nil }
            return Commit(sha: f[0], subject: f[1], author: f[2], date: Date(timeIntervalSince1970: t))
        }
        p.ticketBranches = ((try? git.git(["branch", "--list", "ticket/*", "--format=%(refname:short)"], in: path)) ?? "")
            .split(separator: "\n").map(String.init)
        for b in branches {
            p.knownBranches[b] = git.succeeds(["rev-parse", "--verify", "--quiet", b], in: path)
                || git.succeeds(["rev-parse", "--verify", "--quiet", "origin/\(b)"], in: path)
        }
        return p
    }
}
