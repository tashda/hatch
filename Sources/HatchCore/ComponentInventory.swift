import Foundation

// The inventory (decision DS4, workflow B step 1): every button, menu, picker, toggle and text field in an app, with the
// place it sits in and its look as recipe settings, grouped so setup can recommend the most-used look per place. It
// reads Swift text with a small structural pass (strings and comments masked, brackets matched, enclosing blocks and
// modifier chains followed), so it is free and runs in well under a second. It is a heuristic: a style set on a parent
// view in another file is not seen, and a use whose place cannot be told is listed as unknown, which shows what to add.

public struct ComponentInventory: Equatable, Sendable {
    /// One control found in the app.
    public struct Use: Equatable, Sendable {
        /// An element id from `ComponentElement.catalog`.
        public var element: String
        /// A place id, or nil when the place cannot be told.
        public var place: String?
        /// The look as recipe settings, in the same words a role uses, so a use can be compared with a role.
        public var recipe: [String: String]
        public var importance: ComponentRole.Importance
        /// The role it already uses (`.buttonRole(.primary)` gives `button.primary`), if any.
        public var role: String?
        public var file: String
        public var line: Int
        /// The view type it is written in.
        public var view: String?
        /// What was around it, innermost first (`HStack`, `.toolbar`, `helper footer`, `view SettingsPage`): why it got
        /// its place, or why none.
        public var trail: [String] = []

        public var signature: String { ComponentRole.summary(recipe) }
        public var location: String { "\((file as NSString).lastPathComponent):\(line)" }
    }

    /// Uses of one element in one place with the same look.
    public struct Cluster: Equatable, Sendable {
        public var element: String
        public var place: String?
        public var recipe: [String: String]
        /// The importance most of its uses have.
        public var importance: ComponentRole.Importance
        public var count: Int
        public var examples: [String]
        public var signature: String { ComponentRole.summary(recipe) }
    }

    public var uses: [Use]
    public var swiftFiles: Int

    public init(uses: [Use], swiftFiles: Int) { self.uses = uses; self.swiftFiles = swiftFiles }

    public var elements: [String] {
        let found = Set(uses.map(\.element))
        return ComponentElement.catalog.map(\.id).filter(found.contains)
    }

    /// Places of one element in standard order, unknown (nil) last, with their counts.
    public func places(of element: String) -> [(place: String?, count: Int)] {
        let mine = uses.filter { $0.element == element }
        let order = (ComponentPlace.standard + ComponentPlace.common).map(\.id)
        let ids = Set(mine.compactMap(\.place)).sorted { (order.firstIndex(of: $0) ?? .max, $0) < (order.firstIndex(of: $1) ?? .max, $1) }
        var out = ids.map { id in (place: Optional(id), count: mine.filter { $0.place == id }.count) }
        let unknown = mine.filter { $0.place == nil }.count
        if unknown > 0 { out.append((nil, unknown)) }
        return out
    }

    /// The looks of one element in one place, most used first. The first is what setup recommends (DS4).
    public func clusters(element: String, place: String?) -> [Cluster] {
        var groups: [String: [Use]] = [:], order: [String] = []
        for u in uses where u.element == element && u.place == place {
            if groups[u.signature] == nil { order.append(u.signature) }
            groups[u.signature, default: []].append(u)
        }
        return order.map { sig in
            let list = groups[sig]!
            var tally: [ComponentRole.Importance: Int] = [:]
            for u in list { tally[u.importance, default: 0] += 1 }
            let importance = ComponentRole.Importance.allCases.max { (tally[$0] ?? 0, -$0.rank) < (tally[$1] ?? 0, -$1.rank) } ?? .other
            return Cluster(element: element, place: place, recipe: list[0].recipe, importance: importance, count: list.count,
                           examples: Self.firstDistinct(list.map(\.location), 3))
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.signature < $1.signature }
    }

