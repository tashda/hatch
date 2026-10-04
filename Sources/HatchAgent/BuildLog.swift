import Foundation

/// The part of a build or test log an agent needs: errors and warnings with their file and line, failing tests and the
/// summary. A clean xcodebuild of Hatch prints about 358,000 characters (about 90k tokens) with 12 lines that matter;
/// an agent reading the raw log either pays for all of it on every later turn or, when Claude Code cuts long output,
/// loses the errors. The digest keeps what decides the next step and drops the rest.
public enum BuildLog {
    public struct Digest: Equatable, Sendable {
        public var text: String
        public var errors: Int
        public var warnings: Int
    }

    static let maxErrors = 40, maxWarnings = 15, maxTests = 30, maxChars = 8000

    /// `ok` is whether the command exited with status 0. `root` is stripped from paths to keep lines short.
    public static func digest(_ log: String, ok: Bool, root: String? = nil) -> Digest {
        var errors: [String] = [], warnings: [String] = [], failedTests: [String] = [], summary: [String] = []
        var seen = Set<String>()
        let prefix = root.map { $0.hasSuffix("/") ? $0 : $0 + "/" }

        func short(_ path: String) -> String {
            var p = path
            if let prefix, p.hasPrefix(prefix) { p.removeFirst(prefix.count) }
            return p
        }
        func add(_ line: String, to list: inout [String]) {
            guard seen.insert(line).inserted else { return }
            list.append(line)
        }

        // XCTest prints "Executed …" after every suite; the one after "Test Suite 'All tests'" is a bundle's total.
        var bundleTotals: [(tests: Int, failures: Int)] = [], previous = ""
        for raw in log.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = stripEscapes(String(raw)).trimmingCharacters(in: .whitespaces)
            defer { previous = line }
            if line.hasPrefix("Executed "), previous.hasPrefix("Test Suite 'All tests'"), let counts = executed(line) {
                bundleTotals.append(counts)
            }
            // Compiler command lines and the "failed with a nonzero exit code" wrapper repeat what the diagnostic says.
            if line.count > 1000 || line.contains("failed with a nonzero exit code") { continue }
            if let d = diagnostic(line) {
                let entry = "\(d.kind) \(short(d.file)):\(d.position) \(d.message)"
                if d.kind == "warning" { add(entry, to: &warnings) } else { add(entry, to: &errors) }
                continue
            }
            if let name = failedTest(line) { add("failed: \(name)", to: &failedTests); continue }
            if line.contains("recorded an issue at") { add(short(line), to: &failedTests); continue }
            if isSummary(line) {
                // A bundle without Swift Testing tests still prints its empty run; it says nothing.
                if line.contains("Test run with 0 tests") { continue }
                summary.removeAll { sameKind($0, line) }; summary.append(line); continue
            }
            // Other toolchains (npm, cargo, make, pytest): short lines that start with an error word.
            if line.count < 300, startsWithError(line) { add(line, to: &errors) }
        }

