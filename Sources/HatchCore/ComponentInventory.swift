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
        /// The literal title, when the code writes one (`Button("Rename…")`), for the wording rules (NF4).
        public var title: String?
        /// How sure the place is: `structure` (a List, a `.toolbar`, a Form around it, here or where the view is used),
        /// `name` (a view's or helper's name), or `page` (the default for a window's content). Checks trust structure most.
        public var evidence: String = "structure"
        /// The conditional branches it is in, outermost first (`if@120#140`, `case@300#2`): two uses in different
        /// branches of the same `if`/`else` or `switch` are never on screen together.
        public var branches: [String] = []
        /// What was around it, innermost first (`HStack`, `.toolbar`, `helper footer`, `view SettingsPage`): why it got
        /// its place, or why none.
        public var trail: [String] = []

        public var signature: String { ComponentRole.summary(recipe) }
        public var location: String { "\((file as NSString).lastPathComponent):\(line)" }
    }

    /// Uses of one element in one place with the same look.
    /// True when the two uses sit in different branches of one `if`/`else` chain or `switch`.
    public static func exclusive(_ a: Use, _ b: Use) -> Bool {
        guard a.file == b.file else { return false }
        for (x, y) in zip(a.branches, b.branches) where x != y {
            let sx = x.split(separator: "#").first, sy = y.split(separator: "#").first
            return sx == sy
        }
        return false
    }

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
        inventory(files: appFiles(appRoot: appRoot, excluding: excluding))
    }

    /// The app's own Swift files for macOS, as path and text (tests, other platforms and `excluding` left out).
    public static func appFiles(appRoot: String, excluding: [String] = []) -> [(path: String, text: String)] {
        let root = URL(fileURLWithPath: (appRoot as NSString).expandingTildeInPath).resolvingSymlinksInPath()
        let skip = excluding.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var texts: [(String, String)] = []
        for url in ComponentsScanner.swiftFiles(under: root) {
            let rel = ComponentsScanner.relative(url, to: root)
            if skip.contains(where: { rel.hasPrefix($0) }) { continue }
            if rel.split(separator: "/").contains(where: { $0.hasSuffix("Tests") || $0 == "Package.swift" }) { continue }
            if isOtherPlatform(rel) { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            texts.append((rel, text))
        }
        return texts
    }

    /// Folders and files for another system: `iOS/`, `TableProMobile/`, `Watch Extension/`, `View+iOS.swift`.
    static func isOtherPlatform(_ rel: String) -> Bool {
        let parts = rel.split(separator: "/").map(String.init)
        let folders = parts.dropLast()
        let other = ["ios", "ipados", "watchos", "watch", "tvos", "visionos", "xros", "mobile", "iphone", "ipad"]
        for f in folders {
            let l = f.lowercased()
            if other.contains(l) || ["iOS", "Mobile", "watchOS", "visionOS", "tvOS", "Watch Extension", "WatchKit Extension", "iPhone", "iPad"].contains(where: { f.hasSuffix($0) && f.count > $0.count })
                || other.contains(where: { l == $0 + " app" }) { return true }
        }
        let file = (parts.last ?? "").replacingOccurrences(of: ".swift", with: "")
        return ["+iOS", "_iOS", "-iOS", "+iPhone", "+iPad", "+visionOS", "+watchOS", "+tvOS", "_visionOS", "_watchOS"].contains(where: file.hasSuffix)
            || file.hasSuffix("iOS") && !file.hasSuffix("macOS")
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
            files.append(File(path: path, structure: s, scope: SwiftStructure.Scope(views: s.structs(), members: s.members(), types: s.typeBodies(), path: path),
                              hasControls: hasControls))
        }
        let names = Set(files.flatMap { $0.scope.views.map(\.name) })
        for (index, f) in files.enumerated() {
            for site in f.structure.typeUses(names) { viewUses[site.name, default: []].append((index, site.at, site.modifiers)) }
            for (name, mods) in f.structure.styleWrappers(f.scope) where customModifiers[name] == nil { customModifiers[name] = mods }
        }
    }

    /// The app's own modifiers that only apply styles (`func checkboxStyle() -> some View { toggleStyle(.checkbox) }`,
    /// `struct GlassButton: ViewModifier`), by name, so a control styled through them gets the real style.
    var customModifiers: [String: [SwiftStructure.Modifier]] = [:]
    private var closureMemo: [String: SwiftStructure.Context] = [:]

    /// For a control in a closure passed to the app's own container (`SheetLayout(…) { … } footer: { … }`), where the
    /// container draws that closure: the structure there and the styles it applies (`content().controlSize(.small)`).
    func closureContext(container: String, label: String?, labeled: Set<String> = [], depth: Int) -> SwiftStructure.Context? {
        let key = "\(container)|\(label ?? "")|\(labeled.sorted().joined(separator: ","))"
        if let known = closureMemo[key] { return known }
        guard depth < 6 else { return nil }
        for f in files {
            guard let decl = f.scope.views.first(where: { $0.name == container && f.structure.declaresBody(in: $0) }) else { continue }
            guard let property = label ?? f.structure.firstClosureProperty(in: decl, excluding: labeled),
                  let site = f.structure.uses(of: property, in: decl, scope: f.scope).first else { return nil }
            var ctx = f.structure.context(of: site.at, scope: f.scope, depth: depth + 1, names: false, corpus: nil)
            ctx.chains = [site.modifiers] + ctx.chains
            ctx.trail = ["inside \(container)" + (label.map { " \($0):" } ?? "")] + ctx.trail.prefix(3)
            closureMemo[key] = ctx
            return ctx
        }
        return nil
    }

    /// Where a view is used, as one context: the place most of its uses agree on (the first use breaks a tie), with the
    /// styles of a use in that place. Nil when nothing uses it or it is already being resolved (a view inside itself).
    func context(ofView name: String, depth: Int, element: String? = nil) -> SwiftStructure.Context? {
        let key = name + "|" + (element ?? "")
        if let known = memo[key] { return known }
        guard depth < 8, !resolving.contains(name) else { return nil }
        // Used nowhere as a view: shown by a window, a scene or AppKit (`NSHostingView(rootView:)`), so its content is a page.
        guard let sites = viewUses[name], !sites.isEmpty else {
            let root = SwiftStructure.Context(place: "page", view: name, chains: [], preview: false, trail: ["root view"], source: .page)
            memo[key] = root
            return root
        }
        resolving.insert(name)
        defer { resolving.remove(name) }
        var found: [(place: String?, ctx: SwiftStructure.Context, modifiers: [SwiftStructure.Modifier])] = []
        for site in sites.prefix(12) {
            let f = files[site.file]
            if f.structure.isRootArgument(at: site.at) {
                found.append(("page", SwiftStructure.Context(place: "page", view: name, chains: [], preview: false, trail: ["hosted as rootView"], source: .page), site.modifiers))
                continue
            }
            let ctx = f.structure.context(of: site.at, scope: f.scope, depth: depth + 1, names: true, corpus: self, element: element)
            if ctx.preview || ctx.hidden { continue }
            found.append((ctx.place, ctx, site.modifiers))
        }
        // Used only in previews or hidden places: a root after all.
        guard let first = found.first else {
            let root = SwiftStructure.Context(place: "page", view: name, chains: [], preview: false, trail: ["root view"], source: .page)
            memo[key] = root
            return root
        }
        // Count only the strongest kind of evidence: structure where any use has it, else names, else Page.
        let strongest = found.compactMap { $0.place == nil ? nil : $0.ctx.source.rawValue }.max()
        let counted = found.filter { $0.place != nil && $0.ctx.source.rawValue == strongest }
        var tally: [String: Int] = [:]
        for f in counted { tally[f.place!, default: 0] += 1 }
        // Most uses win; on a tie, the place that appears first.
        let order = counted.compactMap(\.place)
        let best = tally.keys.max { a, b in tally[a]! != tally[b]! ? tally[a]! < tally[b]! : order.firstIndex(of: a)! > order.firstIndex(of: b)! }
        let chosen = found.first { $0.place == best && $0.ctx.source.rawValue == strongest } ?? first
        var out = chosen.ctx
        out.place = best
        out.source = best == nil ? .page : chosen.ctx.source
        out.chains = [chosen.modifiers] + chosen.ctx.chains
        out.trail = ["used in \(found.count) place\(found.count == 1 ? "" : "s")"] + chosen.ctx.trail.prefix(4)
        memo[key] = out
        return out
    }
}

