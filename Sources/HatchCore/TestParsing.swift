import Foundation

/// Finds the tests a repository declares by reading its Swift files, so the catalog needs no build and no model call
/// (rule 4: free local work first). It is a line scanner, not a parser: a suite is a class that inherits a `…TestCase`
/// or a type marked `@Suite`, a test is `func test…()` in such a class or a function marked `@Test`.
public enum TestScanner {
    static let skipped: Set<String> = [".build", ".git", "DerivedData", "node_modules", "Pods", "Carthage", ".swiftpm", "build"]

    public static func scan(root: URL) -> [TestCaseInfo] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [TestCaseInfo] = []
        let base = root.resolvingSymlinksInPath().path
        for case let url as URL in walker {
            if skipped.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
            guard url.pathExtension == "swift" else { continue }
            let relative = String(url.resolvingSymlinksInPath().path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let bundle = bundleName(for: relative), let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out += scan(source: text, bundle: bundle, file: relative)
        }
        return out.sorted { ($0.bundle, $0.suite, $0.name) < ($1.bundle, $1.suite, $1.name) }
    }

    /// The test bundle a path belongs to: `Tests/HatchCoreTests/X.swift` is HatchCoreTests, `AppTests/X.swift` is AppTests.
    /// Nil for files that are not in a test folder.
    static func bundleName(for relativePath: String) -> String? {
        let parts = relativePath.split(separator: "/").map(String.init)
        for (i, part) in parts.enumerated().dropLast() {
            if part == "Tests" || part == "UITests", i + 1 < parts.count - 1 { return parts[i + 1] }
            if part.hasSuffix("Tests") || part.hasSuffix("UITests") { return part }
        }
        return nil
    }

    private struct Scope { var name: String; var suite: Bool; var xctest: Bool; var depth: Int }

    public static func scan(source: String, bundle: String, file: String) -> [TestCaseInfo] {
        var out: [TestCaseInfo] = []
        var stack: [Scope] = []
        var depth = 0
        var pendingTest = false          // an `@Test` attribute waiting for its function
        var pendingSuite = false         // an `@Suite` attribute waiting for its type
        var inBlockComment = false
        for (index, raw) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var line = String(raw)
            if inBlockComment {
                guard let end = line.range(of: "*/") else { continue }
                line = String(line[end.upperBound...]); inBlockComment = false
            }
            line = stripComments(line, inBlock: &inBlockComment)
            let code = line.trimmingCharacters(in: .whitespaces)

            if code.hasPrefix("@Suite") { pendingSuite = true }
            if code.hasPrefix("@Test") { pendingTest = true }

            var body = code
            if let decl = typeDeclaration(code) {
                let isXCTest = decl.inherits.contains { $0.hasSuffix("TestCase") } || (decl.keyword == "extension" && decl.name.hasSuffix("Tests"))
                stack.append(Scope(name: decl.name, suite: isXCTest || pendingSuite, xctest: isXCTest, depth: depth))
                pendingSuite = false
                // A one-line type: whatever follows the brace is still its body.
                body = code.firstIndex(of: "{").map { String(code[code.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
            }
            if let name = functionName(body) {
                if let scope = stack.last(where: { $0.suite }) ?? stack.last {
                    if pendingTest {
                        out.append(TestCaseInfo(bundle: bundle, suite: scope.name, name: name, kind: "swift-testing", file: file, line: index + 1))
                    } else if scope.xctest, name.hasPrefix("test"), body.contains("\(name)()") {
                        out.append(TestCaseInfo(bundle: bundle, suite: scope.name, name: name, kind: "xctest", file: file, line: index + 1))
                    }
                }
                pendingTest = false
            } else if pendingTest, !body.hasPrefix("@"), !body.isEmpty, !body.hasPrefix("//") {
                pendingTest = false
            }

            for ch in line {
                if ch == "{" { depth += 1 }
                if ch == "}" { depth -= 1; while let last = stack.last, last.depth >= depth { stack.removeLast() } }
            }
        }
        return out
    }

    /// Removes `//` comments and string contents from a line so braces inside them are not counted.
    private static func stripComments(_ line: String, inBlock: inout Bool) -> String {
        var out = "", chars = Array(line), i = 0, inString = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                if c == "\\" { i += 2; continue }
                if c == "\"" { inString = false }
                i += 1; continue
            }
            if c == "\"" { inString = true; out.append(c); i += 1; continue }
            if c == "/", i + 1 < chars.count {
                if chars[i + 1] == "/" { break }
                if chars[i + 1] == "*" {
                    if let end = chars[(i + 2)...].indices.first(where: { $0 + 1 < chars.count && chars[$0] == "*" && chars[$0 + 1] == "/" }) { i = end + 2; continue }
                    inBlock = true; break
                }
            }
            out.append(c); i += 1
        }
        return out
    }