        var out: [String] = []
        let status = ok ? "passed" : "FAILED"
        out.append("\(status): \(errors.count) error\(errors.count == 1 ? "" : "s"), \(warnings.count) warning\(warnings.count == 1 ? "" : "s")")
        out += capped(errors, maxErrors, "errors")
        out += capped(failedTests, maxTests, "failing tests")
        out += capped(warnings, maxWarnings, "warnings")
        if bundleTotals.count > 1 {
            // Several test bundles: one total instead of the last bundle's line.
            summary.removeAll { $0.hasPrefix("Executed ") }
            let tests = bundleTotals.map(\.tests).reduce(0, +), failures = bundleTotals.map(\.failures).reduce(0, +)
            summary.append("Executed \(tests) tests in \(bundleTotals.count) bundles, with \(failures) failure\(failures == 1 ? "" : "s")")
        }
        out += summary
        if !ok && errors.isEmpty && failedTests.isEmpty {
            // Nothing recognisable: the end of the log is the best guess, and nothing is silently lost.
            out.append("(no error lines recognised; the last lines of the log:)")
            out += log.split(whereSeparator: \.isNewline).suffix(30).map { String(stripEscapes(String($0)).prefix(300)) }
        }
        var text = out.joined(separator: "\n")
        if text.count > maxChars { text = String(text.prefix(maxChars)) + "\n… (cut at \(maxChars) characters)" }
        return Digest(text: text, errors: errors.count, warnings: warnings.count)
    }

    private static func capped(_ list: [String], _ max: Int, _ what: String) -> [String] {
        list.count > max ? Array(list.prefix(max)) + ["… and \(list.count - max) more \(what)"] : list
    }

    /// `path:line[:col]: error|warning|fatal error: message`
    static func diagnostic(_ line: String) -> (file: String, position: String, kind: String, message: String)? {
        for kind in ["fatal error", "error", "warning"] {
            guard let r = line.range(of: ": \(kind): ") else { continue }
            var parts = line[..<r.lowerBound].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            // The file, then a line number and maybe a column.
            var numbers: [String] = []
            while numbers.count < 2, let last = parts.last, Int(last) != nil { numbers.insert(last, at: 0); parts.removeLast() }
            let file = parts.joined(separator: ":")
            guard !numbers.isEmpty, !file.isEmpty, file.contains("/") || file.contains(".") || !file.contains(" ") else { continue }
            let position = numbers.joined(separator: ":")
            var message = String(line[r.upperBound...])
            // Swift appends a documentation link in brackets; it says nothing new.
            if let link = message.range(of: " [#", options: .backwards) { message = String(message[..<link.lowerBound]) }
            return (file, position, kind == "fatal error" ? "error" : kind, message.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// XCTest's `Test Case '-[Module.Class testName]' failed (…)`.
    static func failedTest(_ line: String) -> String? {
        guard line.hasPrefix("Test Case '"), line.contains("' failed") else { return nil }
        let start = line.index(line.startIndex, offsetBy: "Test Case '".count)
        guard let end = line.range(of: "' failed")?.lowerBound, start < end else { return nil }
        return String(line[start..<end])
    }

    static func isSummary(_ line: String) -> Bool {
        line.hasPrefix("** ") && line.hasSuffix(" **")                               // xcodebuild
            || line.hasPrefix("Executed ") && line.contains(" test")                  // XCTest
            || line.contains("Test run with ") && (line.contains("passed") || line.contains("failed"))  // Swift Testing
            || line.hasPrefix("Build complete!") || line == "error: Build failed"     // SwiftPM
    }

    /// "Executed 46 tests, with 1 failure (0 unexpected) in …" as numbers.
    static func executed(_ line: String) -> (tests: Int, failures: Int)? {
        // Also "Executed 56 tests, with 16 tests skipped and 0 failures (0 unexpected)": the number before "failure".
        let words = line.split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) }
        guard words.count >= 5, let tests = Int(words[1]),
              let i = words.firstIndex(where: { $0 == "failure" || $0 == "failures" }), i > 0, let failures = Int(words[i - 1]) else { return nil }
        return (tests, failures)
    }

    /// Keeps only the last line of each summary kind (XCTest prints "Executed" once per suite).
    private static func sameKind(_ a: String, _ b: String) -> Bool {
        (a.hasPrefix("Executed ") && b.hasPrefix("Executed ")) || (a.contains("Test run with ") && b.contains("Test run with "))
    }

    static func startsWithError(_ line: String) -> Bool {
        let l = line.lowercased()
        if l == "error: build failed" || l == "error: fatalerror" { return false }
        return ["error:", "error[", "fatal:", "fail ", "failed:", "npm err!", "✕ ", "× "].contains { l.hasPrefix($0) }
    }

    /// Removes terminal colour codes and hyperlinks.
    static func stripEscapes(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        var out = "", i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            guard c == "\u{1B}" else { out.append(c); i = s.index(after: i); continue }
            let next = s.index(after: i)
            guard next < s.endIndex else { break }
            if s[next] == "[" {
                // CSI: up to a letter.
                var j = s.index(after: next)
                while j < s.endIndex, !(s[j].isLetter) { j = s.index(after: j) }
                i = j < s.endIndex ? s.index(after: j) : j
            } else if s[next] == "]" {
                // OSC: up to BEL or ESC \.
                var j = s.index(after: next)
                while j < s.endIndex, s[j] != "\u{07}", s[j] != "\u{1B}" { j = s.index(after: j) }
                if j < s.endIndex, s[j] == "\u{1B}" { j = s.index(after: j) }
                i = j < s.endIndex ? s.index(after: j) : j
            } else {
                i = s.index(after: next)
            }
        }
        return out
    }
}
