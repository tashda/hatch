import Foundation

// Every view an app declares, accounted for, and its own components found (proposal on
// `design-review/components-model.html`, ids CM1 to CM12). The SwiftUI controls are one half of an app's design; the
// other half is the app's own views: chips, cards, rows, banners. Each view the app declares gets one answer, with the
// reason Hatch gave it: a component (a visual unit with a look of its own), a wrapper of another view, a screen, layout,
// a sample, or unknown. Unknown is a question for the owner, never a silent guess. Views that draw alike are grouped
// into one component with named variants (tones, sizes), so a design system has a few components, not a pile of views.

/// The look a view gives itself, read from its body: the parts that make a family (font, padding, shape) and the
/// colour, which makes a tone.
public struct AppViewStyle: Codable, Hashable, Sendable {
    public var font: String?
    public var weight: String?
    public var paddingH: Double?
    public var paddingV: Double?
    /// `capsule`, `rounded 8`, `circle`.
    public var shape: String?
    /// The fill behind it, as written (`Color.secondary.opacity(0.12)`).
    public var fill: String?
    /// The first foreground style, as written.
    public var tint: String?
    public var border = false

    /// The shape of the look without its colours: views alike here are one component.
    public var form: String {
        [font.map { "font \($0)" + (weight.map { " \($0)" } ?? "") }, paddingH.map { "padding \(Self.n($0))×\(Self.n(paddingV ?? $0))" },
         shape, border ? "bordered" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    /// The colour part: what tells two tones of one component apart.
    public var tone: String { [fill, tint].compactMap { $0 }.joined(separator: " on ") }

    public var isEmpty: Bool { font == nil && paddingH == nil && shape == nil && fill == nil && tint == nil && !border }

    static func n(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }
}

/// One view the app declares and the answer for it.
public struct AppView: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A visual unit with a look of its own: part of the design system, used once or many times.
        case component
        /// A thin wrapper that only passes on to another of the app's views.
        case wrapper
        /// A screen, page, sheet or pane: made of components, not one.
        case screen
        /// Arranges others and draws nothing of its own.
        case layout
        /// A design lab or sample file: kept out of the system.
        case sample
        /// Hatch could not tell: a question for the owner.
        case unknown

        public var title: String {
            switch self {
            case .component: "Component"
            case .wrapper: "Wrapper"
            case .screen: "Screen"
            case .layout: "Layout"
            case .sample: "Sample"
            case .unknown: "Unknown"
            }
        }
    }

    public var id: String
    /// The file's path in the app, as the inventory read it.
    public var file: String
    public var line: Int
    public var kind: Kind
    /// Why this answer, in a sentence: every answer can be checked.
    public var reason: String
    /// chip, label, card, row, header, banner, button, field, tile, glyph, bar.
    public var family: String?
    public var style: AppViewStyle
    public var interactive: Bool
    /// The app view it passes on to, for a wrapper.
    public var wraps: String?
    public var uses: Int
    public var usedIn: [String]
    public var bodyLines: Int
    /// What it shows, read from its call sites: the texts passed to it ("Merged cleanly", "Build failed").
    public var shows: [String] = []
    /// The screens it is used on, with how many times: the screen a use sits in, by its plain name.
    public var usedOn: [Screen] = []
    /// What it is for, read from what it is given and its name (CM22): `state`, `label`, `choice`, `count`, `action`,
    /// `sample`, `model:Ticket`… Views for the same purpose are one component even when drawn differently.
    public var purpose: String?
    /// The data it is given, as declared: `turn: Turn`, `text: String`.
    public var takes: [String] = []

    public struct Screen: Codable, Hashable, Sendable {
        public var name: String
        public var count: Int
        /// The file and line of the first use there, to open it.
        public var file: String
        public var line: Int
    }

    /// Its plain name: `HXProblemChip` → "Problem chip", `PlainChip` → "Plain chip".
    public var title: String { AppViewScanner.plainName(id) }
}

/// A component of the app's own, proposed from views that draw alike: one name, a few variants.
public struct AppComponentProposal: Codable, Identifiable, Hashable, Sendable {
    public struct Size: Codable, Hashable, Sendable {
        public var name: String
        public var members: [String]
        public var note: String?
    }

    public struct Variant: Codable, Hashable, Sendable {
        public var name: String
        public var members: [String]
        public var style: AppViewStyle
    }

