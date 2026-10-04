import XCTest
@testable import HatchGit

final class LocalClonesTests: XCTestCase {
    func testRepositoryFromURL() {
        XCTAssertEqual(LocalClones.repository(fromURL: "https://github.com/Tashda/Echo.git"), "tashda/echo")
        XCTAssertEqual(LocalClones.repository(fromURL: "git@github.com:tashda/echo.git"), "tashda/echo")
        XCTAssertEqual(LocalClones.repository(fromURL: "ssh://git@github.com/tashda/echo"), "tashda/echo")
        XCTAssertNil(LocalClones.repository(fromURL: "https://gitlab.com/tashda/echo.git"))
        XCTAssertNil(LocalClones.repository(fromURL: "https://github.com/tashda"))
    }

    func testFindsClonesByRemoteAndSkipsOthers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clones-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func makeClone(_ path: String, url: String) throws {
            let git = root.appendingPathComponent(path).appendingPathComponent(".git")
            try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
            try "[remote \"origin\"]\n\turl = \(url)\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n"
                .write(to: git.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        }
        try makeClone("echo", url: "git@github.com:tashda/echo.git")
        try makeClone("work/echo-copy", url: "https://github.com/tashda/echo")
        try makeClone("other", url: "https://github.com/tashda/other.git")
        try makeClone("deep/a/b/c/echo", url: "https://github.com/tashda/echo.git")

        let found = LocalClones.find("tashda/echo", in: [root], depth: 3)
        XCTAssertEqual(found.map { URL(fileURLWithPath: $0).lastPathComponent }, ["echo", "echo-copy"])
    }
}

final class BuildCommandTests: XCTestCase {
    func testSuggestsFromTopLevel() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("build-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertNil(BuildCommand.suggest(in: root.path))
        try "".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        XCTAssertEqual(BuildCommand.suggest(in: root.path), "swift build")
        try fm.createDirectory(at: root.appendingPathComponent("Echo.xcodeproj"), withIntermediateDirectories: true)
        XCTAssertEqual(BuildCommand.suggest(in: root.path), "xcodebuild -project Echo.xcodeproj -scheme Echo build")
    }
}
