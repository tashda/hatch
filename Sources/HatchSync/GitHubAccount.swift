import Foundation
import HatchCore

public struct GitHubUser: Equatable, Sendable {
    public var login: String
    public var name: String?
    public init(login: String, name: String? = nil) { self.login = login; self.name = name }
}

public struct GitHubRepoSummary: Equatable, Sendable, Identifiable {
    public var fullName: String            // "owner/name"
    public var isPrivate: Bool
    public var description: String?
    public var defaultBranch: String
    public var id: String { fullName }
    public init(fullName: String, isPrivate: Bool, description: String? = nil, defaultBranch: String = "main") {
        self.fullName = fullName; self.isPrivate = isPrivate; self.description = description; self.defaultBranch = defaultBranch
    }
}

/// Where Hatch's GitHub App is installed for the signed-in user. Hatch sees only the repositories chosen there.
public struct GitHubInstallation: Equatable, Sendable {
    public var id: Int
    public var appSlug: String
    public var account: String
    /// GitHub's page for this installation, where repositories are added or removed.
    public var settingsURL: URL
    public var allRepositories: Bool
}

/// Where the token in use comes from, for Settings. Order: stored by Hatch, `GITHUB_TOKEN`, the gh tool.
public enum GitHubTokenSource: Equatable, Sendable {
    case stored, environment, ghTool, none
}

/// What `GitHubClient.prepareTicketsRepo` did, so the app can tell the owner in plain words.
public struct TicketsRepoReport: Equatable, Sendable {
    public var repo: GitHubRepoSummary
    public var created: Bool
    public var labelsEnsured: Int
    /// A public tickets repository would expose private tickets: the app refuses to use it unless the owner insists.
    public var isPublic: Bool { !repo.isPrivate }
}

extension GitHubClient {
    static func summary(_ j: JSONValue) -> GitHubRepoSummary? {
        guard let full = j["full_name"]?.stringValue else { return nil }
        return GitHubRepoSummary(fullName: full, isPrivate: j["private"]?.boolValue ?? true,
                                 description: j["description"]?.stringValue, defaultBranch: j["default_branch"]?.stringValue ?? "main")
    }

    /// Who the token belongs to. Also proves the token works.
    public func currentUser() throws -> GitHubUser {
        let r = try perform("GET", url("/user"))
        let j = JSONValue.parse(String(decoding: r.body, as: UTF8.self))
        guard let login = j["login"]?.stringValue else { throw TrackerError.http(status: 200, message: "GitHub did not say who this token belongs to.") }
        return GitHubUser(login: login, name: j["name"]?.stringValue)
    }

    /// Repositories the token can use, most recently pushed first. Fetch enough pages for the selector.
    public func listRepositories(limit: Int = 300) throws -> [GitHubRepoSummary] {
        guard limit > 0 else { return [] }
        var results: [GitHubRepoSummary] = []
        var page = 1
        while results.count < limit {
            let pageSize = min(limit - results.count, 100)
            let r = try perform("GET", url("/user/repos", [("per_page", String(pageSize)), ("page", String(page)),
                                                            ("sort", "pushed"),
                                                            ("affiliation", "owner,collaborator,organization_member")]))
            let batch = JSONValue.parse(String(decoding: r.body, as: UTF8.self)).arrayValue ?? []
            results.append(contentsOf: batch.compactMap(Self.summary))
            if batch.count < pageSize { break }
            page += 1
        }
        return Array(results.prefix(limit))
    }

    /// nil when the repository does not exist or the token cannot see it.
    public func repository(_ fullName: String) throws -> GitHubRepoSummary? {
        do {
            let r = try perform("GET", url(repoPath(fullName)))
            return Self.summary(JSONValue.parse(String(decoding: r.body, as: UTF8.self)))
        } catch TrackerError.notFound { return nil }
    }