    static func firstDistinct(_ items: [String], _ n: Int) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for x in items where out.count < n && seen.insert(x).inserted { out.append(x) }
        return out
    }

    /// How many uses already go through a role (DS step 6 of setup shows it as coverage).
    public var coverage: (withRole: Int, total: Int) { (uses.filter { $0.role != nil }.count, uses.count) }

    /// Files that hold the most uses whose place is unknown: where a new place, or a better rule, would help most.
    public func unknownFiles(element: String? = nil, limit: Int = 6) -> [(file: String, count: Int)] {
        var counts: [String: Int] = [:]
        for u in uses where u.place == nil && (element == nil || u.element == element) { counts[u.file, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map { ($0.key, $0.value) }
    }
}

extension ComponentRole.Importance {
    /// Ties go to the stronger reading.
    var rank: Int { switch self { case .destructive: 0; case .main: 1; case .quiet: 2; case .other: 3 } }
}

// MARK: - Scanning

public enum ComponentInventoryScanner {
    /// Every Swift file under `appRoot`, minus tests, build output and the `excluding` folders (the components
    /// themselves: their insides are definitions, not uses).
    public static func scan(appRoot: String, excluding: [String] = []) -> ComponentInventory {
        let root = URL(fileURLWithPath: (appRoot as NSString).expandingTildeInPath).resolvingSymlinksInPath()
        let skip = excluding.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var texts: [(String, String)] = []
        for url in ComponentsScanner.swiftFiles(under: root) {
            let rel = ComponentsScanner.relative(url, to: root)
            if skip.contains(where: { rel.hasPrefix($0) }) { continue }
            if rel.split(separator: "/").contains(where: { $0.hasSuffix("Tests") || $0 == "Package.swift" }) { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            texts.append((rel, text))
        }
        return inventory(files: texts)
    }

    /// The inventory of a set of files read together, so a view's place can come from where other files use it.
    public static func inventory(files: [(path: String, text: String)]) -> ComponentInventory {
        let corpus = SwiftCorpus(files: files)
        var uses: [ComponentInventory.Use] = []
        for i in corpus.files.indices where corpus.files[i].hasControls {
            uses += corpus.files[i].structure.controls(file: corpus.files[i].path, scope: corpus.files[i].scope, corpus: corpus)
        }
        return ComponentInventory(uses: uses, swiftFiles: files.count)
    }

    /// The controls in one file, read on its own.
    public static func uses(in text: String, file: String) -> [ComponentInventory.Use] {
        inventory(files: [(file, text)]).uses
    }
}

/// All files of an app, read once. It knows where each of the app's own views is used, so a control inside a small
/// reusable view (`KeybindItemView`) gets the place, and the styles, of the places that use it.
final class SwiftCorpus {
    struct File {
        var path: String
        var structure: SwiftStructure
        var scope: SwiftStructure.Scope
        var hasControls: Bool
    }

    var files: [File] = []
    /// A view's name → where it is used: file index and position.
    var viewUses: [String: [(file: Int, at: Int, modifiers: [SwiftStructure.Modifier])]] = [:]
    private var memo: [String: SwiftStructure.Context] = [:]
    private var resolving: Set<String> = []

    init(files texts: [(path: String, text: String)]) {
        for (path, text) in texts {
            let s = SwiftStructure(text)
            let hasControls = ["Button", "Menu", "Picker", "Toggle", "TextField", "searchable"].contains(where: text.contains)
            files.append(File(path: path, structure: s, scope: SwiftStructure.Scope(views: s.structs(), members: s.members(), types: s.typeBodies()),
                              hasControls: hasControls))
        }
        let names = Set(files.flatMap { $0.scope.views.map(\.name) })
        for (index, f) in files.enumerated() {
            for site in f.structure.typeUses(names) { viewUses[site.name, default: []].append((index, site.at, site.modifiers)) }
        }
    }

    /// Where a view is used, as one context: the place most of its uses agree on (the first use breaks a tie), with the
    /// styles of a use in that place. Nil when nothing uses it or it is already being resolved (a view inside itself).
    func context(ofView name: String, depth: Int) -> SwiftStructure.Context? {
        if let known = memo[name] { return known }
        guard depth < 8, !resolving.contains(name) else { return nil }
        // Used nowhere as a view: shown by a window, a scene or AppKit (`NSHostingView(rootView:)`), so its content is a page.
        guard let sites = viewUses[name], !sites.isEmpty else {
            let root = SwiftStructure.Context(place: "page", view: name, chains: [], preview: false, trail: ["root view"])
            memo[name] = root
            return root
        }
        resolving.insert(name)
        defer { resolving.remove(name) }
        var found: [(place: String?, ctx: SwiftStructure.Context, modifiers: [SwiftStructure.Modifier])] = []
        for site in sites.prefix(12) {
            let f = files[site.file]
            if f.structure.isRootArgument(at: site.at) {
                found.append(("page", SwiftStructure.Context(place: "page", view: name, chains: [], preview: false, trail: ["hosted as rootView"]), site.modifiers))
                continue
            }
            let ctx = f.structure.context(of: site.at, scope: f.scope, depth: depth + 1, names: true, corpus: self)
            if ctx.preview { continue }
            found.append((ctx.place, ctx, site.modifiers))
        }
        guard let first = found.first else { return nil }
        var tally: [String: Int] = [:]
        for f in found { if let p = f.place { tally[p, default: 0] += 1 } }
        // Most uses win; on a tie, the place that appears first.
        let order = found.compactMap(\.place)
        let best = tally.keys.max { a, b in tally[a]! != tally[b]! ? tally[a]! < tally[b]! : order.firstIndex(of: a)! > order.firstIndex(of: b)! }
        let chosen = found.first { $0.place == best } ?? first
        var out = chosen.ctx
        out.place = best
        out.chains = [chosen.modifiers] + chosen.ctx.chains
        out.trail = ["used in \(found.count) place\(found.count == 1 ? "" : "s")"] + chosen.ctx.trail.prefix(4)
        memo[name] = out
        return out
    }
}

/// Swift text with strings and comments masked and brackets matched: enough structure to follow a view's nesting and
/// modifier chains without a parser.
struct SwiftStructure {
    let b: [UInt8]
    /// For each bracket, the index of its partner; -1 elsewhere.
    var partner: [Int]
    let lineStarts: [Int]
    /// Every `{` that has a partner, in order.
    var braceOpens: [Int] = []

    init(_ text: String) {
        var bytes = Array(text.utf8)
        Self.mask(&bytes)
        b = bytes
        partner = Array(repeating: -1, count: bytes.count)
        var stack: [Int] = []
        for i in bytes.indices {
            switch bytes[i] {
            case UInt8(ascii: "("), UInt8(ascii: "{"), UInt8(ascii: "["): stack.append(i)
            case UInt8(ascii: ")"), UInt8(ascii: "}"), UInt8(ascii: "]"):
                if let open = stack.popLast() {
                    partner[open] = i; partner[i] = open
                    if bytes[open] == UInt8(ascii: "{") { braceOpens.append(open) }
                }
            default: break
            }
        }
        braceOpens.sort()
        var starts = [0]
        for i in bytes.indices where bytes[i] == UInt8(ascii: "\n") { starts.append(i + 1) }
        lineStarts = starts
    }

    // MARK: Masking

    /// Blanks comments and the insides of string literals (quotes and newlines stay), so brackets and names inside them
    /// are never read as code.
    static func mask(_ b: inout [UInt8]) {
        var i = 0
        while i < b.count {
            if b[i] == UInt8(ascii: "/"), i + 1 < b.count, b[i + 1] == UInt8(ascii: "/") {
                while i < b.count, b[i] != UInt8(ascii: "\n") { b[i] = 32; i += 1 }
            } else if b[i] == UInt8(ascii: "/"), i + 1 < b.count, b[i + 1] == UInt8(ascii: "*") {
                i = blockComment(&b, i)
            } else if b[i] == UInt8(ascii: "\"") || (b[i] == UInt8(ascii: "#") && rawStringStart(b, i) != nil) {
                let span = stringSpan(b, i)
                var k = span.from
                while k < span.to { if b[k] != 10 { b[k] = 32 }; k += 1 }
                i = max(span.end, i + 1)
            } else { i += 1 }
        }
    }

    /// Masks a nested block comment starting at `i`; returns the index after it.
    static func blockComment(_ b: inout [UInt8], _ start: Int) -> Int {
        var depth = 0, i = start
        while i < b.count {
            if b[i] == UInt8(ascii: "/"), i + 1 < b.count, b[i + 1] == UInt8(ascii: "*") { depth += 1; b[i] = 32; b[i + 1] = 32; i += 2; continue }
            if b[i] == UInt8(ascii: "*"), i + 1 < b.count, b[i + 1] == UInt8(ascii: "/") {
                depth -= 1; b[i] = 32; b[i + 1] = 32; i += 2
                if depth == 0 { return i }
                continue
            }
            if b[i] != UInt8(ascii: "\n") { b[i] = 32 }
            i += 1
        }
        return i
    }

    /// The number of `#` before a raw string's quote, when `i` starts one.
    static func rawStringStart(_ b: [UInt8], _ i: Int) -> Int? {
        var j = i, n = 0
        while j < b.count, b[j] == UInt8(ascii: "#") { n += 1; j += 1 }
        return j < b.count && b[j] == UInt8(ascii: "\"") ? n : nil
    }

    /// A string literal starting at `start` (with or without `#`s, one line or three quotes): where its content starts and
    /// stops, and the index after it. An unterminated one-line string stops at the end of the line.
    static func stringSpan(_ b: [UInt8], _ start: Int) -> (from: Int, to: Int, end: Int) {
        let quote = UInt8(ascii: "\""), hashes = rawStringStart(b, start) ?? 0
        let first = start + hashes
        let multiline = first + 2 < b.count && b[first + 1] == quote && b[first + 2] == quote
        if !multiline, first + 1 < b.count, b[first + 1] == quote { return (first + 1, first + 1, min(b.count, first + 2 + hashes)) }
        let q = multiline ? 3 : 1
        func closesHere(_ j: Int) -> Bool {
            guard j + q + hashes <= b.count else { return false }
            for k in 0..<q where b[j + k] != quote { return false }
            for k in 0..<hashes where b[j + q + k] != UInt8(ascii: "#") { return false }
            return true
        }
        let from = first + q
        var i = from
        while i < b.count {
            if !multiline && b[i] == 10 { return (from, i, i) }
            if b[i] == UInt8(ascii: "\\") {
                var j = i + 1, n = 0
                while j < b.count, b[j] == UInt8(ascii: "#"), n < hashes { j += 1; n += 1 }
                guard n == hashes else { i += 1; continue }  // a plain backslash inside a raw string
                if j < b.count, b[j] == UInt8(ascii: "(") { i = interpolationEnd(b, j); continue }
                i = j + 1
                continue
            }
            if closesHere(i) { return (from, i, i + q + hashes) }
            i += 1
        }
        return (from, b.count, b.count)
    }

    /// Skips the code of `\( … )`, which may hold its own strings.
    static func interpolationEnd(_ b: [UInt8], _ open: Int) -> Int {
        var depth = 0, i = open
        while i < b.count {
            switch b[i] {
            case UInt8(ascii: "("): depth += 1
            case UInt8(ascii: ")"): depth -= 1; if depth == 0 { return i + 1 }
            case UInt8(ascii: "\""), UInt8(ascii: "#"):
                if b[i] == UInt8(ascii: "#") && rawStringStart(b, i) == nil { break }
                i = max(stringSpan(b, i).end, i + 1); continue
            default: break
            }
            i += 1
        }
        return i
    }

    // MARK: Reading

    static func isIdentStart(_ c: UInt8) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c >= 0x80 }
    static func isIdent(_ c: UInt8) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) }
    static func isSpace(_ c: UInt8) -> Bool { c == 32 || c == 9 || c == 13 }

    func text(_ from: Int, _ to: Int) -> String { from < to ? String(decoding: b[from..<to], as: UTF8.self) : "" }

    func line(of i: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi { let mid = (lo + hi + 1) / 2; if lineStarts[mid] <= i { lo = mid } else { hi = mid - 1 } }
        return lo + 1
    }

    func skipSpace(_ i: Int, newlines: Bool) -> Int {
        var j = i
        while j < b.count, Self.isSpace(b[j]) || (newlines && b[j] == 10) { j += 1 }
        return j
    }

    func skipSpaceBack(_ i: Int) -> Int {
        var j = i
        while j >= 0, Self.isSpace(b[j]) || b[j] == 10 { j -= 1 }
        return j
    }

    /// The identifier that ends at `end` (inclusive), and where it starts.
    func identifier(endingAt end: Int) -> (name: String, start: Int)? {
        guard end >= 0, end < b.count, Self.isIdent(b[end]) else { return nil }
        var s = end
        while s > 0, Self.isIdent(b[s - 1]) { s -= 1 }
        return (text(s, end + 1), s)
    }

    func identifier(startingAt start: Int) -> (name: String, end: Int)? {
        guard start < b.count, Self.isIdentStart(b[start]) else { return nil }
        var e = start
        while e < b.count, Self.isIdent(b[e]) { e += 1 }
        return (text(start, e), e)
    }

    struct Modifier { var name: String; var args: String }

    /// Labeled trailing closures and `.modifier(…) { … }` calls after `i`, in order, and where they end.
    func chain(after i: Int) -> (modifiers: [Modifier], closures: [(label: String, open: Int)], end: Int) {
        var j = i, mods: [Modifier] = [], closures: [(String, Int)] = []
        while true {
            let k = skipSpace(j, newlines: true)
            guard k < b.count else { break }
            if Self.isIdentStart(b[k]), let id = identifier(startingAt: k) {
                let colon = skipSpace(id.end, newlines: false)
                if colon < b.count, b[colon] == UInt8(ascii: ":") {
                    let brace = skipSpace(colon + 1, newlines: true)
                    if brace < b.count, b[brace] == UInt8(ascii: "{"), partner[brace] > brace {
                        closures.append((id.name, brace)); j = partner[brace] + 1; continue
                    }
                }
                break
            }
            if b[k] == UInt8(ascii: "."), k + 1 < b.count, let id = identifier(startingAt: k + 1) {
                var p = id.end, args = ""
                let paren = skipSpace(p, newlines: false)
                if paren < b.count, b[paren] == UInt8(ascii: "("), partner[paren] > paren {
                    args = text(paren + 1, partner[paren]); p = partner[paren] + 1
                }
                let brace = skipSpace(p, newlines: false)
                if brace < b.count, b[brace] == UInt8(ascii: "{"), partner[brace] > brace { p = partner[brace] + 1 }
                mods.append(Modifier(name: id.name, args: args)); j = p; continue
            }
            break
        }
        return (mods, closures, j)
    }

    /// What a `{` belongs to: the call before it (`HStack`, `.toolbar`, `ToolbarItem(placement: …)`), and the closure's
    /// label when it is a labeled trailing closure (`label:`, `actions:`).
    func owner(ofBrace brace: Int) -> (name: String, args: String, label: String?, dotted: Bool, hash: Bool)? {
        var j = skipSpaceBack(brace - 1)
        guard j >= 0 else { return nil }
        var label: String?
        if b[j] == UInt8(ascii: ":") {
            guard let id = identifier(endingAt: skipSpaceBack(j - 1)) else { return nil }
            label = id.name
            j = skipSpaceBack(id.start - 1)
            guard j >= 0 else { return nil }
            if b[j] == UInt8(ascii: "}"), partner[j] >= 0, var found = owner(ofBrace: partner[j]) { found.label = label; return found }
            if b[j] == UInt8(ascii: "(") { return nil }  // an argument closure: `Button(action: { … })`
        }
        var args = ""
        if b[j] == UInt8(ascii: ")"), partner[j] >= 0 {
            args = text(partner[j] + 1, j)
            j = skipSpaceBack(partner[j] - 1)
        }
        guard let id = identifier(endingAt: j) else { return nil }
        let before = id.start - 1
        return (id.name, args, label, before >= 0 && b[before] == UInt8(ascii: "."), before >= 0 && b[before] == UInt8(ascii: "#"))
    }

    /// Ranges of `struct Name … { … }` and `extension Name … { … }` bodies, for the view a control is written in.
    func structs() -> [(name: String, open: Int, close: Int)] {
        var out: [(String, Int, Int)] = []
        var i = 0
        // `extension Name` too: large apps split a view across `Name+Part.swift` files.
        for word in [Array("struct".utf8), Array("extension".utf8)] {
            var i = 0
            while i + word.count < b.count {
                if b[i] == word[0], Array(b[i..<(i + word.count)]) == word, (i == 0 || !Self.isIdent(b[i - 1])), Self.isSpace(b[i + word.count]),
                   let id = identifier(startingAt: skipSpace(i + word.count, newlines: false)) {
                    var k = id.end
                    while k < b.count, b[k] != UInt8(ascii: "{"), b[k] != UInt8(ascii: "}") { k += 1 }
                    if k < b.count, b[k] == UInt8(ascii: "{"), partner[k] > k, id.name != "View" { out.append((id.name, k, partner[k])) }
                    i = id.end; continue
                }
                i += 1
            }
        }
        return out
    }

    /// Bodies of `class`, `enum`, `actor` and `protocol` declarations.
    func typeBodies() -> [Int] {
        var out: [Int] = []
        for keyword in ["class", "enum", "actor", "protocol"] {
            let word = Array(keyword.utf8)
            var i = 0
            while i + word.count < b.count {
                defer { i += 1 }
                guard b[i] == word[0], Array(b[i..<(i + word.count)]) == word, i == 0 || !Self.isIdent(b[i - 1]), Self.isSpace(b[i + word.count]),
                      identifier(startingAt: skipSpace(i + word.count, newlines: false)) != nil else { continue }
                // To the body's `{`; `=` or `}` first means no body (`enum` in a `case`, a stored `class var`).
                var k = i + word.count
                while k < b.count, b[k] != UInt8(ascii: "{"), b[k] != UInt8(ascii: "}"), b[k] != UInt8(ascii: "=") { k += 1 }
                if k < b.count, b[k] == UInt8(ascii: "{") { out.append(k) }
            }
        }
        return out
    }

    /// `NSHostingView(rootView: Name())`, `NSHostingController(rootView: …)`: a view AppKit shows as a window's content.
    func isRootArgument(at i: Int) -> Bool {
        let colon = skipSpaceBack(i - 1)
        guard colon >= 0, b[colon] == UInt8(ascii: ":"), let label = identifier(endingAt: skipSpaceBack(colon - 1)) else { return false }
        return label.name == "rootView" || label.name == "content"
    }

    /// Where any of `names` is used as a view: `Name(…)` or `Name { … }`, not declared, not a member (`.Name`).
    func typeUses(_ names: Set<String>) -> [(name: String, at: Int, modifiers: [Modifier])] {
        var out: [(String, Int, [Modifier])] = []
        var i = 0
        while i < b.count {
            guard Self.isIdentStart(b[i]), i == 0 || !Self.isIdent(b[i - 1]), let id = identifier(startingAt: i) else { i += 1; continue }
            defer { i = id.end }
            guard b[i] >= 65 && b[i] <= 90, names.contains(id.name) else { continue }
            if i > 0, b[i - 1] == UInt8(ascii: ".") { continue }
            if let before = identifier(endingAt: skipSpaceBack(i - 1)), ["struct", "extension", "class", "enum", "typealias"].contains(before.name) { continue }
            var p = skipSpace(id.end, newlines: false)
            guard p < b.count, b[p] == UInt8(ascii: "(") || b[p] == UInt8(ascii: "{") else { continue }
            if b[p] == UInt8(ascii: "("), partner[p] > p { p = partner[p] + 1 }
            let brace = skipSpace(p, newlines: false)
            if brace < b.count, b[brace] == UInt8(ascii: "{"), partner[brace] > brace { p = partner[brace] + 1 }
            out.append((id.name, i, chain(after: p).modifiers))
        }
        return out
    }

    /// Bodies of `func name(…) … {` and `var name: … {`: helpers whose place is decided where they are called.
    func members() -> [(name: String, open: Int, close: Int)] {
        var out: [(String, Int, Int)] = []
        for keyword in ["func", "var"] {
            let word = Array(keyword.utf8)
            var i = 0
            while i + word.count < b.count {
                defer { i += 1 }
                guard b[i] == word[0], Array(b[i..<(i + word.count)]) == word, i == 0 || !Self.isIdent(b[i - 1]),
                      Self.isSpace(b[i + word.count]), let id = identifier(startingAt: skipSpace(i + word.count, newlines: false)) else { continue }
                // To the body's `{`, over balanced brackets; a stored property ends at `=` or the end of the line.
                var k = id.end
                while k < b.count {
                    let c = b[k]
                    if c == UInt8(ascii: "("), partner[k] > k { k = partner[k] + 1; continue }
                    if c == UInt8(ascii: "{") || c == UInt8(ascii: "}") || c == UInt8(ascii: "=") { break }
                    if keyword == "var", c == 10 { break }
                    k += 1
                }
                if k < b.count, b[k] == UInt8(ascii: "{"), partner[k] > k { out.append((id.name, k, partner[k])) }
            }
        }
        return out
    }

    /// The `{` blocks around `i`, outermost first.
    func enclosingBraces(of i: Int) -> [Int] {
        braceOpens.filter { $0 < i && partner[$0] > i }
    }

    // MARK: Controls

    static let elementNames: [String: String] = [
        "Button": "button", "Menu": "menu", "Picker": "picker", "Toggle": "toggle",
        "TextField": "field", "SecureField": "field",
    ]

    /// The views and helpers of a file, read once.
    struct Scope {
        var views: [(name: String, open: Int, close: Int)]
        var members: [(name: String, open: Int, close: Int)]
        /// Bodies of declarations (types, functions, properties): never a container that names a place.
        var declarations: Set<Int>

        init(views: [(name: String, open: Int, close: Int)], members: [(name: String, open: Int, close: Int)], types: [Int] = []) {
            self.views = views; self.members = members
            declarations = Set(views.map(\.open) + members.map(\.open) + types)
        }
    }

    func controls(file: String, scope: Scope, corpus: SwiftCorpus?) -> [ComponentInventory.Use] {
        var out: [ComponentInventory.Use] = []
        var i = 0
        while i < b.count {
            let c = b[i]
            guard Self.isIdentStart(c), i == 0 || !Self.isIdent(b[i - 1]) else { i += 1; continue }
            guard let id = identifier(startingAt: i) else { i += 1; continue }
            defer { i = id.end }
            let prev = i > 0 ? b[i - 1] : 0
            if id.name == "searchable", prev == UInt8(ascii: ".") {
                if let use = searchField(at: i, scope: scope, corpus: corpus, file: file) { out.append(use) }
                continue
            }
            guard let element = Self.elementNames[id.name], prev != UInt8(ascii: "."), prev != UInt8(ascii: "#") else { continue }
            let next = skipSpace(id.end, newlines: false)
            guard next < b.count, b[next] == UInt8(ascii: "(") || b[next] == UInt8(ascii: "{") else { continue }
            if let use = control(element, nameEnd: id.end, start: i, scope: scope, corpus: corpus, file: file) { out.append(use) }
        }
        return out
    }

    /// One control: its own call, trailing closures and modifiers, then what the enclosing blocks add.
    func control(_ element: String, nameEnd: Int, start: Int, scope: Scope, corpus: SwiftCorpus?, file: String) -> ComponentInventory.Use? {
        var p = skipSpace(nameEnd, newlines: false), args = ""
        var closures: [(label: String, open: Int)] = []
        if p < b.count, b[p] == UInt8(ascii: "("), partner[p] > p { args = text(p + 1, partner[p]); p = partner[p] + 1 }
        let trailing = skipSpace(p, newlines: false)
        if trailing < b.count, b[trailing] == UInt8(ascii: "{"), partner[trailing] > trailing {
            closures.append(("", trailing)); p = partner[trailing] + 1
        }
        let own = chain(after: p)
        closures += own.closures

        var context = self.context(of: start, scope: scope, corpus: corpus)
        guard !context.preview, !Self.hidden([own.modifiers] + context.chains) else { return nil }
        // A field or switch beside the footer buttons is still part of the sheet's form.
        if context.place == "sheetFooter", element != "button", element != "menu" { context.place = "form" }

        var env = StyleEnvironment()
        env.read(own.modifiers, own: true)
        for level in context.chains { env.read(level, own: false) }

        var recipe: [String: String] = [:]
        var importance = ComponentRole.Importance.other
        switch element {
        case "button":
            recipe["style"] = env.buttonStyle ?? "automatic"
            if let s = env.size { recipe["size"] = s }
            recipe["label"] = env.labelStyle ?? buttonLabel(args: args, closures: closures)
            if let s = env.shape { recipe["shape"] = s }
            if let t = env.tint { recipe["tint"] = t }
            if let k = env.key { recipe["key"] = k }
            if env.help { recipe["tooltip"] = "title" }
            if args.contains("role: .destructive") || args.contains("role:.destructive") { importance = .destructive }
            else if env.key == "defaultAction" || (recipe["style"]?.hasSuffix("Prominent") ?? false) { importance = .main }
            else if env.key == "cancelAction" || args.contains("role: .cancel") || recipe["style"] == "link" { importance = .quiet }
        case "menu":
            recipe["style"] = env.menuStyle ?? "automatic"
            if let s = env.buttonStyle { recipe["look"] = s }
            if let s = env.indicator { recipe["indicator"] = s }
            recipe["label"] = env.labelStyle ?? buttonLabel(args: args, closures: closures)
            if let s = env.size { recipe["size"] = s }
        case "picker":
            recipe["style"] = env.pickerStyle ?? "automatic"
            if env.labelsHidden { recipe["label"] = "hidden" }
            if let s = env.size { recipe["size"] = s }
        case "toggle":
            recipe["style"] = env.toggleStyle ?? "automatic"
            if let s = env.size { recipe["size"] = s }
        default:
            recipe["style"] = env.textFieldStyle ?? "automatic"
            if let s = env.size { recipe["size"] = s }
        }
        return ComponentInventory.Use(element: element, place: context.place, recipe: recipe, importance: importance,
                                      role: env.role.map { "\(element).\($0)" }, file: file, line: line(of: start), view: context.view,
                                      trail: context.trail + (context.view.map { ["view \($0)"] } ?? []))
    }

    /// Buttons kept only for their keyboard shortcut, drawn at zero size or fully transparent: not part of the look.
    static func hidden(_ chains: [[Modifier]]) -> Bool {
        chains.contains { level in
            level.contains { m in
                let a = m.args.replacingOccurrences(of: " ", with: "")
                return m.name == "hidden" || (m.name == "opacity" && (a == "0" || a == "0.0"))
                    || (m.name == "frame" && a.contains("width:0") && a.contains("height:0"))
            }
        }
    }

    /// `.searchable(…)` is a search field in the toolbar.
    func searchField(at start: Int, scope: Scope, corpus: SwiftCorpus?, file: String) -> ComponentInventory.Use? {
        let context = self.context(of: start, scope: scope, corpus: corpus)
        guard !context.preview else { return nil }
        return ComponentInventory.Use(element: "field", place: "toolbar", recipe: ["style": "automatic"], importance: .other,
                                      role: nil, file: file, line: line(of: start), view: context.view)
    }

    /// How a button's label is made: from `systemImage:`, a title, or what the label closure draws.
    func buttonLabel(args: String, closures: [(label: String, open: Int)]) -> String {
        if args.contains("systemImage:") || args.contains("image:") { return "titleAndIcon" }
        let first = args.trimmingCharacters(in: .whitespacesAndNewlines)
        if first.hasPrefix("\"") || (!first.isEmpty && !first.hasPrefix("action:") && !first.hasPrefix("role:") && !first.hasPrefix("selection:")) {
            return "titleOnly"
        }
        // The label is the `label:` closure, or the trailing one when the action is an argument.
        let labelClosure = closures.first { $0.label == "label" } ?? (args.contains("action:") ? closures.first { $0.label.isEmpty } : nil)
        guard let open = labelClosure?.open, partner[open] > open else { return "custom" }
        let body = text(open + 1, partner[open])
        if body.contains("Label(") { return "titleAndIcon" }
        let image = body.contains("Image(")
        let title = body.contains("Text(")
        if image && title { return "titleAndIcon" }
        if image { return "iconOnly" }
        if title { return "titleOnly" }
        return "custom"
    }

    struct Context { var place: String?; var view: String?; var chains: [[Modifier]]; var preview: Bool; var trail: [String] = [] }

    /// Where a control sits, in order: the first enclosing block that names a place; for a control in a helper, the
    /// places where the helper is called (up to three hops); the helper's name (`footer`); the view's name; else unknown.
    /// The modifier chains of the enclosing calls are collected on the way, innermost first, for the styles they set.
    func context(of i: Int, scope: Scope, depth: Int = 0, names: Bool = true, corpus: SwiftCorpus? = nil) -> Context {
        // A helper's call site must not let its view's name beat the helper's own name (`actionBar` in a `DecideCard`),
        // so helper hops run with `names` off; a hop to another file's use of the view runs with it on.
        let view = scope.views.filter { $0.open < i && i < $0.close }.max { $0.open < $1.open }
        var ctx = Context(place: nil, view: view?.name, chains: [], preview: view?.name.hasSuffix("_Previews") ?? false)
        var inStack = false, collecting = true, customRow = false, inSection = false
        for brace in enclosingBraces(of: i).reversed() where !scope.declarations.contains(brace) {
            guard let o = owner(ofBrace: brace) else { continue }
            if o.hash && o.name == "Preview" { ctx.preview = true; return ctx }
            if ctx.trail.count < 12 { ctx.trail.append((o.dotted ? "." : "") + o.name + (o.label.map { " \($0):" } ?? "")) }
            let end = partner[brace] > brace ? partner[brace] + 1 : brace + 1
            if collecting { ctx.chains.append(chain(after: end).modifiers) }
            guard ctx.place == nil else { continue }
            switch (o.dotted, o.name) {
            case (true, "contextMenu"), (true, "commands"), (false, "CommandMenu"), (false, "CommandGroup"):
                ctx.place = "contextMenu"
            case (false, "Menu") where o.label == nil: ctx.place = "contextMenu"
            case (false, let name) where o.label == nil && (name.hasSuffix("MenuButton") || name.hasSuffix("Menu")): ctx.place = "contextMenu"
            case (true, "alert"), (true, "confirmationDialog"): ctx.place = "alert"
            case (false, "ToolbarItem"), (false, "ToolbarItemGroup"):
                ctx.place = o.args.contains("confirmationAction") || o.args.contains("cancellationAction") || o.args.contains("destructiveAction")
                    ? "sheetFooter" : "toolbar"
            case (true, "toolbar"): ctx.place = "toolbar"
            case (true, "safeAreaInset"), (true, "safeAreaBar"): if o.args.contains(".bottom") { ctx.place = "bottomBar" }
            case (true, "popover"), (false, "MenuBarExtra"): ctx.place = "popover"
            case (true, "inspector"): ctx.place = "inspector"
            case (false, "Form"): ctx.place = "form"
            case (false, "List"), (false, "Table"), (false, "TableColumn"), (false, "OutlineGroup"): ctx.place = "listRow"
            case (false, "ContentUnavailableView"): ctx.place = "emptyState"
            case (false, "GroupBox"): ctx.place = "card"
            case (false, "HStack"): inStack = true
            case (false, "Section"): inSection = true
            case (true, "sheet"), (true, "fullScreenCover"): ctx.place = inStack ? "sheetFooter" : "page"
            case (false, "WindowGroup"), (false, "Window"), (false, "UtilityWindow"), (false, "DocumentGroup"), (false, "NavigationStack"),
                 (false, "TabView"), (false, "Tab"):
                ctx.place = "page"
            case (false, "NavigationSplitView") where o.label == "detail" || o.label == "content": ctx.place = "page"
            case (false, "Settings"): ctx.place = "form"
            case (_, let name) where o.label != nil && (name.first?.isUppercase == true || o.dotted):
                // A labeled closure of the app's own container: `StandardSheetView(actionButtons:)`, `footer:`, `toolbar:`.
                let owner = Self.words(name), label = Self.words(o.label!)
                if owner.contains(where: { ["sheet", "dialog", "modal"].contains($0) }), label.contains(where: { ["action", "actions", "button", "buttons", "footer"].contains($0) }) {
                    ctx.place = "sheetFooter"
                } else if let named = Self.place(forView: o.label!, inStack: false), named != "listRow" { ctx.place = named }
            case (true, let name) where !Self.systemModifiers.contains(name):
                // The app's own modifiers that present something: `.bottomBar { }`, `.alert2(…) { }`.
                if let named = Self.place(forView: name, inStack: false), named != "listRow", named != "form" { ctx.place = named }
            case (false, let name) where name.first?.isUppercase == true:
                // The app's own containers say where they are by name: `HXSettingsCard`, `ActionBar`. A custom row
                // (`PropertyRow`, `InsetRow`) is a labeled form row as often as a list row, so it waits for what is around it.
                let named = Self.place(forView: name, inStack: inStack)
                if named == "listRow" { customRow = true } else { ctx.place = named }
            default: break
            }
            // Menu and alert items are drawn by the system: the styles after a Menu or an alert's view are its own, not theirs.
            if ctx.place == "contextMenu" || ctx.place == "alert" {
                if collecting { ctx.chains.removeLast() }
                collecting = false
            }
        }
        if ctx.place == nil, let member = scope.members.filter({ $0.open < i && i < $0.close && $0.name != "body" }).max(by: { $0.open < $1.open }) {
            ctx.trail.append("helper \(member.name)")
            if depth < 3 {
                // The styles come from the call site that gives the place, or else from the first one.
                var first: [[Modifier]]?
                for site in callSites(of: member.name, outside: member).prefix(4) {
                    let at = context(of: site.start, scope: scope, depth: depth + 1, names: false, corpus: corpus)
                    if at.preview { continue }
                    ctx.trail.append("called in: " + at.trail.prefix(4).joined(separator: " < "))
                    if let place = at.place { ctx.place = place; ctx.chains += [site.modifiers] + at.chains; first = nil; break }
                    if first == nil { first = [site.modifiers] + at.chains }
                }
                if let first { ctx.chains += first }
            }
            if ctx.place == nil, names { ctx.place = Self.place(forView: member.name, inStack: inStack) }
        }
        guard names else { return ctx }
        // In a sheet, a Section is a form; only a stack outside one is the footer.
        if ctx.place == nil, let name = view?.name { ctx.place = Self.place(forView: name, inStack: inStack && !inSection) }
        // The view is used elsewhere: its uses say where it is, and their styles reach it.
        if let name = view?.name, let used = corpus?.context(ofView: name, depth: depth) {
            if ctx.place == nil, let place = used.place, !(customRow && place == "listRow" && Self.formish(view?.name)) {
                ctx.place = place
                ctx.trail += used.trail
            }
            if collecting { ctx.chains += used.chains }
        }
        let formish = Self.formish(view?.name) || scope.members.contains { $0.open < i && i < $0.close && Self.formish($0.name) }
        if ctx.place == nil, inSection, formish { ctx.place = "form" }
        if ctx.place == nil && customRow { ctx.place = formish ? "form" : "listRow" }
        if ctx.place == "listRow", customRow, formish { ctx.place = "form" }
        return ctx
    }

    /// Names that say a view is a form-like page: a labeled row there is a form row, not a list row.
    static func formish(_ name: String?) -> Bool {
        guard let name else { return false }
        let w = words(name)
        return ["form", "settings", "setup", "preferences", "properties", "property", "options", "editor", "sheet", "page", "inspector", "dialog"]
            .contains(where: w.contains)
    }

    /// SwiftUI's own modifiers that take a closure: never read as a place by their name.
    static let systemModifiers: Set<String> = [
        "onChange", "onAppear", "onDisappear", "task", "overlay", "background", "mask", "onReceive", "onSubmit", "onTapGesture",
        "simultaneousGesture", "gesture", "navigationDestination", "fullScreenCover", "sheet", "onHover", "onDrop", "onKeyPress",
        "dropDestination", "draggable", "onCommand", "animation", "transaction", "focusedValue", "searchSuggestions", "refreshable",
        "swipeActions", "onMove", "onDelete", "onContinuousHover", "onGeometryChange", "onScrollGeometryChange", "contentShape",
        "accessibilityAction", "accessibilityActions", "matchedGeometryEffect", "visualEffect", "scrollTransition", "compositingGroup",
    ]

    /// Where a helper is used in this file, and the modifiers written after the call (`headerButtons(t).buttonStyle(.glass)`).
    func callSites(of name: String, outside member: (name: String, open: Int, close: Int)) -> [(start: Int, modifiers: [Modifier])] {
        var out: [(Int, [Modifier])] = []
        let word = Array(name.utf8)
        var i = 0
        while i + word.count <= b.count {
            defer { i += 1 }
            guard b[i] == word[0], Array(b[i..<(i + word.count)]) == word, i == 0 || !Self.isIdent(b[i - 1]),
                  i + word.count == b.count || !Self.isIdent(b[i + word.count]) else { continue }
            if i > member.open && i < member.close { continue }
            // Skip the declaration itself (`func name`, `var name`).
            if let before = identifier(endingAt: skipSpaceBack(i - 1)), ["func", "var", "let"].contains(before.name) { continue }
            var p = i + word.count
            if p < b.count, b[p] == UInt8(ascii: "("), partner[p] > p { p = partner[p] + 1 }
            out.append((i, chain(after: p).modifiers))
        }
        return out
    }

    /// Places told by a view's or helper's name, read as words: `TicketRow`, `DetailsCard`, `leadingToolbarItem`,
    /// `ScriptAsMenuContent`, `IdentityFormSections`. Chrome words come first, so `SettingsToolbar` is a toolbar.
    static func place(forView raw: String, inStack: Bool) -> String? {
        var w = words(raw)
        if w.last == "view", w.count > 1 { w.removeLast() }
        func has(_ x: String...) -> Bool { x.contains { w.contains($0) } }
        func pair(_ a: String, _ b: String) -> Bool { zip(w, w.dropFirst()).contains { $0 == a && $1 == b } }
        if pair("menu", "bar") { return "popover" }
        if has("toolbar") { return "toolbar" }
        if has("popover") { return "popover" }
        if has("inspector", "panel", "pane") { return "inspector" }
        if has("footer") || pair("bottom", "bar") || pair("action", "bar") { return "bottomBar" }
        if pair("empty", "state") { return "emptyState" }
        if has("menu", "commands") && !pair("menu", "button") { return "contextMenu" }
        if has("alert") { return "alert" }
        if has("card") { return "card" }
        if has("settings", "setup", "preferences", "properties", "property", "options", "form") { return "form" }
        if let last = w.last, ["row", "cell"].contains(last) { return "listRow" }
        if has("sheet", "dialog") { return inStack ? "sheetFooter" : nil }
        return nil
    }

    /// `HXSetupRow` → hx, setup, row; `leadingToolbarItem` → leading, toolbar, item.
    static func words(_ name: String) -> [String] {
        var out: [String] = [], current = ""
        let chars = Array(name)
        for (i, c) in chars.enumerated() {
            guard c.isLetter else { if !current.isEmpty { out.append(current) }; current = ""; continue }
            let prevLower = i > 0 && chars[i - 1].isLowercase
            let nextLower = i + 1 < chars.count && chars[i + 1].isLowercase
            let prevUpper = i > 0 && chars[i - 1].isUppercase
            if c.isUppercase, !current.isEmpty, prevLower || (prevUpper && nextLower) { out.append(current); current = "" }
            current.append(c)
        }
        if !current.isEmpty { out.append(current) }
        return out.map { $0.lowercased() }
    }
}