/// `#if` conditions judged for macOS: `os(macOS)` true, other systems and Mac Catalyst false, `canImport(UIKit)` false,
/// anything else (DEBUG, flags, `swift(>=6)`) true.
enum PlatformCondition {
    static func evaluate(_ text: String) -> Bool {
        var tokens: [String] = []
        var current = ""
        for c in text {
            if c.isLetter || c.isNumber || c == "_" || c == "." { current.append(c); continue }
            if !current.isEmpty { tokens.append(current); current = "" }
            if "()!,".contains(c) { tokens.append(String(c)) }
            else if c == "&" || c == "|" {
                if tokens.last == String(c) { tokens[tokens.count - 1] = String(c) + String(c) } else { tokens.append(String(c)) }
            } else if c == "/" { break }  // a trailing comment
        }
        if !current.isEmpty { tokens.append(current) }
        var i = 0
        func or() -> Bool { var v = and(); while i < tokens.count, tokens[i] == "||" { i += 1; let r = and(); v = v || r }; return v }
        func and() -> Bool { var v = unary(); while i < tokens.count, tokens[i] == "&&" { i += 1; let r = unary(); v = v && r }; return v }
        func unary() -> Bool {
            if i < tokens.count, tokens[i] == "!" { i += 1; return !unary() }
            return primary()
        }
        func primary() -> Bool {
            guard i < tokens.count else { return true }
            if tokens[i] == "(" { i += 1; let v = or(); if i < tokens.count, tokens[i] == ")" { i += 1 }; return v }
            let name = tokens[i]; i += 1
            var args: [String] = []
            if i < tokens.count, tokens[i] == "(" {
                i += 1
                var depth = 1
                while i < tokens.count, depth > 0 {
                    if tokens[i] == "(" { depth += 1 } else if tokens[i] == ")" { depth -= 1; if depth == 0 { i += 1; break } }
                    if depth > 0 && tokens[i] != "," { args.append(tokens[i]) }
                    i += 1
                }
            }
            switch name {
            case "os": return args.contains { ["macOS", "OSX"].contains($0) }
            case "targetEnvironment": return false
            case "canImport": return !args.contains { ["UIKit", "WatchKit", "UIKitCore", "CarPlay"].contains($0) }
            case "false": return false
            default: return true
            }
        }
        return or()
    }
}

/// Swift text with strings and comments masked and brackets matched: enough structure to follow a view's nesting and
/// modifier chains without a parser.
struct SwiftStructure {
    let b: [UInt8]
    /// The source as written (strings intact), for reading titles.
    let raw: [UInt8]
    /// For each bracket, the index of its partner; -1 elsewhere.
    var partner: [Int]
    let lineStarts: [Int]
    /// Every `{` that has a partner, in order.
    var braceOpens: [Int] = []

    init(_ text: String) {
        var bytes = Array(text.utf8)
        raw = bytes
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
        maskStringsAndComments(&b)
        maskOtherPlatforms(&b)
    }

    /// Blanks the branches of `#if` blocks that are not compiled on macOS (`#if os(iOS)`, `targetEnvironment(macCatalyst)`,
    /// `canImport(UIKit)`), and the directive lines themselves, so only the Mac's code is read and braces stay balanced.
    /// A condition Hatch cannot judge (`DEBUG`, a feature flag) counts as true.
    static func maskOtherPlatforms(_ b: inout [UInt8]) {
        var stack: [(active: Bool, taken: Bool, parent: Bool)] = []
        var lineStart = 0
        func blankLine(_ from: Int, _ to: Int) { var k = from; while k < to { if b[k] != 10 { b[k] = 32 }; k += 1 } }
        while lineStart < b.count {
            var lineEnd = lineStart
            while lineEnd < b.count, b[lineEnd] != 10 { lineEnd += 1 }
            var first = lineStart
            while first < lineEnd, isSpace(b[first]) { first += 1 }
            let line = first < lineEnd ? String(decoding: b[first..<lineEnd], as: UTF8.self) : ""
            let active = stack.last?.active ?? true
            if line.hasPrefix("#if ") || line.hasPrefix("#if(") || line == "#if" {
                let cond = PlatformCondition.evaluate(String(line.dropFirst(3)))
                stack.append((active && cond, cond, active))
                blankLine(lineStart, lineEnd)
            } else if line.hasPrefix("#elseif"), var top = stack.popLast() {
                let cond = PlatformCondition.evaluate(String(line.dropFirst(7)))
                top.active = top.parent && !top.taken && cond; top.taken = top.taken || cond
                stack.append(top)
                blankLine(lineStart, lineEnd)
            } else if line.hasPrefix("#else"), var top = stack.popLast() {
                top.active = top.parent && !top.taken; top.taken = true
                stack.append(top)
                blankLine(lineStart, lineEnd)
            } else if line.hasPrefix("#endif") {
                _ = stack.popLast()
                blankLine(lineStart, lineEnd)
            } else if !active {
                blankLine(lineStart, lineEnd)
            }
            lineStart = lineEnd + 1
        }
    }