    /// Creates a repository. Private unless told otherwise. With `organization`, in that organization instead of the user's account.
    public func createRepository(name: String, description: String, isPrivate: Bool = true, organization: String? = nil) throws -> GitHubRepoSummary {
        let path = organization.map { "/orgs/\($0)/repos" } ?? "/user/repos"
        let body: JSONValue = ["name": .string(name), "description": .string(description), "private": .bool(isPrivate), "auto_init": .bool(true)]
        let r = try perform("POST", url(path), body: body)
        guard let s = Self.summary(JSONValue.parse(String(decoding: r.body, as: UTF8.self))) else {
            throw TrackerError.http(status: 201, message: "GitHub created the repository but did not describe it.")
        }
        return s
    }

    /// Makes `fullName` ready to hold tickets: creates it (private) when missing and `createIfMissing`, then makes sure the Hatch labels exist.
    public func prepareTicketsRepo(_ fullName: String, createIfMissing: Bool) throws -> TicketsRepoReport {
        var created = false
        var found = try repository(fullName)
        if found == nil {
            guard createIfMissing else { throw TrackerError.notFound("\(fullName) does not exist, or this token cannot see it.") }
            let parts = fullName.split(separator: "/").map(String.init)
            guard parts.count == 2 else { throw TrackerError.validation("A repository is written owner/name.") }
            let me = try currentUser()
            found = try createRepository(name: parts[1], description: "Tickets for Hatch. Private on purpose.", isPrivate: true,
                                         organization: parts[0].lowercased() == me.login.lowercased() ? nil : parts[0])
            created = true
        }
        let labels = LabelSpec.baseSet.map { $0 }
        try ensureLabels(repo: fullName, labels)
        return TicketsRepoReport(repo: found!, created: created, labelsEnsured: labels.count)
    }

    /// Installations of the GitHub App this token belongs to, for the signed-in user.
    public func installations() throws -> [GitHubInstallation] {
        let r = try perform("GET", url("/user/installations", [("per_page", "100")]))
        let list = JSONValue.parse(String(decoding: r.body, as: UTF8.self))["installations"]?.arrayValue ?? []
        return list.compactMap { j in
            guard let id = j["id"]?.intValue, let link = j["html_url"]?.stringValue, let u = URL(string: link) else { return nil }
            return GitHubInstallation(id: id, appSlug: j["app_slug"]?.stringValue ?? "", account: j["account"]?["login"]?.stringValue ?? "",
                                      settingsURL: u, allRepositories: j["repository_selection"]?.stringValue == "all")
        }
    }

    /// Branch names of a repository, the default branch's first page included. For the base branch picker.
    public func listBranches(_ fullName: String, limit: Int = 200) throws -> [String] {
        var names: [String] = []
        var page = 1
        while names.count < limit {
            let r = try perform("GET", url("\(repoPath(fullName))/branches", [("per_page", "100"), ("page", String(page))]))
            let batch = JSONValue.parse(String(decoding: r.body, as: UTF8.self)).arrayValue ?? []
            names.append(contentsOf: batch.compactMap { $0["name"]?.stringValue })
            if batch.count < 100 { break }
            page += 1
        }
        return Array(names.prefix(limit))
    }

    /// Makes sure `name` exists in `fullName`, branching it from `base` when missing. True when it was created.
    @discardableResult
    public func ensureBranch(_ fullName: String, name: String, from base: String) throws -> Bool {
        do {
            _ = try perform("GET", url("\(repoPath(fullName))/git/ref/heads/\(name)"))
            return false
        } catch TrackerError.notFound {}
        let r = try perform("GET", url("\(repoPath(fullName))/git/ref/heads/\(base)"))
        guard let sha = JSONValue.parse(String(decoding: r.body, as: UTF8.self))["object"]?["sha"]?.stringValue else {
            throw TrackerError.http(status: r.status, message: "GitHub did not return the commit of \(base).")
        }
        _ = try perform("POST", url("\(repoPath(fullName))/git/refs"), body: ["ref": .string("refs/heads/\(name)"), "sha": .string(sha)])
        return true
    }

    /// Which source the token would come from right now, without using it.
    public static func tokenSource(stored: String?) -> GitHubTokenSource {
        if let stored, !stored.isEmpty { return .stored }
        if let env = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !env.isEmpty { return .environment }
        if let out = runGh(), !out.isEmpty { return .ghTool }
        return .none
    }
}