    public var id: String
    public var title: String
    public var family: String
    public var interactive: Bool
    public var members: [String]
    public var variants: [Variant]
    /// The sizes Hatch proposes (small, medium, large), each with its views and what to settle.
    public var sizes: [Size]
    public var uses: Int
    /// What Hatch proposes and why, in a sentence.
    public var why: String
    /// What the views are for, in words ("show a state"), when Hatch could read it (CM22).
    public var purpose: String? = nil
}

/// The whole answer for an app: every view, the components proposed, and how much is accounted for.
public struct AppViewModel: Codable, Sendable {
    public var views: [AppView]
    public var proposals: [AppComponentProposal]

    public func count(_ kind: AppView.Kind) -> Int { views.filter { $0.kind == kind }.count }

    /// Views with an answer, as a share of all views outside samples: the system is not agreed below 100%.
    public var covered: Double {
        let counted = views.filter { $0.kind != .sample }
        guard !counted.isEmpty else { return 1 }
        return Double(counted.filter { $0.kind != .unknown }.count) / Double(counted.count)
    }
}

public enum AppViewScanner {
    /// Reads every view the app declares, answers each, and proposes the app's own components.
    /// `measured`: each view's height in points as the app drew it (from its gallery), which beats any estimate.
    public static func scan(files: [(path: String, text: String)], measured: [String: Double] = [:]) -> AppViewModel {
        var found: [(decl: Declaration, structure: SwiftStructure, file: String)] = []
        for f in files {
            let s = SwiftStructure(f.text)
            let sample = f.text.contains(ComponentInventoryScanner.sampleMarker)
            for d in declarations(s, sample: sample) { found.append((d, s, f.path)) }
        }
        let names = Set(found.map(\.decl.name))
        // Uses of each view across the app, outside its own declaration.
        var uses: [String: (count: Int, files: Set<String>)] = [:]
        var shows: [String: [String]] = [:]
        var sites: [String: [(enclosing: [String], file: String, line: Int)]] = [:]
        for f in files {
            let s = SwiftStructure(f.text)
            let here = found.filter { $0.file == f.path }
            for u in s.typeUses(names) {
                let own = here.contains { $0.decl.name == u.name && $0.decl.open < u.at && u.at < $0.decl.close }
                if own { continue }
                uses[u.name, default: (0, [])].count += 1
                uses[u.name, default: (0, [])].files.insert((f.path as NSString).lastPathComponent)
                // The first text passed to it: what this use shows.
                let paren = s.skipSpace(u.at + u.name.utf8.count, newlines: false)
                if paren < s.b.count, s.b[paren] == UInt8(ascii: "("), s.partner[paren] > paren,
                   let text = firstLiteral(s.rawText(paren + 1, s.partner[paren])), !(shows[u.name]?.contains(text) ?? false) {
                    shows[u.name, default: []].append(text)
                }
                // The declarations around it, outermost first: the screen it sits on is among them.
                let around = here.filter { $0.decl.open < u.at && u.at < $0.decl.close }.sorted { $0.decl.open < $1.decl.open }.map(\.decl.name)
                sites[u.name, default: []].append((around, f.path, s.line(of: u.at)))
            }
        }
        var views: [AppView] = []
        for (d, s, file) in found {
            let u = uses[d.name] ?? (0, [])
            var v = answer(d, s, file: file, names: names, uses: u.count, usedIn: u.files.sorted())
            v.shows = Array((shows[d.name] ?? []).prefix(6))
            views.append(v)
        }
        // Where each view is used, by screen: the outermost screen around a use, else the view it sits in.
        let kinds = Dictionary(views.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a })
        for i in views.indices {
            var screens: [String: AppView.Screen] = [:]
            for site in sites[views[i].id] ?? [] {
                guard let name = site.enclosing.first(where: { kinds[$0] == .screen }) ?? site.enclosing.last,
                      kinds[name] != .sample else { continue }
                screens[name, default: .init(name: plainName(name, screen: true), count: 0, file: site.file, line: site.line)].count += 1
            }
            views[i].usedOn = screens.values.sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        }
        views.sort { ($0.family ?? "~", $0.id) < ($1.family ?? "~", $1.id) }
        return AppViewModel(views: views, proposals: propose(views, measured: measured))
    }

    /// The first string literal in a call's arguments: what a use shows. Nil for an interpolated or empty one.
    static func firstLiteral(_ args: String) -> String? {
        guard let m = ComponentReader.re(#""([^"\\]{1,48})""#).firstMatch(in: args, range: NSRange(args.startIndex..., in: args)),
              let r = Range(m.range(at: 1), in: args) else { return nil }
        let text = String(args[r]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty || text.contains("\\(") ? nil : text
    }

    /// `plainName` for a view's type, as a function value.
    public static func plainNameOf(_ type: String) -> String { plainName(type) }

    /// A type's plain name: `HXProblemChip` → "Problem chip", `TicketDetailView` → "Ticket detail" (a screen drops its
    /// View or Page). A short all-capitals prefix (HX) is the app's, not part of the name.
    public static func plainName(_ type: String, screen: Bool = false) -> String {
        var words = SwiftStructure.words(type)
        if words.count > 1, let first = words.first, first.count <= 3,
           type.prefix(first.count).allSatisfy(\.isUppercase), type.dropFirst(first.count).first?.isUppercase == true { words.removeFirst() }
        if screen, words.count > 1, ["view", "page", "screen"].contains(words.last!) { words.removeLast() }
        guard let first = words.first else { return type }
        let special = ["github": "GitHub", "ios": "iOS", "macos": "macOS", "ui": "UI", "id": "ID", "url": "URL"]
        let out = words.enumerated().map { i, w in special[w] ?? (i == 0 ? w.prefix(1).uppercased() + w.dropFirst() : w) }
        _ = first
        // Brand names the word splitter cuts in two.
        return out.joined(separator: " ").replacingOccurrences(of: "Git hub", with: "GitHub").replacingOccurrences(of: "git hub", with: "GitHub")
            .replacingOccurrences(of: "Mac os", with: "macOS").replacingOccurrences(of: "mac os", with: "macOS")
    }

    /// The views of the app at a folder, read with the inventory's own file rules (tests, other platforms and samples
    /// marked as such are left out).
    public static func scan(appRoot: String, excluding: [String] = [], measured: [String: Double] = [:]) -> AppViewModel {
        scan(files: ComponentInventoryScanner.appFiles(appRoot: appRoot, excluding: excluding), measured: measured)
    }

    // MARK: Declarations

    struct Declaration {
        var name: String
        var header: String
        var open: Int
        var close: Int
        var line: Int
        var body: String
        var bodyLines: Int
        var sample: Bool
        /// The stored properties it is given, `name: Type`, leaving out its own state and the environment.
        var properties: [(name: String, type: String)] = []
    }

    /// `struct Name: View { … }` and `struct Name<Content: View>: View { … }`, with the body of `var body`.
    static func declarations(_ s: SwiftStructure, sample: Bool) -> [Declaration] {
        let text = s.text(0, s.b.count)
        let re = ComponentReader.re(#"\bstruct\s+([A-Z]\w*)\s*(<[^>{]*>)?\s*:\s*([^{]*)\{"#)
        var out: [Declaration] = []
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let nameR = Range(m.range(at: 1), in: text), let headR = Range(m.range(at: 3), in: text) else { continue }
            let header = String(text[headR])
            // A view, not a view modifier or a style.
            guard header.split(whereSeparator: { $0 == "," || $0 == " " }).contains(where: { $0 == "View" }) else { continue }
            // Byte offsets: the structure counts UTF-8 bytes.
            guard let whole = Range(m.range, in: text) else { continue }
            let open = text.utf8.distance(from: text.startIndex, to: whole.upperBound) - 1
            guard open >= 0, open < s.partner.count, s.partner[open] > open else { continue }
            let close = s.partner[open]
            let inside = s.text(open + 1, close)
            var body = inside
            if let r = inside.range(of: "var body"), let brace = inside[r.upperBound...].firstIndex(of: "{") {
                let start = inside.utf8.distance(from: inside.startIndex, to: brace) + open + 1
                if start < s.partner.count, s.partner[start] > start { body = s.text(start + 1, s.partner[start]) }
            }
            out.append(Declaration(name: String(text[nameR]), header: header, open: open, close: close, line: s.line(of: open),
                                   body: body, bodyLines: body.split(separator: "\n").count, sample: sample, properties: properties(inside)))
        }
        return out
    }

    /// The stored properties declared at the top level of a view's body of declarations: what it is given.
    static func properties(_ inside: String) -> [(name: String, type: String)] {
        // Its own state, the environment and the app's shared models (an observed model is where data comes from, not what is shown).
        let own = ["@State", "@StateObject", "@Environment", "@EnvironmentObject", "@FocusState", "@AppStorage", "@SceneStorage", "@Namespace",
                   "@GestureState", "@FetchRequest", "@Query", "@ObservedObject", "@Bindable"]
        let re = ComponentReader.re(#"^\s*((?:@\w+(?:\([^)]*\))?\s+)*)(?:(?:public|private|fileprivate|internal)\s+)?(?:let|var)\s+(\w+)\s*:\s*([^={]+?)\s*(=.*)?$"#)
        var out: [(String, String)] = [], depth = 0
        for line in inside.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if depth == 0, !line.contains("var body"), let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let a = Range(m.range(at: 1), in: line), let n = Range(m.range(at: 2), in: line), let t = Range(m.range(at: 3), in: line) {
                let attrs = String(line[a])
                let type = String(line[t]).trimmingCharacters(in: .whitespaces)
                let base = String(type.prefix { $0.isLetter || $0.isNumber })
                if !own.contains(where: attrs.contains), !["Model", "Store", "Configuration"].contains(where: base.hasSuffix) {
                    out.append((String(line[n]), type))
                }
            }
            if line.contains("var body") && depth == 0 { break }
            depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
        }
        return out
    }

    /// Words for a purpose: "show a state", "show a ticket".
    public static func purposeWords(_ p: String) -> String {
        let fixed = ["state": "show a state", "label": "name something", "choice": "pick or filter", "count": "show a count",
                     "action": "do something when clicked", "sample": "show a sample of something else", "shortcut": "show a shortcut"]
        if let w = fixed[p] { return w }
        guard p.hasPrefix("model:") else { return p }
        let words = SwiftStructure.words(String(p.dropFirst(6))).joined(separator: " ")
        return "show " + (["a", "e", "i", "o", "u"].contains(words.prefix(1)) ? "an " : "a ") + words
    }

    static let stateWords = ["status", "state", "turn", "phase", "result", "severity", "level", "outcome", "verdict", "health", "problem", "error",
                             "warning", "failure", "progress"]
    static let plainTypes = ["String", "LocalizedStringKey", "Text", "Int", "Double", "CGFloat", "Float", "Bool", "Color", "Image", "Date", "URL",
                             "UUID", "Font", "Content", "Label", "Icon", "Trailing", "Leading", "Detail", "Value", "ID", "Data", "Edge", "Alignment",
                             "AnyView", "CGSize", "CGPoint", "TimeInterval", "Character", "NSImage", "Any"]

    /// What a view is for, from what it is given and its name (CM22). Nil when nothing says it: then only the look groups it.
    static func purpose(name: String, properties: [(name: String, type: String)], interactive: Bool) -> String? {
        let words = SwiftStructure.words(name)
        let types = properties.map { $0.type.replacingOccurrences(of: "?", with: "") }
        let names = properties.map { $0.name.lowercased() }
        if words.contains(where: { ["sample", "example", "preview", "demo", "specimen"].contains($0) }) { return "sample" }
        let selection = zip(names, types).contains { n, t in
            t.hasPrefix("Binding<Bool") || (t == "Bool" && ["selected", "isselected", "ison", "on", "active", "isactive", "current", "iscurrent", "checked"].contains(n))
        }
        if interactive, selection { return "choice" }
        let typeWords = types.flatMap { SwiftStructure.words(String($0.prefix { $0.isLetter || $0.isNumber })) }
        if typeWords.contains(where: stateWords.contains) || words.contains(where: stateWords.contains) { return "state" }
        if words.contains(where: { ["key", "keys", "caps", "keycap", "shortcut"].contains($0) }) { return "shortcut" }
        let data = zip(names, types).filter { _, t in !t.contains("->") && !t.hasPrefix("Binding") }
        if let model = data.map(\.1).first(where: { t in
            let base = String(t.prefix { $0.isLetter || $0.isNumber })
            return base.first?.isUppercase == true && !plainTypes.contains(base) && !t.hasPrefix("[")
        }) {
            return "model:" + String(model.prefix { $0.isLetter || $0.isNumber })
        }
        if data.contains(where: { n, t in t == "Int" && ["count", "number", "total", "n"].contains(n) }), !types.contains("String") { return "count" }
        if !data.isEmpty, data.allSatisfy({ _, t in ["String", "LocalizedStringKey", "Text"].contains(t) || t == "String?" }) { return "label" }
        if interactive, types.contains(where: { $0.contains("->") }) { return "action" }
        return nil
    }

    // MARK: The answer for one view

    static let familyWords: [(String, [String])] = [
        ("chip", ["chip", "pill", "tag"]), ("badge", ["badge", "count"]), ("banner", ["banner", "callout", "notice", "toast"]),
        ("card", ["card", "tile", "box"]), ("row", ["row", "line", "cell", "item"]), ("header", ["header", "subtitle", "title", "heading"]),
        ("label", ["label", "caption"]), ("glyph", ["glyph", "icon", "dot", "avatar"]), ("button", ["button"]),
        ("field", ["field", "editor", "input"]), ("bar", ["bar", "strip"]), ("bubble", ["bubble", "message"]),
        ("keycap", ["caps", "keycap", "keycaps"]), ("menu", ["menu", "picker"]), ("empty state", ["empty"]),
        ("section", ["section", "group"]), ("thumbnail", ["thumb", "thumbnail", "swatch", "preview"]),
    ]
    static let screenWords = ["view", "page", "screen", "sheet", "window", "pane", "tab", "panel", "inspector", "assistant", "hub", "palette", "lab",
                              "settings", "form", "overview", "detail", "board"]

    static func answer(_ d: Declaration, _ s: SwiftStructure, file: String, names: Set<String>, uses: Int, usedIn: [String]) -> AppView {
        let words = SwiftStructure.words(d.name)
        let last = words.last ?? ""
        let style = readStyle(d.body)
        let interactive = ["Button(", "Button {", "Toggle(", "onTapGesture", "Menu(", "Menu {", "Picker("].contains { d.body.contains($0) }
        let family = familyWords.first { $0.1.contains(last) }?.0 ?? (screenWords.contains(last) ? nil : familyByLook(style))
        var view = AppView(id: d.name, file: file, line: d.line, kind: .unknown, reason: "", family: family,
                           style: style, interactive: interactive, wraps: nil, uses: uses, usedIn: usedIn, bodyLines: d.bodyLines)
        view.takes = d.properties.map { "\($0.name): \($0.type)" }
        view.purpose = purpose(name: d.name, properties: d.properties, interactive: interactive)

        if d.sample || words.first == "lab" || file.contains("/Labs/") {
            view.kind = .sample; view.reason = "Drawn in a design lab or a sample file."; view.family = nil
            return view
        }
        // A body that is one call to another of the app's views passes on to it.
        let trimmed = d.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let callee = names.first(where: { trimmed.hasPrefix($0 + "(") || trimmed.hasPrefix($0 + " {") || trimmed.hasPrefix($0 + "{") }),
           callee != d.name, d.bodyLines <= 3 {
            view.kind = .wrapper; view.wraps = callee; view.reason = "Its body is \(callee): the same component under another name."
            return view
        }
        // A name that says screen decides before the look: a sheet with a rounded panel is still a sheet.
        let named = familyWords.contains { $0.1.contains(last) }
        let screenish = (screenWords.contains(last) && !named) || d.bodyLines > 60
        if screenish {
            view.kind = .screen; view.family = nil
            view.reason = d.bodyLines > 60 ? "\(d.bodyLines) lines of body: a screen made of components." : "Named as a \(last): a screen made of components."
            return view
        }
        // A name and a look that disagree are asked about, not settled by Hatch: a "chip" with no capsule or fill.
        if family == "chip" || family == "badge", style.shape == nil, style.fill == nil, d.bodyLines <= 60 {
            view.reason = "Named a \(family!), but draws none (no shape, no fill): a label, or a \(family!) that lost its shape?"
            view.family = "label"
            return view
        }
        // A look of its own but no kind Hatch can tell: asked, never put in an "other" drawer.
        if family == nil, !style.isEmpty, d.bodyLines <= 60 {
            view.reason = "Draws a look of its own (\(style.form.isEmpty ? style.tone : style.form)), but neither its name nor its look says what kind of component it is."
            return view
        }
        if !style.isEmpty, d.bodyLines <= 60 {
            view.kind = .component
            view.reason = "Draws a look of its own (\(style.form.isEmpty ? style.tone : style.form))" + (uses > 0 ? ", used \(uses) time\(uses == 1 ? "" : "s")." : ".")
            return view
        }
        if style.isEmpty, d.header.contains("Content") || d.body.contains("Layout") {
            view.kind = .layout; view.family = nil; view.reason = "Arranges the content it is given and draws nothing of its own."
            return view
        }
        // A menu or picker of the app's own, built on the native control.
        if family == "menu", ["Menu(", "Menu {", "Picker("].contains(where: d.body.contains) {
            view.kind = .component
            view.reason = "A \(last) of the app's own, built on the native \(d.body.contains("Picker(") ? "Picker" : "Menu")."
            return view
        }
        if family != nil, d.bodyLines <= 30 {
            view.kind = .component
            view.reason = "A small \(family!) that takes its look from the controls inside it."
            return view
        }
        view.reason = "Neither a clear component nor a screen: \(d.bodyLines) lines, no look of its own read from the code."
        return view
    }

    /// A family from the look when the name says nothing: a capsule with caption text is a chip, a rounded surface with
    /// padding a card.
    static func familyByLook(_ st: AppViewStyle) -> String? {
        if st.shape == "capsule", st.font?.hasPrefix("caption") == true || st.font == "callout" { return "chip" }
        if st.shape?.hasPrefix("rounded") == true, (st.paddingH ?? 0) >= 10 { return "card" }
        return nil
    }

    static func lastMatch(_ pattern: String, _ text: String) -> [String]? {
        let re = ComponentReader.re(pattern)
        guard let m = re.matches(in: text, range: NSRange(text.startIndex..., in: text)).last else { return nil }
        return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    /// The style modifiers on the outside of a body, as written.
    static func readStyle(_ body: String) -> AppViewStyle {
        var st = AppViewStyle()
        func first(_ pattern: String) -> [String]? {
            let re = ComponentReader.re(pattern)
            guard let m = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) else { return nil }
            return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: body).map { String(body[$0]) } ?? "" }
        }
        // The font of the text (an icon beside it may be smaller), else the last one written: the outermost.
        // `.caption`, `.caption.weight(.medium)`, `.system(size: 13, weight: .semibold)`.
        let fontPattern = #"\.font\(\.(?:system\(size:\s*([\d.]+)(?:,\s*weight:\s*\.(\w+))?[^)]*\)|(\w+))(?:\.weight\(\.(\w+)\))?"#
        if let f = first(#"Text\([^)]*\)\s*"# + fontPattern) ?? lastMatch(fontPattern, body) {
            st.font = f[0].isEmpty ? f[2] : "system \(f[0])"
            let weight = f[1].isEmpty ? f[3] : f[1]
            st.weight = weight.isEmpty ? nil : weight
        }
        if let h = first(#"\.padding\(\.horizontal,\s*([\d.]+)\)"#) { st.paddingH = Double(h[0]) }
        if let v = first(#"\.padding\(\.vertical,\s*([\d.]+)\)"#) { st.paddingV = Double(v[0]) }
        if st.paddingH == nil, let p = first(#"\.padding\(([\d.]+)\)"#) { st.paddingH = Double(p[0]); st.paddingV = Double(p[0]) }
        if body.contains("Capsule()") { st.shape = "capsule" }
        else if let r = first(#"RoundedRectangle\(cornerRadius:\s*([\d.]+)"#) { st.shape = "rounded \(r[0])" }
        else if body.contains("Circle()") && body.contains(".background") { st.shape = "circle" }
        if let bg = first(#"\.background\(([^,()]+(?:\([^()]*\))*(?:\.\w+\([^()]*\))*)\s*,\s*in:"#) { st.fill = bg[0].trimmingCharacters(in: .whitespaces) }
        if let fg = first(#"\.foregroundStyle\(([^)]+\)?)\)"#) { st.tint = fg[0].trimmingCharacters(in: .whitespaces) }
        st.border = body.contains(".stroke(") || body.contains(".strokeBorder(")
        return st
    }

    // MARK: Proposals

    /// Most variants a component should have before Hatch proposes merging them: past it the system stops being one
    /// look with a few sizes and becomes a pile of one-offs.
    public static let variantBudget = 3

    /// Two looks that draw alike: the same shape, text style and weight, padding within a point. Colour is left out:
    /// a colour that changes with what is shown is the same component.
    static func drawnAlike(_ a: AppViewStyle, _ b: AppViewStyle) -> Bool {
        a.shape == b.shape && a.font == b.font && (a.weight ?? "regular") == (b.weight ?? "regular")
            && abs((a.paddingH ?? 0) - (b.paddingH ?? 0)) <= 1 && abs((a.paddingV ?? 0) - (b.paddingV ?? 0)) <= 1
    }

    /// The app's own components, grouped by what they are for within a family (chips, cards, rows…), interactive ones
    /// apart (CM22): views given the same kind of thing (a state, a label, a ticket) are one component even when drawn
    /// differently, and the owner then picks the look it keeps. Views whose purpose Hatch can't read are grouped by
    /// look. Each group is one proposal; the owner names it, merges groups, moves a view out or keeps them apart.
    static func propose(_ views: [AppView], measured: [String: Double] = [:]) -> [AppComponentProposal] {
        let components = views.filter { $0.kind == .component }
        let wrappersOf = Dictionary(grouping: views.filter { $0.kind == .wrapper }, by: { $0.wraps ?? "" })
        var out: [AppComponentProposal] = []
        let families = Dictionary(grouping: components, by: { ($0.family ?? "other") + ($0.interactive ? "+interactive" : "") })
        for (key, members) in families {
            let family = key.replacingOccurrences(of: "+interactive", with: "")
            let interactive = key.hasSuffix("+interactive")
            // Plain text says what a chip or label is for, but not what a header, row or card is for: those go by look.
            func grouping(_ v: AppView) -> String? { v.purpose == "label" && !["chip", "badge", "label"].contains(family) ? nil : v.purpose }
            var groups: [[AppView]] = []
            for v in members.sorted(by: { ($0.uses, $1.id) > ($1.uses, $0.id) }) {
                let i = groups.firstIndex { g in
                    if let p = grouping(v) { return grouping(g[0]) == p }
                    return grouping(g[0]) == nil && drawnAlike(g[0].style, v.style)
                }
                if let i { groups[i].append(v) } else { groups.append([v]) }
            }
            for group in groups {
                let lead = group[0]
                let all = group.map(\.id) + group.flatMap { wrappersOf[$0.id]?.map(\.id) ?? [] }
                let purpose = lead.purpose.map(purposeWords)
                let looks = group.reduce(into: [AppView]()) { ls, v in if !ls.contains(where: { drawnAlike($0.style, v.style) }) { ls.append(v) } }.count
                let why: String
                if group.count > 1, let purpose {
                    why = "These \(group.count) views all \(purpose)" + (looks > 1 ? ", drawn \(looks) ways: one \(family)?" : ": one \(family)?")
                } else if group.count > 1 {
                    why = "These \(group.count) views are drawn alike: one \(family)?"
                } else {
                    why = (["a", "e", "i", "o", "u"].contains(family.prefix(1)) ? "An " : "A ") + "\(family) of its own" + (purpose.map { ": it \(Self.thirdPerson($0))." } ?? ".")
                }
                out.append(AppComponentProposal(id: family + (interactive ? ".interactive" : "") + "." + lead.id, title: title(family: family, purpose: lead.purpose, lead: lead),
                                                family: family, interactive: interactive, members: all,
                                                variants: [.init(name: "", members: group.map(\.id), style: lead.style)], sizes: [],
                                                uses: group.reduce(0) { $0 + $1.uses }, why: why, purpose: purpose))
            }
        }
        return out.sorted { ($0.uses, $1.id) > ($1.uses, $0.id) }
    }

    /// "show a state" → "shows a state".
    public static func thirdPerson(_ words: String) -> String {
        guard let space = words.firstIndex(of: " ") else { return words }
        let verb = String(words[..<space])
        return (verb == "do" ? "does" : verb + "s") + words[space...]
    }

    /// A group's name from its purpose where that says more than one view's name: a chip for a state is a "Status chip".
    static func title(family: String, purpose: String?, lead: AppView) -> String {
        switch (purpose, family) {
        case ("state"?, _): return "Status " + family
        case ("label"?, "chip"): return "Tag"
        case ("choice"?, "chip"): return "Filter chip"
        case ("count"?, _): return "Count " + family
        default: return lead.title
        }
    }

    /// How a group's views compare, in a sentence, and whether their looks are the same (then nothing is chosen).
    public static func compare(_ views: [AppView]) -> (same: Bool, words: String) {
        guard let first = views.first else { return (true, "") }
        if views.count == 1 { return (true, first.style.form.isEmpty ? "Its look comes from the controls inside it." : "Drawn with \(first.style.form).") }
        if views.dropFirst().allSatisfy({ drawnAlike($0.style, first.style) }) {
            let tones = Set(views.map(\.style.tone)).count
            return (true, "Drawn the same" + (first.style.form.isEmpty ? "" : ": \(first.style.form)") + "." + (tones > 1 ? " Only the colour differs." : ""))
        }
        var diffs: [String] = []
        func differs(_ name: String, _ value: (AppViewStyle) -> String?) {
            let values = views.map { value($0.style) ?? "none" }
            if Set(values).count > 1 { diffs.append("\(name) (" + Array(NSOrderedSet(array: values)).compactMap { $0 as? String }.joined(separator: ", ") + ")") }
        }
        differs("text") { $0.font }
        differs("weight") { $0.weight ?? "regular" }
        differs("padding") { s in s.paddingH.map { "\(AppViewStyle.n($0))×\(AppViewStyle.n(s.paddingV ?? $0))" } }
        differs("shape") { $0.shape }
        return (false, "They differ in " + diffs.joined(separator: ", ") + ".")
    }

    /// Sizes for a family: forms that are nearly the same (same shape and text size, padding within a point) are one
    /// size first, with any difference in weight named; the rest are split where the sizes jump most, into at most
    /// three (small, medium, large). A starting point the owner corrects, never applied on its own.
    static func sizeProposal(_ members: [AppView], measured: [String: Double] = [:]) -> [(name: String, members: [String], note: String?)] {
        func near(_ a: AppViewStyle, _ b: AppViewStyle) -> Bool {
            a.shape == b.shape && a.font == b.font && abs((a.paddingH ?? 0) - (b.paddingH ?? 0)) <= 1 && abs((a.paddingV ?? 0) - (b.paddingV ?? 0)) <= 1
        }
        var groups: [[AppView]] = []
        for v in members.sorted(by: { $0.uses > $1.uses }) {
            if let i = groups.firstIndex(where: { near($0[0].style, v.style) }) { groups[i].append(v) } else { groups.append([v]) }
        }
        // The height as drawn when the app has drawn it; else text size in points (macOS's own sizes for each
        // style) plus the vertical padding, one scale for both.
        let points = ["caption2": 10.0, "caption": 10, "footnote": 10, "subheadline": 11, "callout": 12, "body": 13, "headline": 13,
                      "title3": 15, "title2": 17, "title": 22, "largeTitle": 26]
        func height(_ v: AppView) -> Double {
            if let m = measured[v.id] { return m }
            let st = v.style
            let size = st.font?.split(separator: " ").dropFirst().first.flatMap { Double($0) }
            let text = st.font.flatMap { points[$0] } ?? size ?? 13
            return text * 1.2 + 2 * (st.paddingV ?? 0)
        }
        func score(_ group: [AppView]) -> Double { group.map(height).reduce(0, +) / Double(group.count) }
        groups.sort { score($0) < score($1) }
        // More than three: cut where the scores jump most.
        var buckets: [[AppView]] = groups
        if groups.count > variantBudget {
            let gaps = (1..<groups.count).map { (i: $0, gap: score(groups[$0]) - score(groups[$0 - 1])) }
            let cuts = gaps.sorted { $0.gap > $1.gap }.prefix(variantBudget - 1).map(\.i).sorted()
            buckets = []; var start = 0
            for c in cuts + [groups.count] { buckets.append(groups[start..<c].flatMap { $0 }); start = c }
        }
        let names = buckets.count == 1 ? ["one size"] : buckets.count == 2 ? ["small", "large"] : ["small", "medium", "large"]
        return zip(names, buckets).map { name, vs in
            let weights = Set(vs.map { $0.style.weight ?? "regular" })
            let note = weights.count > 1 ? "weights differ (" + weights.sorted().joined(separator: ", ") + "): pick one" : nil
            return (name, vs.map(\.id), note)
        }
    }

    /// What SwiftUI offers for a family, if anything: the catalog element to draw, and the words for it. Shown beside
    /// the app's own views so the owner can choose the native option instead (CM15).
    public static func nativeOption(family: String) -> (element: String?, words: String) {
        switch family {
        case "card", "section": ("card", "SwiftUI's GroupBox: a titled box drawn by macOS.")
        case "row": ("row", "A List row: macOS draws its height, selection and separators.")
        case "button": ("button", "Button, in one of SwiftUI's styles.")
        case "menu": ("menu", "Menu or Picker, as macOS draws them.")
        case "field": ("field", "TextField, in one of SwiftUI's styles.")
        case "empty state": ("emptyState", "ContentUnavailableView: macOS's own empty state.")
        case "chip": (nil, "SwiftUI has no chip. The nearest native is a badge on a row (.badge) or a small bordered button.")
        case "badge": ("badge", "SwiftUI's .badge: a count on a row or a toolbar item, drawn by macOS.")
        case "label": (nil, "SwiftUI's Label: an icon and a title, styled by where it sits.")
        case "header": (nil, "No component: a header is text in one of macOS's styles (.title, .headline).")
        case "keycap": (nil, "SwiftUI has no keycap; menus show shortcuts themselves.")
        case "bubble", "banner", "thumbnail", "glyph", "bar": (nil, "SwiftUI has no \(family): this one is the app's own.")
        default: (nil, "No native equivalent.")
        }
    }

    /// A tone's name from its colour words: `Theme.critical` → critical, `Color.secondary.opacity(0.12)` → neutral.
    static func toneName(_ tone: String, _ views: [AppView]) -> String {
        let l = tone.lowercased()
        if l.contains("critical") || l.contains("red") { return "critical" }
        if l.contains("accent") { return "accent" }
        if l.contains("turn") || l.contains("for: ") { return "by turn" }
        if l.contains("secondary") || l.contains("gray") || l.contains("primary") || l.isEmpty { return "neutral" }
        return "own colour"
    }
}
