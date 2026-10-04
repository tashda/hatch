import Foundation

/// Which screens and source files a ticket is about, worked out by Hatch from the ticket's own words (decision IR9). Two
/// tickets are related when they name the same thing; nothing a model says about "the same screen" counts. Free: a text
/// search over the app's source, no model call.
///
/// Three kinds of evidence, strongest first:
/// - A label the ticket quotes ("Typed into views") found in the source. A label found in more than `maxFilesPerLabel`
///   files says nothing about one file, so it is ignored.
/// - A name that is a real Swift file or type in the app (`DecideView`, `ToolbarActions`).
/// - A screen the ticket names in plain words ("Decide", "Specs"): the app's own view files, with the suffix dropped
///   (`DecideView.swift` is the screen "decide"). The product's own names (`hatch`, `iris`) are not screens.
public struct SourceAnchors: Sendable {
    public struct File: Sendable { public var path: String; var lower: String; var declared: Set<String> }
    private let files: [File]
    /// Screen word (without a plural) to the file it comes from, and to the name as the file spells it.
    private let screens: [String: String]
    private let screenNames: [String: String]
    /// A quoted label that occurs in more files than this is too common to point at one of them.
    public static let maxFilesPerLabel = 3
    /// Shortest quoted text taken as a label.
    public static let minLabelLength = 6
    /// File name endings that make a file a screen or a part of one.
    static let screenSuffixes = ["View", "Page", "Sheet", "Panel", "Window", "Pane", "Parts", "Overlay"]
    /// The product's own names: they appear in nearly every ticket, so they say nothing about where a ticket is.
    static let notScreens: Set<String> = ["hatch", "iris", "agent", "agents", "ticket", "tickets", "project", "root"]

    public init(files: [(path: String, text: String)]) {
        var screens: [String: String] = [:], names: [String: String] = [:]
        self.files = files.map { f in
            var declared = Set<String>()
            let base = ((f.path as NSString).lastPathComponent as NSString).deletingPathExtension
            if base.count >= 5 { declared.insert(base) }
            for m in Self.declaration.matches(in: f.text, range: NSRange(f.text.startIndex..., in: f.text)) {
                if let r = Range(m.range(at: 1), in: f.text) { declared.insert(String(f.text[r])) }
            }
            for suffix in Self.screenSuffixes where base.hasSuffix(suffix) && base.count >= suffix.count + 4 {
                let name = Self.stem(String(base.dropLast(suffix.count)).lowercased())
                if !Self.notScreens.contains(name), screens[name] == nil { screens[name] = f.path; names[name] = String(base.dropLast(suffix.count)).lowercased() }
                break
            }
            return File(path: f.path, lower: f.text.lowercased(), declared: declared)
        }
        self.screens = screens
        self.screenNames = names
    }

    /// Indexes the Swift files of an app folder (not tests, not build output, not a separate package such as the Stage).
    public init(appRoot: String) {
        let root = URL(fileURLWithPath: appRoot).resolvingSymlinksInPath()
        var found: [(String, String)] = []
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in e {
                let name = url.lastPathComponent
                if ["build", ".build", "DerivedData", "Pods", "Tests", "Stage"].contains(name) || name.hasSuffix("Tests") { e.skipDescendants(); continue }
                guard url.pathExtension == "swift", let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let rel = url.path.hasPrefix(root.path + "/") ? String(url.path.dropFirst(root.path.count + 1)) : url.path
                found.append((rel, text))
            }
        }
        self.init(files: found)
    }

    public var isEmpty: Bool { files.isEmpty }

    private static let declaration = try! NSRegularExpression(pattern: #"\b(?:struct|class|enum|actor|protocol)\s+([A-Z][A-Za-z0-9_]{4,})"#)
    private static let identifier = try! NSRegularExpression(pattern: #"\b[A-Z][a-z0-9]+(?:[A-Z][A-Za-z0-9]*)+\b"#)
    private static let quoted = try! NSRegularExpression(pattern: "[\"\u{201C}]([^\"\u{201C}\u{201D}\n]{3,80})[\"\u{201D}]")

    static func stem(_ w: String) -> String { w.hasSuffix("s") && w.count > 4 ? String(w.dropLast()) : w }

    /// What the text points at: the files it quotes or names, and the screens it mentions. `weight` orders links by how
    /// much a shared anchor proves: a file counts twice a screen.
    struct Evidence { var files: [String: [String]] = [:]; var screens: [String: String] = [:] }

    func evidence(in text: String) -> Evidence {
        var out = Evidence()
        let whole = NSRange(text.startIndex..., in: text)
        for m in Self.quoted.matches(in: text, range: whole) {
            guard let r = Range(m.range(at: 1), in: text) else { continue }
            let label = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard label.count >= Self.minLabelLength else { continue }
            let hits = files.filter { $0.lower.contains(label) }
            guard !hits.isEmpty, hits.count <= Self.maxFilesPerLabel else { continue }
            for h in hits { out.files[h.path, default: []].append("\u{201C}\(label)\u{201D}") }
        }
        for m in Self.identifier.matches(in: text, range: whole) {
            guard let r = Range(m.range, in: text) else { continue }
            let name = String(text[r])
            for f in files where f.declared.contains(name) { out.files[f.path, default: []].append(name) }
        }
        let words = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map { Self.stem(String($0)) })
        for (name, path) in screens where words.contains(name) { out.screens[name] = path }
        return out
    }

    /// The files and screens the text points at, for tests and display.
    public func files(in text: String) -> Set<String> { Set(evidence(in: text).files.keys) }
    public func screens(in text: String) -> Set<String> { Set(evidence(in: text).screens.keys) }

    /// What two tickets both point at, as one line for the link, and how much it proves. Nil when they share nothing.
    public func shared(_ a: String, _ b: String) -> (weight: Int, why: String)? {
        let ea = evidence(in: a), eb = evidence(in: b)
        let sharedFiles = ea.files.keys.filter { eb.files[$0] != nil }.sorted()
        let sharedScreens = ea.screens.keys.filter { eb.screens[$0] != nil }.sorted()
        guard !sharedFiles.isEmpty || !sharedScreens.isEmpty else { return nil }
        var parts: [String] = []
        for f in sharedFiles.prefix(2) {
            let because = Array(Set((ea.files[f] ?? []) + (eb.files[f] ?? []))).sorted().prefix(2).joined(separator: ", ")
            parts.append("both point at \((f as NSString).lastPathComponent) (\(because))")
        }
        if !sharedScreens.isEmpty { parts.append("both name the \(sharedScreens.prefix(3).map { screenNames[$0] ?? $0 }.joined(separator: ", ")) screen") }
        return (2 * sharedFiles.count + sharedScreens.count, parts.joined(separator: "; "))
    }
}

/// Whether two texts say the same thing in nearly the same words: the one evidence of a repeat that needs no source search.
public enum TextLikeness {
    public static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 })
    }

    /// Shared words over all words, 0 to 1.
    public static func overlap(_ a: String, _ b: String) -> Double {
        let x = words(a), y = words(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return Double(x.intersection(y).count) / Double(x.union(y).count)
    }

    /// Close enough to be the same prompt said again.
    public static let repeatThreshold = 0.8
}