/// The style modifiers that reach a control: its own first, then each enclosing level, the nearest winning, as SwiftUI's
/// environment does.
struct StyleEnvironment {
    var buttonStyle: String?, size: String?, labelStyle: String?, shape: String?, tint: String?
    var menuStyle: String?, indicator: String?, pickerStyle: String?, toggleStyle: String?, textFieldStyle: String?
    var labelsHidden = false
    var key: String?, help = false, role: String?

    mutating func read(_ modifiers: [SwiftStructure.Modifier], own: Bool) {
        for m in modifiers {
            let a = m.args.trimmingCharacters(in: .whitespacesAndNewlines)
            switch m.name {
            case "buttonStyle": if buttonStyle == nil { buttonStyle = Self.style(a, suffix: "ButtonStyle") }
            case "controlSize": if size == nil { size = Self.member(a) }
            case "labelStyle": if labelStyle == nil, let s = Self.member(a), ["iconOnly", "titleOnly", "titleAndIcon"].contains(s) { labelStyle = s }
            case "buttonBorderShape": if shape == nil { shape = Self.member(a) }
            case "tint": if tint == nil { tint = Self.tint(a) }
            case "menuStyle": if menuStyle == nil { menuStyle = Self.style(a, suffix: "MenuStyle") }
            case "menuIndicator": if indicator == nil { indicator = Self.member(a) }
            case "pickerStyle": if pickerStyle == nil { pickerStyle = Self.style(a, suffix: "PickerStyle") }
            case "toggleStyle": if toggleStyle == nil { toggleStyle = Self.style(a, suffix: "ToggleStyle") }
            case "textFieldStyle": if textFieldStyle == nil { textFieldStyle = Self.style(a, suffix: "TextFieldStyle") }
            case "labelsHidden": labelsHidden = true
            case "keyboardShortcut" where own:
                if key == nil { key = a.hasPrefix(".defaultAction") ? "defaultAction" : a.hasPrefix(".cancelAction") ? "cancelAction" : nil }
            case "help" where own: help = true
            default:
                // A generated role modifier: `.buttonRole(.primary)`.
                if own, role == nil, m.name.hasSuffix("Role"), let r = Self.member(a) { role = r }
            }
        }
    }