    private static let typeKeywords = ["class", "struct", "actor", "enum", "extension"]

    private static func typeDeclaration(_ code: String) -> (keyword: String, name: String, inherits: [String])? {
        var words = code.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        // Modifiers and attributes before the keyword.
        let modifiers: Set<String> = ["public", "internal", "private", "fileprivate", "open", "final", "package", "@MainActor", "@Suite", "nonisolated"]
        while let first = words.first, modifiers.contains(first) || first.hasPrefix("@Suite") { words.removeFirst() }
        guard let keyword = words.first, typeKeywords.contains(keyword), words.count > 1 else { return nil }
        let rest = words.dropFirst().joined(separator: " ")
        let name = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." })
        guard !name.isEmpty else { return nil }
        var inherits: [String] = []
        if let colon = rest.firstIndex(of: ":") {
            var tail = String(rest[rest.index(after: colon)...].prefix { $0 != "{" })
            if let w = tail.range(of: " where ") { tail = String(tail[..<w.lowerBound]) }
            inherits = tail.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces).prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) }
        }
        return (keyword, name.split(separator: ".").last.map(String.init) ?? name, inherits)
    }

    private static func functionName(_ code: String) -> String? {
        guard let r = code.range(of: "func ") else { return nil }
        // Only declarations: the text before `func` is modifiers and attributes.
        let before = code[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
        guard before.split(separator: " ").allSatisfy({ ["public", "internal", "private", "fileprivate", "open", "final", "static", "override", "@MainActor", "nonisolated", "@Test"].contains(String($0)) || $0.hasPrefix("@Test(") }) else { return nil }
        let name = code[r.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return name.isEmpty ? nil : String(name)
    }
}

/// Reads `xcresulttool get test-results tests` (Xcode 16 and later). The tree is Test Plan, then bundles, suites and
/// cases; a failure or skip is a child node of its case.
public enum XCResult {
    public enum ReadError: Error, CustomStringConvertible {
        case unavailable
        case failed(String)
        public var description: String {
            switch self {
            case .unavailable: "xcresulttool is only available on a Mac with Xcode."
            case .failed(let m): "xcresulttool failed: \(m)"
            }
        }
    }

    public static func parse(_ json: Data) throws -> [TestResult] {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any], let nodes = root["testNodes"] as? [[String: Any]] else {
            throw ReadError.failed("no test nodes in the result")
        }
        var out: [TestResult] = []
        for n in nodes { walk(n, bundle: "", suite: "", into: &out) }
        return out
    }

    private static func walk(_ node: [String: Any], bundle: String, suite: String, into out: inout [TestResult]) {
        let type = node["nodeType"] as? String ?? "", name = node["name"] as? String ?? ""
        let children = node["children"] as? [[String: Any]] ?? []
        switch type {
        case "Unit test bundle", "UI test bundle":
            for c in children { walk(c, bundle: name, suite: "", into: &out) }
        case "Test Suite":
            // Nested suites keep the innermost name, as Xcode's own report does.
            for c in children { walk(c, bundle: bundle, suite: name, into: &out) }
        case "Test Case":
            var message: String?, file: String?, line: Int?
            for c in children {
                let kind = c["nodeType"] as? String ?? ""
                guard kind == "Failure Message" || kind == "Skip Message" else { continue }
                let text = c["name"] as? String ?? ""
                message = message.map { $0 + "\n" + text } ?? text
                if file == nil, let loc = c["sourceLocation"] as? [String: Any] {
                    file = loc["filePath"] as? String; line = loc["lineNumber"] as? Int
                }
            }
            out.append(TestResult(bundle: bundle, suite: suite, name: name, status: TestStatus(xcresult: node["result"] as? String ?? ""),
                                  duration: node["durationInSeconds"] as? Double, message: message, file: file, line: line))
        default:
            // Test Plan, device and configuration nodes: look inside.
            for c in children { walk(c, bundle: bundle, suite: suite, into: &out) }
        }
    }

    /// Runs `xcresulttool` on a result bundle. macOS only.
    public static func read(path: String) throws -> [TestResult] {
        #if os(macOS)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["xcresulttool", "get", "test-results", "tests", "--path", path]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { throw ReadError.unavailable }
        // Both pipes are drained before waiting, so a large result cannot fill one and block the tool.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ReadError.failed(String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
        return try parse(data)
        #else
        throw ReadError.unavailable
        #endif
    }
}