    static func maskStringsAndComments(_ b: inout [UInt8]) {
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
    func rawText(_ from: Int, _ to: Int) -> String { from < to ? String(decoding: raw[from..<to], as: UTF8.self) : "" }

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
            // An argument closure (`Menu(content: { … }, label: …)`, `.contextMenu(forSelectionType:menu:)`): the call
            // whose parentheses hold it.
            if let open = enclosingParen(of: brace), let call = identifier(endingAt: skipSpaceBack(open - 1)) {
                let before = call.start - 1
                return (call.name, text(open + 1, partner[open] > open ? partner[open] : open + 1), label,
                        before >= 0 && b[before] == UInt8(ascii: "."), before >= 0 && b[before] == UInt8(ascii: "#"))
            }
            return nil
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

    /// The innermost `(` whose parentheses hold position `i`, if that comes before any enclosing `{`.
    func enclosingParen(of i: Int) -> Int? {
        var k = i - 1, depth = 0
        while k >= 0 {
            let c = b[k]
            if c == UInt8(ascii: ")") || c == UInt8(ascii: "]") || c == UInt8(ascii: "}") { depth += 1 }
            else if c == UInt8(ascii: "(") || c == UInt8(ascii: "[") || c == UInt8(ascii: "{") {
                if depth == 0 { return c == UInt8(ascii: "(") ? k : nil }
                depth -= 1
            }
            k -= 1
        }
        return nil
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

    static let styleModifierNames: Set<String> = ["buttonStyle", "controlSize", "labelStyle", "buttonBorderShape", "toggleStyle", "pickerStyle",
                                                  "textFieldStyle", "menuStyle", "menuIndicator", "tint", "labelsHidden"]

    /// Functions and ViewModifiers in this file that apply styles, with the styles in their bodies (the first branch of
    /// an `if #available` first, so the newest look wins).
    func styleWrappers(_ scope: Scope) -> [(String, [Modifier])] {
        var out: [(String, [Modifier])] = []
        func styles(_ open: Int, _ close: Int) -> [Modifier] {
            var mods: [Modifier] = [], k = open
            while k < close {
                // `.toggleStyle(…)` or, with an implicit self, `toggleStyle(…)` at the start of an expression.
                let start = b[k] == UInt8(ascii: ".") ? k + 1 : (Self.isIdentStart(b[k]) && !Self.isIdent(b[k - 1]) && b[k - 1] != UInt8(ascii: ".") ? k : -1)
                if start >= 0, let id = identifier(startingAt: start), Self.styleModifierNames.contains(id.name) {
                    let paren = skipSpace(id.end, newlines: false)
                    if paren < b.count, b[paren] == UInt8(ascii: "("), partner[paren] > paren {
                        let args = text(paren + 1, partner[paren]).trimmingCharacters(in: .whitespaces)
                        // Only fixed styles: a parameter passed through says nothing here.
                        if args.isEmpty || args.hasPrefix(".") || args.first?.isUppercase == true { mods.append(Modifier(name: id.name, args: args)) }
                    }
                    k = id.end; continue
                }
                k += 1
            }
            return mods
        }
        for m in scope.members where m.name != "body" && m.name != "makeBody" && m.name.first?.isLowercase == true {
            let mods = styles(m.open, m.close)
            if !mods.isEmpty { out.append((m.name, mods)) }
        }
        // `struct GlassButton: ViewModifier { func body(content: Content) -> some View { … } }`
        for v in scope.views where text(v.open - min(v.open, 120), v.open).contains("ViewModifier") {
            let mods = styles(v.open, v.close)
            if !mods.isEmpty { out.append((v.name, mods)) }
        }
        return out
    }

    /// True when a type's body here declares `var body`.
    func declaresBody(in decl: (name: String, open: Int, close: Int)) -> Bool {
        text(decl.open, decl.close).contains("var body")
    }

    /// The first closure property of a container (`let content: () -> Content`, `@ViewBuilder var content`): what a
    /// trailing closure fills.
    func firstClosureProperty(in decl: (name: String, open: Int, close: Int), excluding labeled: Set<String> = []) -> String? {
        let body = text(decl.open, decl.close)
        // An explicit initializer decides the order: its first closure parameter not labeled at the call.
        if let initRange = body.range(of: "init("), let close = body[initRange.upperBound...].firstIndex(of: "{") {
            let params = body[initRange.upperBound..<close]
            for part in params.split(separator: ",") {
                let words = part.split(separator: ":", maxSplits: 1)
                guard words.count == 2 else { continue }
                let names = words[0].split(separator: " ").map(String.init)
                guard let name = names.last?.replacingOccurrences(of: "@ViewBuilder", with: "") , !name.isEmpty else { continue }
                if (words[1].contains("->") || part.contains("@ViewBuilder")) && !labeled.contains(names.first ?? name) { return name }
            }
        }
        let re = ComponentReader.re(#"(@ViewBuilder\s+)?(?:let|var)\s+(\w+)\s*:\s*([^\n={]+)"#)
        for m in re.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let nameRange = Range(m.range(at: 2), in: body), let typeRange = Range(m.range(at: 3), in: body) else { continue }
            let name = String(body[nameRange]), type = String(body[typeRange])
            if name == "body" || labeled.contains(name) { continue }
            if m.range(at: 1).location != NSNotFound || type.contains("->") || type.trimmingCharacters(in: .whitespaces) == "Content" { return name }
        }
        return nil
    }

    /// Where a property of a type is drawn inside it: `content()`, `footer`, `self.content` (not its declaration).
    func uses(of property: String, in decl: (name: String, open: Int, close: Int), scope: Scope) -> [(at: Int, modifiers: [Modifier])] {
        var out: [(Int, [Modifier])] = []
        let word = Array(property.utf8)
        var i = decl.open
        while i + word.count <= decl.close {
            defer { i += 1 }
            guard b[i] == word[0], Array(b[i..<(i + word.count)]) == word, !Self.isIdent(b[i - 1]), !Self.isIdent(b[i + word.count]) else { continue }
            if let before = identifier(endingAt: skipSpaceBack(i - 1)), ["let", "var", "func"].contains(before.name) { continue }
            let next = skipSpace(i + word.count, newlines: false)
            if next < b.count, b[next] == UInt8(ascii: ":") || b[next] == UInt8(ascii: "=") { continue }
            if b[i - 1] == UInt8(ascii: "."), !(i >= 5 && text(i - 5, i) == "self.") { continue }
            // Inside a member's body (where views are built), not in an initializer's assignment.
            guard scope.members.contains(where: { $0.open < i && i < $0.close && $0.name != "init" }) else { continue }
            var p = i + word.count
            if p < b.count, b[p] == UInt8(ascii: "("), partner[p] > p { p = partner[p] + 1 }
            out.append((i, chain(after: p).modifiers))
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

    /// True when the `.` at `dot` continues an expression (`…).searchable(`), not an enum case (`kind: .searchable`).
    func isChained(_ dot: Int) -> Bool {
        let p = skipSpaceBack(dot - 1)
        guard p >= 0 else { return false }
        if b[p] == UInt8(ascii: ")") || b[p] == UInt8(ascii: "}") || b[p] == UInt8(ascii: "]") { return true }
        // After a value (`content.searchable`), not a type (`Kind.searchable`) or a keyword.
        guard let id = identifier(endingAt: p) else { return false }
        return id.name.first?.isLowercase == true && !["case", "return", "in"].contains(id.name)
    }

    /// The views and helpers of a file, read once.
    struct Scope {
        var views: [(name: String, open: Int, close: Int)]
        var members: [(name: String, open: Int, close: Int)]
        /// Bodies of declarations (types, functions, properties): never a container that names a place.
        var declarations: Set<Int>
        /// The file's path in the app, for folder hints (`Settings/`).
        var path: String

        init(views: [(name: String, open: Int, close: Int)], members: [(name: String, open: Int, close: Int)], types: [Int] = [], path: String = "") {
            self.views = views; self.members = members; self.path = path
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
            if id.name == "searchable", prev == UInt8(ascii: "."), isChained(i - 1) {
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
        var p = skipSpace(nameEnd, newlines: false), args = "", rawArgs = ""
        var closures: [(label: String, open: Int)] = []
        if p < b.count, b[p] == UInt8(ascii: "("), partner[p] > p { args = text(p + 1, partner[p]); rawArgs = rawText(p + 1, partner[p]); p = partner[p] + 1 }
        let trailing = skipSpace(p, newlines: false)
        if trailing < b.count, b[trailing] == UInt8(ascii: "{"), partner[trailing] > trailing {
            closures.append(("", trailing)); p = partner[trailing] + 1
        }
        let own = chain(after: p)
        closures += own.closures

        // Inside a ButtonStyle's makeBody a Button is part of the style, not a use.
        if scope.members.contains(where: { $0.name == "makeBody" && $0.open < start && start < $0.close }) { return nil }
        var context = self.context(of: start, scope: scope, corpus: corpus, element: element)
        guard !context.preview, !context.hidden, !Self.hidden([own.modifiers] + context.chains) else { return nil }
        // A field or switch beside the footer buttons is still part of the sheet's form.
        if context.place == "sheetFooter", element != "button", element != "menu" { context.place = "form" }

        var env = StyleEnvironment()
        let custom = corpus?.customModifiers ?? [:]
        env.read(own.modifiers, own: true, custom: custom)
        for level in context.chains { env.read(level, own: false, custom: custom) }

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
            else if let hint = context.importance {
                importance = hint
                // A confirmation or cancellation placement is the Return or Esc button.
                if recipe["key"] == nil, hint == .main { recipe["key"] = "defaultAction" }
                if recipe["key"] == nil, hint == .quiet { recipe["key"] = "cancelAction" }
            }
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
                                      // Only a title written as the first argument (`Button("Rename…")`).
                                      title: title(rawArgs: rawArgs, closures: closures),
                                      evidence: context.place == nil ? "none" : ["page", "name", "structure"][context.source.rawValue],
                                      branches: branches(of: start),
                                      trail: context.trail + (context.view.map { ["view \($0)"] } ?? []))
    }

    /// The `if`/`else` and `switch` branches around `i`, outermost first. An `if` chain is named by the brace of its
    /// first branch, so `if a {…} else if b {…} else {…}` gives three ids with one prefix.
    func branches(of i: Int) -> [String] {
        var out: [String] = []
        for brace in enclosingBraces(of: i) {
            if let chain = ifChainStart(brace) { out.append("if@\(chain)#\(brace)"); continue }
            if statementKeyword(before: brace) == "switch" {
                // The case label in force at `i`: the last `case`/`default` at this depth before it.
                var caseIndex = 0, k = brace + 1, depth = 0
                while k < i {
                    let c = b[k]
                    if c == UInt8(ascii: "{") || c == UInt8(ascii: "(") || c == UInt8(ascii: "[") { depth += 1 }
                    else if c == UInt8(ascii: "}") || c == UInt8(ascii: ")") || c == UInt8(ascii: "]") { depth -= 1 }
                    else if depth == 0, Self.isIdentStart(c), k == 0 || !Self.isIdent(b[k - 1]), let id = identifier(startingAt: k),
                            id.name == "case" || id.name == "default" { caseIndex += 1; k = id.end; continue }
                    k += 1
                }
                out.append("case@\(brace)#\(caseIndex)")
            }
        }
        return out
    }

    /// Where the statement a `{` opens starts: after the previous line break, `{`, `}` or `;` outside brackets.
    func statementStart(before brace: Int) -> Int {
        var k = brace - 1, depth = 0
        while k >= 0 {
            let c = b[k]
            if c == UInt8(ascii: ")") || c == UInt8(ascii: "]") { depth += 1 }
            else if c == UInt8(ascii: "(") || c == UInt8(ascii: "[") { if depth == 0 { break }; depth -= 1 }
            else if depth == 0, c == 10 || c == UInt8(ascii: "{") || c == UInt8(ascii: "}") || c == UInt8(ascii: ";") { break }
            k -= 1
        }
        return skipSpace(k + 1, newlines: true)
    }

    /// The first word of the statement a `{` opens (`if`, `else`, `switch`, `for`, or a call's name).
    func statementKeyword(before brace: Int) -> String? { identifier(startingAt: statementStart(before: brace))?.name }

    /// For a brace that is a branch of an `if` chain, the brace of the chain's first branch: `else` and `else if`
    /// branches follow the `}` before their `else` back to the `if`.
    func ifChainStart(_ brace: Int) -> Int? {
        guard let word = statementKeyword(before: brace), word == "if" || word == "else" else { return nil }
        var current = brace
        while true {
            let start = statementStart(before: current)
            guard identifier(startingAt: start)?.name == "else" else { return current }
            let prev = skipSpaceBack(start - 1)
            guard prev >= 0, b[prev] == UInt8(ascii: "}"), partner[prev] >= 0 else { return current }
            current = partner[prev]
        }
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

    /// The literal title: the first argument (`Button("Rename…")`), or the label's `Label("…")` or `Text("…")`.
    func title(rawArgs: String, closures: [(label: String, open: Int)]) -> String? {
        if rawArgs.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("\"") { return Self.firstLiteral(rawArgs) }
        guard let open = (closures.first { $0.label == "label" } ?? closures.last)?.open, partner[open] > open else { return nil }
        let body = rawText(open + 1, partner[open])
        for marker in ["Label(", "Text("] {
            if let r = body.range(of: marker) {
                let after = body[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if after.hasPrefix("\"") { return Self.firstLiteral(after) }
            }
        }
        return nil
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
        for style in ["iconOnly", "titleOnly", "titleAndIcon"] where body.contains("labelStyle(.\(style))") { return style }
        if body.contains("Label(") { return "titleAndIcon" }
        let image = body.contains("Image(")
        let title = body.contains("Text(")
        if image && title { return "titleAndIcon" }
        if image { return "iconOnly" }
        if title { return "titleOnly" }
        return "custom"
    }

    /// How a place was found. Structure (a `List`, a `.toolbar`, a `Form` around it, here or where the view is used)
    /// beats a name (`TicketRow`, `footer`), and a name beats Page, the default for a window's or sheet's content.
    enum PlaceSource: Int { case page = 0, name = 1, structure = 2 }

    struct Context {
        var place: String?
        var view: String?
        var chains: [[Modifier]]
        var preview: Bool
        var trail: [String] = []
        var source: PlaceSource = .page
        /// Importance a container implies (`ToolbarItem(placement: .confirmationAction)` holds the main action).
        var importance: ComponentRole.Importance?
        /// Inside something never drawn (`.accessibilityActions`).
        var hidden = false

        mutating func set(_ place: String?, _ source: PlaceSource) {
            guard let place else { return }
            self.place = place
            self.source = place == "page" ? .page : source
        }
    }

    /// Where a control sits. In order: the first enclosing block that names a place; for a control in a helper, the
    /// blocks around the helper's call sites (up to three hops); the blocks around the view's uses in other files; the
    /// helper's name (`footer`); the view's name; Page when the view is a window's content; else unknown. The modifier
    /// chains of the enclosing calls are collected on the way, innermost first, for the styles they set.
    func context(of i: Int, scope: Scope, depth: Int = 0, names: Bool = true, corpus: SwiftCorpus? = nil, element: String? = nil) -> Context {
        // Helper hops run with `names` off, so a call site's view name never beats the helper's own name
        // (`actionBar` in a `DecideCard`); the first level applies names after all structure has been tried.
        let view = scope.views.filter { $0.open < i && i < $0.close }.max { $0.open < $1.open }
        var ctx = Context(place: nil, view: view?.name, chains: [], preview: view?.name.hasSuffix("_Previews") ?? false)
        var inStack = false, collecting = true, customRow = false, inSection = false, softCard = false, sealed = false
        let levels = enclosingBraces(of: i).reversed().filter { !scope.declarations.contains($0) }.map { (brace: $0, owner: owner(ofBrace: $0)) }
        for (k, level) in levels.enumerated() {
            guard let o = level.owner else { continue }
            let brace = level.brace
            if o.hash && o.name == "Preview" { ctx.preview = true; return ctx }
            if o.dotted, o.name.hasPrefix("accessibility") { ctx.hidden = true }
            if ctx.trail.count < 12 { ctx.trail.append((o.dotted ? "." : "") + o.name + (o.label.map { " \($0):" } ?? "")) }
            let end = partner[brace] > brace ? partner[brace] + 1 : brace + 1
            let after = chain(after: end)
            // Styles the app's own container applies where it draws this closure come before its outside chain.
            if collecting, !o.dotted, o.name.first?.isUppercase == true,
               let inner = corpus?.closureContext(container: o.name, label: o.label, labeled: Set(after.closures.map(\.label)), depth: depth) {
                ctx.chains += inner.chains
            }
            if collecting { ctx.chains.append(after.modifiers) }
            guard ctx.place == nil else { continue }
            let outer = levels.dropFirst(k + 1).first { $0.owner != nil }?.owner
            switch (o.dotted, o.name) {
            case (true, "contextMenu"), (true, "commands"), (false, "CommandMenu"), (false, "CommandGroup"):
                ctx.set("contextMenu", .structure)
            case (false, "Menu") where o.label == nil || o.label == "content": ctx.set("contextMenu", .structure)
            case (false, "MenuBarExtra"):
                // A menu bar extra is a menu unless it asks for a window.
                let window = after.modifiers.contains { $0.name == "menuBarExtraStyle" && $0.args.contains("window") }
                ctx.set(window ? "popover" : "contextMenu", .structure)
            case (false, let name) where o.label == nil && (name.hasSuffix("MenuButton") || name.hasSuffix("Menu")): ctx.set("contextMenu", .structure)
            case (true, "alert"), (true, "confirmationDialog"): ctx.set("alert", .structure)
            case (false, "ToolbarItem"), (false, "ToolbarItemGroup"):
                if o.args.contains("confirmationAction") { ctx.importance = .main }
                else if o.args.contains("cancellationAction") { ctx.importance = .quiet }
                else if o.args.contains("destructiveAction") { ctx.importance = .destructive }
                ctx.set(ctx.importance == nil ? "toolbar" : "sheetFooter", .structure)
            case (true, "toolbar"): ctx.set("toolbar", .structure)
            case (true, "safeAreaInset"), (true, "safeAreaBar"):
                if o.args.contains(".bottom") { ctx.set("bottomBar", .structure) } else if o.args.contains(".top") { ctx.set("actionRow", .structure) }
            case (true, "popover"): ctx.set("popover", .structure)
            case (true, "inspector"): ctx.set("inspector", .structure)
            case (false, "Form"): ctx.set("form", .structure)
            case (false, "GridRow"): ctx.set("form", .structure)
            case (false, "List"), (false, "Table"), (false, "TableColumn"), (false, "OutlineGroup"): ctx.set("listRow", .structure)
            case (false, "ForEach") where ["LazyVGrid", "LazyHGrid", "LazyVStack", "LazyHStack", "Grid"].contains(outer?.name ?? ""):
                ctx.set("listRow", .structure)
            case (false, "ForEach") where (element == "button" || element == "menu") && (outer?.name == "Section" || inStack)
                    && !levels.dropFirst(k + 1).contains(where: { l in l.owner.map { ["toolbar", "contextMenu", "Menu", "alert", "confirmationDialog", "ToolbarItem", "ToolbarItemGroup"].contains($0.name) } ?? false }):
                // Actions on records repeated in rows (a stack per item) are row actions; a form's own toggles stay form.
                ctx.set("listRow", .structure)
            case (false, "ContentUnavailableView"): ctx.set("emptyState", .structure)
            case (false, "GroupBox"): ctx.set("card", .structure)
            case (false, "GlassEffectContainer"): ctx.set("floating", .structure)
            case (false, "NavigationLink") where o.label == nil && after.closures.contains(where: { $0.label == "label" }):
                ctx.set("page", .structure)  // the destination, not the link's row
            case (false, "HStack"):
                inStack = true
                if isSubmitRow(brace) {
                    // A popover's own Cancel and Apply row is still the popover.
                    let inPopover = levels.dropFirst(k + 1).contains { $0.owner?.dotted == true && $0.owner?.name == "popover" }
                        || Self.words(view?.name ?? "").contains("popover")
                    ctx.set(inPopover ? "popover" : "sheetFooter", .structure)
                } else if followsTitle(brace, within: levels.dropFirst(k + 1).first?.brace) || precedesList(brace) {
                    ctx.set("actionRow", .structure)
                }
            case (false, "Section"): inSection = true
            case (true, "sheet"), (true, "fullScreenCover"): ctx.set(inStack ? "sheetFooter" : "page", .structure)
            case (false, "WindowGroup"), (false, "Window"), (false, "UtilityWindow"), (false, "DocumentGroup"), (false, "NavigationStack"),
                 (false, "TabView"), (false, "Tab"):
                ctx.set("page", .page)
            case (false, "NavigationSplitView") where o.label == "detail" || o.label == "content": ctx.set("page", .page)
            case (false, "Settings"): ctx.set("form", .structure)
            case (false, let name) where name.first?.isUppercase == true
                    && corpus?.closureContext(container: name, label: o.label, labeled: Set(after.closures.map(\.label)), depth: depth)?.place != nil:
                // Inside the app's own container: where it draws this closure decides.
                let inner = corpus!.closureContext(container: name, label: o.label, labeled: Set(after.closures.map(\.label)), depth: depth)!
                ctx.set(inner.place, inner.source == .page ? .page : .structure)
                ctx.importance = ctx.importance ?? inner.importance
            case (_, let name) where o.label != nil && (name.first?.isUppercase == true || o.dotted):
                // A labeled closure of the app's own container: `StandardSheetView(actionButtons:)`, `footer:`.
                let owner = Self.words(name), label = Self.words(o.label!)
                if owner.contains(where: { ["sheet", "dialog", "modal"].contains($0) }), label.contains(where: { ["action", "actions", "button", "buttons", "footer"].contains($0) }) {
                    ctx.set("sheetFooter", .structure)
                } else if let named = Self.place(forView: name, inStack: false), ["emptyState", "card", "popover", "inspector", "alert"].contains(named) {
                    ctx.set(named, .structure)  // `UnavailableStateView(actions:)`, `SectionCard(footer:)`
                } else if let named = Self.place(forView: o.label!, inStack: false), named != "listRow" { ctx.set(named, .structure) }
            case (true, let name) where !Self.systemModifiers.contains(name):
                // The app's own modifiers that present something: `.bottomBar { }`, `.alert2(…) { }`.
                if let named = Self.place(forView: name, inStack: false), named != "listRow", named != "form" { ctx.set(named, .structure) }
            case (false, let name) where name.first?.isUppercase == true:
                // The app's own containers say where they are by name: `HXSettingsCard`, `ActionBar`, `CompatList`.
                // A custom row (`PropertyRow`) is a labeled form row as often as a list row, so it waits for what is around it.
                let named = Self.words(name).last == "list" ? "listRow" : Self.place(forView: name, inStack: inStack)
                if named == "listRow" && Self.words(name).last != "list" { customRow = true } else { ctx.set(named, .structure) }
            default: break
            }
            // A container drawn as glass floats; one with a rounded background is a card, but only when nothing larger
            // (a popover, an inspector, a settings group) names the place.
            if ctx.place == nil {
                if after.modifiers.contains(where: { $0.name == "glassEffect" }) { ctx.set("floating", .structure) }
                else if after.modifiers.contains(where: Self.isRoundedBackground) { softCard = true }
            }
            // Content of a sheet, a window or a navigation destination starts a new screen: what is around the
            // presenting code says nothing about it.
            if ctx.place == "page", (o.dotted && ["sheet", "fullScreenCover"].contains(o.name)) || (!o.dotted && ["WindowGroup", "Window", "UtilityWindow", "DocumentGroup", "NavigationLink"].contains(o.name)) {
                sealed = true
            }
            // Menu and alert items are drawn by the system: the styles after a Menu or an alert's view are its own, not theirs.
            if ctx.place == "contextMenu" || ctx.place == "alert" {
                if collecting { ctx.chains.removeLast() }
                collecting = false
            }
        }
        if ctx.place != nil, ctx.source == .page, ctx.place != "page" { ctx.source = .structure }

        if sealed { return ctx }
        let member = scope.members.filter({ $0.open < i && i < $0.close && $0.name != "body" }).max(by: { $0.open < $1.open })
        if let member, ctx.place == nil || ctx.source == .page {
            ctx.trail.append("helper \(member.name)")
            if depth < 3 {
                // The styles come from the call site that gives the place, or else from the first one.
                var first: [[Modifier]]?
                for site in callSites(of: member.name, outside: member, in: scope).prefix(4) {
                    let at = context(of: site.start, scope: scope, depth: depth + 1, names: false, corpus: corpus, element: element)
                    if at.preview || at.hidden { continue }
                    ctx.trail.append("called in: " + at.trail.prefix(4).joined(separator: " < "))
                    if let place = at.place, at.source.rawValue > ctx.source.rawValue || ctx.place == nil {
                        ctx.set(place, at.source); ctx.importance = ctx.importance ?? at.importance
                        ctx.chains += [site.modifiers] + at.chains; first = nil
                        if at.source == .structure { break }
                    }
                    if first == nil, ctx.place == nil { first = [site.modifiers] + at.chains }
                }
                if let first { ctx.chains += first }
            }
        }
        guard names else {
            if softCard, ctx.place == nil || ctx.source == .page { ctx.set("card", .name); ctx.trail.append("rounded background") }
            return ctx
        }

        // Where other files use this view: structure there beats any name here.
        let used = view.flatMap { corpus?.context(ofView: $0.name, depth: depth, element: element) }
        if let used, let place = used.place, used.source == .structure, ctx.place == nil || ctx.source != .structure {
            ctx.set(place, .structure); ctx.trail += used.trail
            ctx.importance = ctx.importance ?? used.importance
        }
        // Names: the helper's, then the view's. In a sheet, a Section is a form; only a stack outside one is the footer.
        if ctx.place == nil || ctx.source == .page, let member, var named = Self.place(forView: member.name, inStack: inStack) {
            if named == "bottomBar" || named == "actionRow", isSubmitRow(member.open) || Self.words(view?.name ?? "").contains(where: { ["sheet", "dialog"].contains($0) }) {
                named = "sheetFooter"
            }
            ctx.set(named, .name); ctx.trail.append("named \(member.name)")
        }
        if ctx.place == nil || ctx.source == .page, let name = view?.name, let named = Self.place(forView: name, inStack: inStack && !inSection) {
            ctx.set(named, .name); ctx.trail.append("named \(name)")
        }
        if softCard, ctx.place == nil || ctx.source == .page { ctx.set("card", .name); ctx.trail.append("rounded background") }
        if ctx.place == nil, let used, let place = used.place { ctx.set(place, used.source); ctx.trail += used.trail }
        if collecting, let used { ctx.chains += used.chains }

        let formish = Self.formish(view?.name) || scope.members.contains { $0.open < i && i < $0.close && Self.formish($0.name) }
        if ctx.place == nil, inSection, formish { ctx.set("form", .name); ctx.trail.append("section in a form-like view") }
        if ctx.place == nil && customRow { ctx.set(formish ? "form" : "listRow", .name); ctx.trail.append("custom row") }
        if ctx.place == "listRow", customRow, formish { ctx.set("form", .name); ctx.trail.append("custom row in a form-like view") }
        // A file in a Settings or Preferences folder is a settings form when nothing else says.
        if ctx.place == nil,
           scope.path.split(separator: "/").dropLast().contains(where: { ["settings", "preferences"].contains($0.lowercased()) }) {
            ctx.set("form", .name); ctx.trail.append("settings folder")
        }
        return ctx
    }

    /// A stack holding a Cancel and a default button: a sheet's or dialog's footer, wherever it is defined.
    func isSubmitRow(_ brace: Int) -> Bool {
        guard partner[brace] > brace else { return false }
        let body = text(brace, partner[brace])
        let cancels = body.contains(".cancelAction") || body.contains("role: .cancel")
        let confirms = body.contains(".defaultAction") || body.contains("Prominent")
        // Cancel and OK anywhere, or a right-aligned Done that dismisses as the last thing in its parent (a title bar's
        // close button is not a footer).
        return (cancels && confirms) || (body.contains("dismiss()") && body.contains("Spacer(") && body.contains("Button") && isLastChild(brace))
    }

    /// True when nothing but modifiers follows this block before its parent closes.
    func isLastChild(_ brace: Int) -> Bool {
        guard partner[brace] > brace else { return false }
        let end = chain(after: partner[brace] + 1).end
        let next = skipSpace(end, newlines: true)
        return next >= b.count || b[next] == UInt8(ascii: "}")
    }

    /// A row of controls right above a list, table or scrolling content (a Divider between is fine): the pane's actions.
    func precedesList(_ brace: Int) -> Bool {
        guard partner[brace] > brace else { return false }
        var p = skipSpace(chain(after: partner[brace] + 1).end, newlines: true)
        if let id = identifier(startingAt: p), id.name == "Divider" { p = skipSpace(chain(after: id.end).end, newlines: true) }
        guard let next = identifier(startingAt: p) else { return false }
        return ["List", "Table", "ScrollView", "LazyVStack", "LazyVGrid", "OutlineGroup"].contains(next.name)
    }

    /// A row right under a title (`Text(…).font(.largeTitle)` or `.title`): the page's actions.
    func followsTitle(_ brace: Int, within parent: Int?) -> Bool {
        let start = statementStart(before: brace)
        // Earlier siblings in the same parent (at most a dozen lines back).
        var k = start - 1, lines = 0
        let floor = parent ?? 0
        while k > floor, lines < 12 { if b[k] == 10 { lines += 1 }; k -= 1 }
        let before = text(max(floor, k), start)
        return [".font(.largeTitle", ".font(.title)", ".font(.title2", ".font(.title.", ".font(.title2.", ".font(.title3"].contains { before.contains($0) }
    }

    /// `.background(…, in: RoundedRectangle(…))`, `.clipShape(.rect(cornerRadius:))` and the like.
    static func isRoundedBackground(_ m: Modifier) -> Bool {
        guard ["background", "clipShape", "cornerRadius", "containerShape"].contains(m.name) else { return false }
        if m.name == "cornerRadius" { return true }
        return m.args.contains("RoundedRectangle") || m.args.contains("cornerRadius") || m.args.contains(".rect(")
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
    func callSites(of name: String, outside member: (name: String, open: Int, close: Int), in scope: Scope) -> [(start: Int, modifiers: [Modifier])] {
        var out: [(Int, [Modifier])] = []
        let owner = scope.views.filter { $0.open < member.open && member.close < $0.close }.max { $0.open < $1.open }
        let sameType = owner.map { o in scope.views.filter { $0.name == o.name } } ?? [(name: "", open: 0, close: b.count)]
        let word = Array(name.utf8)
        var i = 0
        while i + word.count <= b.count {
            defer { i += 1 }
            guard b[i] == word[0], Array(b[i..<(i + word.count)]) == word, i == 0 || !Self.isIdent(b[i - 1]),
                  i + word.count == b.count || !Self.isIdent(b[i + word.count]) else { continue }
            if i > member.open && i < member.close { continue }
            // Only inside the same type (its struct or extensions in this file): `content` elsewhere is another thing.
            if !sameType.contains(where: { $0.open < i && i < $0.close }) { continue }
            // Skip the declaration itself (`func name`, `var name`), argument labels (`content:`) and other objects' members.
            if let before = identifier(endingAt: skipSpaceBack(i - 1)), ["func", "var", "let"].contains(before.name) { continue }
            let next = skipSpace(i + word.count, newlines: false)
            if next < b.count, b[next] == UInt8(ascii: ":") { continue }
            if i > 0, b[i - 1] == UInt8(ascii: "."), !(i >= 5 && text(i - 5, i) == "self.") { continue }
            var p = i + word.count
            if p < b.count, b[p] == UInt8(ascii: "("), partner[p] > p { p = partner[p] + 1 }
            out.append((i, chain(after: p).modifiers))
        }
        return out
    }

    /// Places told by a view's or helper's name, read as words: `TicketRow`, `DetailsCard`, `leadingToolbarItem`,
    /// `ScriptAsMenuContent`, `IdentityFormSections`. Chrome words come first, so `SettingsToolbar` is a toolbar.
    static func place(forView raw: String, inStack: Bool, rows: Bool = true) -> String? {
        // Names only break ties: toolbar, menu, popover and inspector come from real modifiers, never a name
        // (`TabSectionToolbar` is a strip in the pane, `CertificateStatusPanel` a block in Settings).
        var w = words(raw)
        if w.last == "view", w.count > 1 { w.removeLast() }
        func has(_ x: String...) -> Bool { x.contains { w.contains($0) } }
        func pair(_ a: String, _ b: String) -> Bool { zip(w, w.dropFirst()).contains { $0 == a && $1 == b } }
        if has("footer") || pair("bottom", "bar") || pair("action", "bar") { return "bottomBar" }
        if pair("empty", "state") || has("unavailable", "placeholder") { return "emptyState" }
        if has("popover", "popup") || pair("menu", "bar") { return "popover" }
        if has("alert") { return "alert" }
        if has("card") || pair("group", "box") { return "card" }
        if has("settings", "setup", "preferences", "options", "form") { return "form" }
        if has("inspector") { return "inspector" }
        // `actionRow` is the actions under a title; `filterRow` or `headerRow` are strips, not list rows.
        if pair("action", "row") || pair("actions", "row") { return inStack && has("sheet", "dialog") ? "sheetFooter" : "actionRow" }
        if rows, let last = w.last, ["row", "cell"].contains(last) {
            let strip = ["filter", "header", "title", "top", "bottom", "tool", "button", "buttons", "tab", "search", "status"]
            return w.dropLast().last.map(strip.contains) == true ? nil : "listRow"
        }
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

    mutating func read(_ modifiers: [SwiftStructure.Modifier], own: Bool, custom: [String: [SwiftStructure.Modifier]] = [:]) {
        for m in modifiers {
            // The app's own style wrappers: a style named at the call (`style: .glass`) wins, then what the wrapper applies.
            if !SwiftStructure.styleModifierNames.contains(m.name), m.name != "keyboardShortcut", m.name != "help" {
                // A button style named at the call of a wrapper (`.fancyButtonStyle(style: .glass)`).
                if m.name.lowercased().contains("button"), m.name.lowercased().contains("style"), buttonStyle == nil,
                   let named = ["glassProminent", "glass", "borderedProminent", "bordered", "borderless", "plain", "link"].first(where: { m.args.contains(".\($0)") }) {
                    buttonStyle = named
                }
                let wrapped = m.name == "modifier" ? m.args.split(whereSeparator: { $0 == "(" || $0 == " " }).first.map(String.init) : m.name
                if let wrapped, let inner = custom[wrapped] {
                    read(inner, own: false)
                    continue
                }
            }
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

public extension ComponentInventoryScanner {
    /// The app's oldest supported macOS, from `Package.swift` (`.macOS(.v14)`, `.macOS("26.0")`) and Xcode projects
    /// (`MACOSX_DEPLOYMENT_TARGET = 13.0;`): the value most targets use. Nil when none says.
    static func minimumMacOS(appRoot: String) -> String? {
        let root = URL(fileURLWithPath: (appRoot as NSString).expandingTildeInPath)
        var found: [String: Int] = [:]
        let patterns = [ComponentReader.re(#"\.macOS\(\s*\.v(\d+)(?:_(\d+))?\s*\)"#), ComponentReader.re(#"\.macOS\(\s*"(\d+)(?:\.(\d+))?"#),
                        ComponentReader.re(#"MACOSX_DEPLOYMENT_TARGET\s*=\s*"?(\d+)(?:\.(\d+))?"#)]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in e {
            let name = url.lastPathComponent
            if ComponentsScanner.skippedFolders.contains(name) || name == "checkouts" { e.skipDescendants(); continue }
            if url.pathComponents.count - root.pathComponents.count > 4 { e.skipDescendants(); continue }
            guard name == "Package.swift" || name == "project.pbxproj" || name.hasSuffix(".xcconfig"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for re in patterns {
                for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let major = Range(m.range(at: 1), in: text).map({ String(text[$0]) }) else { continue }
                    let minor = Range(m.range(at: 2), in: text).map { String(text[$0]) } ?? "0"
                    // Old marketing numbers (10.15) count as they are.
                    found["\(major).\(minor)", default: 0] += 1
                }
            }
        }
        return found.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }
}