    /// `.glass` → glass; `PlainButtonStyle()` → plain; `.glass(.clear)` → glass; `MyStyle()` → custom:MyStyle.
    static func style(_ a: String, suffix: String) -> String? {
        if let m = member(a) { return m }
        guard let first = a.split(whereSeparator: { $0 == "(" || $0 == " " }).first.map(String.init), !first.isEmpty else { return nil }
        if first.hasSuffix(suffix) {
            let base = String(first.dropLast(suffix.count))
            let known = ["Plain": "plain", "Borderless": "borderless", "Bordered": "bordered", "BorderedProminent": "borderedProminent",
                         "Link": "link", "Default": "automatic", "Automatic": "automatic", "Switch": "switch", "Checkbox": "checkbox",
                         "Segmented": "segmented", "Menu": "menu", "Inline": "inline", "RoundedBorder": "roundedBorder", "Button": "button",
                         "BorderlessButton": "borderlessButton"]
            if let k = known[base] { return k }
        }
        return "custom:" + first
    }

    /// The member a leading-dot argument names: `.small` → small, `.glass(.clear)` → glass.
    static func member(_ a: String) -> String? {
        guard a.hasPrefix("."), let id = a.dropFirst().split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).first else { return nil }
        return String(id)
    }

    static func tint(_ a: String) -> String {
        let lower = a.lowercased()
        if lower.contains("red") || lower.contains("critical") || lower.contains("destructive") { return "critical" }
        if lower.contains("accent") { return "accent" }
        return "custom"
    }
}