/// Follows xcodebuild's or `swift test`'s output while a run goes, so the page can show progress before the result
/// bundle exists. Feed it lines as they arrive; it returns an event when a test starts or ends. XCTest only: Swift
/// Testing results arrive with the result bundle.
public struct TestLogFollower {
    public enum Event: Equatable, Sendable {
        case started(bundle: String, suite: String, name: String)
        case finished(TestResult)
    }

    /// Failure text collected for a test before its "failed" line arrives.
    private var failures: [String: (message: String, file: String, line: Int?)] = [:]

    public init() {}

    public mutating func feed(_ raw: String) -> Event? {
        let line = raw.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("Test Case '-["), let (key, rest) = Self.testCase(line) {
            let (bundle, suite, name) = Self.parts(key)
            if rest == "started." { return .started(bundle: bundle, suite: suite, name: name) }
            for (word, status) in [("passed", TestStatus.passed), ("failed", .failed), ("skipped", .skipped)] where rest.hasPrefix(word) {
                let seconds = rest.range(of: "(").flatMap { r in Double(rest[r.upperBound...].prefix { $0 != " " }) }
                let f = failures.removeValue(forKey: key)
                return .finished(TestResult(bundle: bundle, suite: suite, name: name, status: status, duration: seconds,
                                            message: f?.message, file: f?.file, line: f?.line))
            }
            return nil
        }
        // `/path/File.swift:6: error: -[Module.Class test] : message`
        if let r = line.range(of: ": error: -["), let end = line.range(of: "] : ", range: r.upperBound..<line.endIndex) {
            let key = "[" + line[r.upperBound..<end.lowerBound] + "]"
            var head = line[..<r.lowerBound].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let number = head.last.flatMap(Int.init)
            if number != nil { head.removeLast() }
            let message = String(line[end.upperBound...])
            let prior = failures[key]
            failures[key] = (prior.map { $0.message + "\n" + message } ?? message, prior?.file ?? head.joined(separator: ":"), prior?.line ?? number)
        }
        return nil
    }

    /// `Test Case '-[Module.Class method]' passed (0.003 seconds).` → ("[Module.Class method]", "passed (0.003 seconds).")
    private static func testCase(_ line: String) -> (String, String)? {
        guard let open = line.range(of: "'-["), let close = line.range(of: "]' ", range: open.upperBound..<line.endIndex) else { return nil }
        return ("[" + line[open.upperBound..<close.lowerBound] + "]", String(line[close.upperBound...]))
    }

    /// "[Module.Class method]" → bundle Module, suite Class, name method.
    private static func parts(_ key: String) -> (String, String, String) {
        let inner = key.dropFirst().dropLast()
        let pieces = inner.split(separator: " ", maxSplits: 1).map(String.init)
        let type = pieces.first ?? "", method = pieces.count > 1 ? pieces[1] : ""
        let dot = type.split(separator: ".").map(String.init)
        return (dot.count > 1 ? dot[0] : "", dot.last ?? type, method)
    }
}
