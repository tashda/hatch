import XCTest
import Foundation
@testable import HatchSync

final class GitHubAccountTests: XCTestCase {
    var transport: CannedTransport!
    var client: GitHubClient!

    override func setUp() {
        transport = CannedTransport()
        client = GitHubClient(token: "tok", transport: transport)
    }

    func testCurrentUser() throws {
        transport.responses = [json(#"{"login":"ada","name":"Ada L"}"#)]
        let me = try client.currentUser()
        XCTAssertEqual(me, GitHubUser(login: "ada", name: "Ada L"))
        XCTAssertEqual(transport.requests[0].url.path, "/user")
    }

    func testListRepositoriesKeepsPrivacy() throws {
        transport.responses = [json(#"[{"full_name":"ada/tickets","private":true,"default_branch":"main"},{"full_name":"ada/site","private":false}]"#)]
        let repos = try client.listRepositories()
        XCTAssertEqual(repos.map(\.fullName), ["ada/tickets", "ada/site"])
        XCTAssertEqual(repos.map(\.isPrivate), [true, false])
        XCTAssertTrue(transport.requests[0].url.absoluteString.contains("per_page=100"))
    }

    func testListRepositoriesIncludesLaterPages() throws {
        let firstPage = (0..<100).map { #"{"full_name":"ada/repo\#($0)","private":true}"# }.joined(separator: ",")
        transport.responses = [json("[\(firstPage)]"), json(#"[{"full_name":"ada/last","private":true}]"#)]

        let repos = try client.listRepositories()

        XCTAssertEqual(repos.count, 101)
        XCTAssertEqual(repos.last?.fullName, "ada/last")
        XCTAssertTrue(transport.requests[1].url.absoluteString.contains("page=2"))
    }

    func testMissingRepositoryIsNil() throws {
        transport.responses = [json(#"{"message":"Not Found"}"#, status: 404)]
        XCTAssertNil(try client.repository("ada/none"))
    }

    func testCreatesAPrivateRepositoryWhenMissing() throws {
        transport.responses = [
            json(#"{"message":"Not Found"}"#, status: 404),                                  // repository(ada/tickets)
            json(#"{"login":"ada"}"#),                                                         // currentUser
            json(#"{"full_name":"ada/tickets","private":true,"default_branch":"main"}"#, status: 201),
            json("[]"),                                                                        // existing labels
        ]
        transport.responses += (0..<60).map { _ in json("{}", status: 201) }                    // label creations
        let report = try client.prepareTicketsRepo("ada/tickets", createIfMissing: true)
        XCTAssertTrue(report.created)
        XCTAssertFalse(report.isPublic)
        let create = transport.requests.first { $0.method == "POST" && $0.url.path == "/user/repos" }
        XCTAssertNotNil(create)
        let body = String(decoding: create?.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains(#""private":true"#), body)
        XCTAssertGreaterThan(report.labelsEnsured, 10)
    }

    func testLinkingAnExistingPublicRepositoryIsReported() throws {
        transport.responses = [json(#"{"full_name":"ada/open","private":false,"default_branch":"main"}"#), json("[]")]
        transport.responses += (0..<60).map { _ in json("{}", status: 201) }
        let report = try client.prepareTicketsRepo("ada/open", createIfMissing: false)
        XCTAssertFalse(report.created)
        XCTAssertTrue(report.isPublic, "the app must be able to warn that tickets would be public")
    }

    func testMissingRepositoryWithoutCreateIsAnError() {
        transport.responses = [json(#"{"message":"Not Found"}"#, status: 404)]
        XCTAssertThrowsError(try client.prepareTicketsRepo("ada/none", createIfMissing: false))
    }

    func testOrganisationRepositoryUsesTheOrgEndpoint() throws {
        transport.responses = [
            json(#"{"message":"Not Found"}"#, status: 404), json(#"{"login":"ada"}"#),
            json(#"{"full_name":"acme/tickets","private":true}"#, status: 201), json("[]"),
        ]
        transport.responses += (0..<60).map { _ in json("{}", status: 201) }
        _ = try client.prepareTicketsRepo("acme/tickets", createIfMissing: true)
        XCTAssertTrue(transport.requests.contains { $0.url.path == "/orgs/acme/repos" })
    }
}

final class GitHubBranchTests: XCTestCase {
    func testListBranches() throws {
        let transport = CannedTransport()
        transport.responses = [json(#"[{"name":"main"},{"name":"dev"}]"#)]
        let client = GitHubClient(token: "tok", transport: transport)
        XCTAssertEqual(try client.listBranches("ada/app"), ["main", "dev"])
        XCTAssertEqual(transport.requests[0].url.path, "/repos/ada/app/branches")
    }

    func testEnsureBranchCreatesFromBase() throws {
        let transport = CannedTransport()
        transport.responses = [HTTPResponse(status: 404), json(#"{"object":{"sha":"abc123"}}"#), json("{}", status: 201)]
        let client = GitHubClient(token: "tok", transport: transport)
        XCTAssertTrue(try client.ensureBranch("ada/app", name: "hatch", from: "dev"))
        XCTAssertEqual(transport.requests.map(\.url.path), ["/repos/ada/app/git/ref/heads/hatch", "/repos/ada/app/git/ref/heads/dev", "/repos/ada/app/git/refs"])
        XCTAssertTrue(String(decoding: transport.requests[2].body ?? Data(), as: UTF8.self).contains("abc123"))
    }

    func testEnsureBranchLeavesExistingBranch() throws {
        let transport = CannedTransport()
        transport.responses = [json(#"{"object":{"sha":"abc"}}"#)]
        let client = GitHubClient(token: "tok", transport: transport)
        XCTAssertFalse(try client.ensureBranch("ada/app", name: "hatch", from: "dev"))
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testAppClientDoesNotFallBackToOtherTokens() {
        let client = GitHubClient(token: nil, fallback: false, transport: CannedTransport())
        XCTAssertThrowsError(try client.currentUser())
    }
}

/// What Settings › GitHub reads: the account picture, the installation's access, the rate limit and the labels.
final class GitHubSettingsClientTests: XCTestCase {
    var transport: CannedTransport!
    var client: GitHubClient!

    override func setUp() {
        transport = CannedTransport()
        client = GitHubClient(token: "tok", transport: transport)
    }

    func testCurrentUserReadsTheAvatar() throws {
        transport.responses = [json(#"{"login":"ada","avatar_url":"https://avatars.githubusercontent.com/u/1"}"#)]
        XCTAssertEqual(try client.currentUser().avatarURL?.absoluteString, "https://avatars.githubusercontent.com/u/1")
    }

    func testInstallationsReadPermissionsAndSelection() throws {
        transport.responses = [json(#"""
        {"total_count":1,"installations":[{"id":7,"app_slug":"hatch","account":{"login":"ada"},
          "html_url":"https://github.com/settings/installations/7","repository_selection":"selected",
          "permissions":{"issues":"write","metadata":"read","checks":"read"}}]}
        """#)]
        let installation = try XCTUnwrap(client.installations().first)
        XCTAssertEqual(installation.repositorySelection, "selected")
        XCTAssertFalse(installation.allRepositories)
        XCTAssertEqual(installation.permissions, ["issues": "write", "metadata": "read", "checks": "read"])
    }

    func testPermissionNeedsCompareTheLowestGrant() {
        let granted = ["issues": "write", "contents": "read", "checks": "read", "metadata": "read", "administration": "admin"]
        let needs = Dictionary(uniqueKeysWithValues: GitHubPermissionNeed.all.map { ($0.title, $0) })
        XCTAssertTrue(needs["Issues"]!.isMet(in: granted))
        XCTAssertEqual(needs["Contents"]!.granted(in: granted), .read)
        XCTAssertFalse(needs["Contents"]!.isMet(in: granted), "read is not enough to push Hatch's branch")
        XCTAssertFalse(needs["Pull requests"]!.isMet(in: granted))
        XCTAssertEqual(needs["Checks and commit statuses"]!.granted(in: granted), GitHubAccess.none, "statuses is missing")
        XCTAssertTrue(needs["Administration"]!.isMet(in: granted), "admin counts as write")
        XCTAssertTrue(needs["Metadata"]!.isMet(in: granted))
    }

    func testInstallationRepositoryCount() throws {
        transport.responses = [json(#"{"total_count":12,"repositories":[{"full_name":"ada/a"}]}"#)]
        XCTAssertEqual(try client.installationRepositoryCount(7), 12)
        XCTAssertEqual(transport.requests[0].url.path, "/user/installations/7/repositories")
    }

    func testRateLimitReadsTheCoreAllowance() throws {
        transport.responses = [json(#"{"resources":{"core":{"limit":5000,"remaining":4812,"reset":1790000000,"used":188}},"rate":{}}"#)]
        let limit = try client.rateLimit()
        XCTAssertEqual(limit, GitHubRateLimit(remaining: 4812, limit: 5000, reset: Date(timeIntervalSince1970: 1_790_000_000)))
        XCTAssertEqual(transport.requests[0].url.path, "/rate_limit")
    }

    func testMissingHatchLabels() throws {
        let present = LabelSpec.baseSet.dropFirst(2).map { #"{"name":"\#($0.name.uppercased())"}"# }.joined(separator: ",")
        transport.responses = [json("[\(present),{\"name\":\"bug\"}]")]
        let missing = try client.missingHatchLabels(repo: "ada/tickets")
        XCTAssertEqual(missing, LabelSpec.baseSet.prefix(2).map(\.name), "names compare without case")
        XCTAssertEqual(transport.requests[0].url.path, "/repos/ada/tickets/labels")
    }

    func testAllLabelsPresent() throws {
        transport.responses = [json("[" + LabelSpec.baseSet.map { #"{"name":"\#($0.name)"}"# }.joined(separator: ",") + "]")]
        XCTAssertEqual(try client.missingHatchLabels(repo: "ada/tickets"), [])
    }
}
