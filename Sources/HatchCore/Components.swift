import Foundation

// Components (decisions CO1 to CO8): the app's named colors, type, sizes and shared views. They live inside the app
// repository, normally as a local Swift package, so the app gets no new dependency and a change is one branch and one
// pull request. Hatch finds them, starts them through tickets, lists them for agents and the Components page, and points
// out values typed straight into views. Nothing here calls a model: it reads Swift text and asset catalogs.

/// Where a project's components are, relative to the app repository's root.
public struct ComponentsConfig: Codable, Equatable, Sendable {
    /// The folder that holds them, such as `Packages/AcmeComponents`. It may not exist yet while its setup ticket runs.
    public var path: String
    /// The library to import when the folder is a Swift package (`import AcmeComponents`). Nil for a plain folder in the
    /// app target, which the app can use but a Proposal cannot import.
    public var product: String?

    public init(path: String, product: String? = nil) {
        self.path = path; self.product = product
    }

    /// Where Hatch suggests starting them: a local package named after the app.
    public static func suggested(appName: String) -> ComponentsConfig {
        let base = appName.filter { $0.isLetter || $0.isNumber }
        let name = (base.isEmpty ? "App" : base.prefix(1).uppercased() + base.dropFirst()) + "Components"
        return ComponentsConfig(path: "Packages/\(name)", product: name)
    }
}

public extension ProjectConfig {
    /// The components folder on this Mac: inside the app clone, or the root of a separate components repository
    /// (the advanced case, for a package several apps share). Nil when the project has none or no clone here.
    var componentsFolder: String? {
        if let c = components, let app = repo(.app)?.localPath { return (app as NSString).appendingPathComponent(c.path) }
        if let separate = repo(.designSystem)?.localPath { return separate }
        return nil
    }

    /// How the components are described to people and agents: "Packages/AcmeComponents" or "acme/ui (its own repository)".
    var componentsLabel: String? {
        if let c = components { return c.path }
        if let separate = repo(.designSystem) { return "\(separate.remote) (its own repository)" }
        return nil
    }
}

// MARK: - What the components contain

public struct ComponentRGBA: Equatable, Sendable, Codable {
    public var red: Double, green: Double, blue: Double, alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    /// `#3366CC`, or `#3366CC80` when not opaque.
    public var hex: String {
        func byte(_ v: Double) -> String { String(format: "%02X", Int((max(0, min(1, v)) * 255).rounded())) }
        return "#" + byte(red) + byte(green) + byte(blue) + (alpha < 0.999 ? byte(alpha) : "")
    }
}

public struct ColorToken: Equatable, Sendable {
    /// How code refers to it: `Color.surface`, `Palette.accent`, or the asset name for a color set no code names.
    public var name: String
    public var light: ComponentRGBA?
    public var dark: ComponentRGBA?
    /// A system color it maps to, such as `blue` or `windowBackgroundColor`, when it has no value of its own.
    public var system: String?
    public var file: String
}

public struct FontToken: Equatable, Sendable {
    public var name: String
    /// A system text style (`headline`, `body`), so it follows Dynamic Type.
    public var style: String?
    public var size: Double?
    public var weight: String?
    public var design: String?
    /// A custom font family.
    public var family: String?
    public var file: String

    /// "Headline, semibold" or "15 pt, rounded".
    public var summary: String {
        var parts: [String] = []
        if let family { parts.append(family) }
        if let style { parts.append(style.prefix(1).uppercased() + style.dropFirst()) }
        if let size { parts.append(size == size.rounded() ? "\(Int(size)) pt" : "\(size) pt") }
        if let weight { parts.append(weight) }
        if let design, design != "default" { parts.append(design) }
        return parts.isEmpty ? "Custom" : parts.joined(separator: ", ")
    }
}

public struct SizeToken: Equatable, Sendable {
    public var name: String
    public var value: Double
    public var file: String
    public init(name: String, value: Double, file: String) { self.name = name; self.value = value; self.file = file }
}

public struct ViewEntry: Equatable, Sendable {
    public enum Kind: String, Sendable { case view, style, modifier }
    /// `PrimaryButton`, `CardStyle`, or `.cardBackground()` for a View extension.
    public var name: String
    public var kind: Kind
    public var file: String
}

/// Everything found in a components folder.
public struct ComponentCatalog: Equatable, Sendable {
    public var colors: [ColorToken] = []
    public var fonts: [FontToken] = []
    public var sizes: [SizeToken] = []
    public var views: [ViewEntry] = []
    public init() {}

    public var isEmpty: Bool { colors.isEmpty && fonts.isEmpty && sizes.isEmpty && views.isEmpty }
    public var tokenCount: Int { colors.count + fonts.count + sizes.count }

    /// What an agent's brief says about them: names only, a few per kind, so it costs a few hundred tokens at most.
    /// `values` adds each color's hex, for Sketches drawn in HTML.
    public func briefLines(cap: Int = 16, values: Bool = false) -> [String] {
        func list(_ names: [String]) -> String {
            let shown = names.prefix(cap).joined(separator: ", ")
            return names.count > cap ? shown + ", and \(names.count - cap) more" : shown
        }
        var out: [String] = []
        if !colors.isEmpty {
            out.append("- Colors: " + list(colors.map { c in
                guard values else { return c.name }
                if let l = c.light { return "\(c.name) \(l.hex)" + (c.dark.map { "/\($0.hex)" } ?? "") }
                return c.system.map { "\(c.name) (system \($0))" } ?? c.name
            }))
        }
        if !fonts.isEmpty { out.append("- Type: " + list(fonts.map(\.name))) }
        if !sizes.isEmpty { out.append("- Sizes: " + list(sizes.map { "\($0.name) \(Self.number($0.value))" })) }
        let views = self.views.filter { $0.kind == .view }.map(\.name)
        let styles = self.views.filter { $0.kind != .view }.map(\.name)
        if !views.isEmpty { out.append("- Views: " + list(views)) }
        if !styles.isEmpty { out.append("- Styles and modifiers: " + list(styles)) }
        return out
    }

    static func number(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
}

// MARK: - Reading Swift text

/// A forgiving reader for the Swift that usually holds components: `static let` tokens in extensions or enums, public
/// views and styles. It tracks braces to know the enclosing type and skips what it does not understand, so odd code
/// gives a shorter list, never a crash. Like `SwiftSource`, it scans text instead of parsing Swift.
public enum ComponentReader {
    /// Reads one file. `requirePublic` is true for a package, whose internal names the app cannot use.
    public static func read(_ text: String, file: String, requirePublic: Bool, into catalog: inout ComponentCatalog) {
        struct Scope { var name: String; var level: Int; var publicExtension: Bool; var isViewExtension: Bool }
        var stack: [Scope] = []
        var pending: Scope?
        var depth = 0
        for raw in text.components(separatedBy: "\n") {
            let line = stripComment(raw)
            let code = stripStrings(line)
            let before = depth
            let decl = typeDeclaration(line)
            for ch in code { if ch == "{" { depth += 1 } else if ch == "}" { depth -= 1 } }
            let innermost = stack.last
            let chain = stack.map(\.name)

            if let decl {
                let scope = Scope(name: decl.name, level: before + 1, publicExtension: decl.isExtension && decl.isPublic,
                                  isViewExtension: decl.isExtension && decl.name == "View")
                if code.contains("{") { stack.append(scope) } else { pending = scope }
                if let kind = decl.viewKind, !decl.isExtension, (!requirePublic || decl.isPublic), !decl.name.hasSuffix("_Previews") {
                    catalog.views.append(ViewEntry(name: (chain + [decl.name]).joined(separator: "."), kind: kind, file: file))
                }
                // `enum Radius { static let card: CGFloat = 12 }` on one line.
                if let open = line.firstIndex(of: "{") {
                    let rest = line[line.index(after: open)...].replacingOccurrences(of: "}", with: "")
                    if let member = staticMember(rest), !requirePublic || member.isPublic || scope.publicExtension {
                        add(member, owner: decl.name, chain: chain + [decl.name], file: file, into: &catalog)
                    }
                    if scope.isViewExtension, let name = modifierFunction(rest), !requirePublic || scope.publicExtension || rest.contains("public ") {
                        catalog.views.append(ViewEntry(name: ".\(name)()", kind: .modifier, file: file))
                    }
                }
            } else if var p = pending, code.contains("{") {
                p.level = before + 1
                stack.append(p)
                pending = nil
            } else if let member = staticMember(line) {
                let isPublic = member.isPublic || (innermost?.publicExtension ?? false)
                if !requirePublic || isPublic, let owner = innermost {
                    add(member, owner: owner.name, chain: chain, file: file, into: &catalog)
                }
            } else if let scope = innermost, scope.isViewExtension, let name = modifierFunction(line),
                      !requirePublic || line.contains("public ") || scope.publicExtension {
                catalog.views.append(ViewEntry(name: ".\(name)()", kind: .modifier, file: file))
            }
            stack.removeAll { $0.level > depth }
        }
    }

    // MARK: Declarations

    struct TypeDecl { var name: String; var isExtension: Bool; var isPublic: Bool; var viewKind: ViewEntry.Kind? }

    static func typeDeclaration(_ line: String) -> TypeDecl? {
        guard let m = firstMatch(typePattern, line) else { return nil }
        let modifiers = m[1] ?? ""
        let keyword = m[2] ?? ""
        let name = m[3] ?? ""
        let conformances = m[4] ?? ""
        let isPublic = modifiers.contains("public") || modifiers.contains("open")
        var kind: ViewEntry.Kind?
        if keyword == "struct" || keyword == "class" {
            let names = conformances.split(whereSeparator: { ",:<> {".contains($0) }).map { String($0) }
            if names.contains("View") { kind = .view }
            else if names.contains(where: { styleProtocols.contains($0) }) { kind = .style }
        }
        return TypeDecl(name: name, isExtension: keyword == "extension", isPublic: isPublic, viewKind: kind)
    }

    static let styleProtocols: Set<String> = ["ButtonStyle", "PrimitiveButtonStyle", "ToggleStyle", "LabelStyle", "ViewModifier",
                                              "TextFieldStyle", "GroupBoxStyle", "MenuStyle", "ProgressViewStyle", "DisclosureGroupStyle"]

    struct Member { var name: String; var type: String?; var value: String; var isPublic: Bool }

    static func staticMember(_ line: String) -> Member? {
        guard let m = firstMatch(memberPattern, line), let name = m[2], let value = m[4] else { return nil }
        let modifiers = m[1] ?? ""
        return Member(name: name, type: m[3], value: value.trimmingCharacters(in: CharacterSet(charactersIn: " ;")),
                      isPublic: modifiers.contains("public") || modifiers.contains("open"))
    }

    static func modifierFunction(_ line: String) -> String? {
        firstMatch(modifierPattern, line)?[1] ?? nil
    }

    static func add(_ m: Member, owner: String, chain: [String], file: String, into catalog: inout ComponentCatalog) {
        let name = (chain + [m.name]).joined(separator: ".")
        // `SwiftUI.Font.system(…)` reads the same as `Font.system(…)`.
        let type = (m.type ?? "").replacingOccurrences(of: "SwiftUI.", with: "")
        let value = m.value.replacingOccurrences(of: "SwiftUI.", with: "")
        if value.hasPrefix("Font.Weight") || value.hasPrefix("Font.Design") || type.hasPrefix("Font.") { return }
        let colorish = type == "Color" || type == "NSColor" || owner == "Color" || owner == "ShapeStyle"
            || value.hasPrefix("Color(") || value.hasPrefix("Color.")
        let fontish = type == "Font" || owner == "Font" || value.hasPrefix("Font.") || value.hasPrefix(".system(") || value.hasPrefix(".custom(")
        if colorish && !fontish {
            var token = ColorToken(name: name, light: nil, dark: nil, system: nil, file: file)
            parseColor(value, into: &token)
            catalog.colors.append(token)
        } else if fontish {
            catalog.fonts.append(parseFont(value, name: name, file: file))
        } else if let number = numericValue(value), numericTypes.contains(type) || type.isEmpty {
            let lower = m.name.lowercased()
            guard !["duration", "delay", "opacity", "animation", "alpha", "scale", "ratio", "count", "limit", "max", "min"]
                .contains(where: { lower.contains($0) }) else { return }
            catalog.sizes.append(SizeToken(name: name, value: number, file: file))
        }
    }

    static let numericTypes: Set<String> = ["CGFloat", "Double", "Float", "Int", ""]

    // MARK: Values

    static func parseColor(_ value: String, into token: inout ColorToken) {
        if let m = firstMatch(rgbPattern, value) {
            let r = fraction(m[1]), g = fraction(m[2]), b = fraction(m[3])
            if let r, let g, let b { token.light = ComponentRGBA(red: r, green: g, blue: b, alpha: fraction(m[4]) ?? 1) }
        } else if let m = firstMatch(whitePattern, value), let w = fraction(m[1]) {
            token.light = ComponentRGBA(red: w, green: w, blue: w, alpha: fraction(m[2]) ?? 1)
        } else if let m = firstMatch(hexPattern, value), let hex = m[1] {
            token.light = rgba(hex: hex)
        } else if let m = firstMatch(assetPattern, value), let asset = m[1] {
            token.system = "asset:" + asset
        } else if let m = firstMatch(assetSymbolPattern, value), let symbol = m[1] {
            // `Color(.brandPrimary)`: Xcode's symbol for a color set, or a system color such as `.systemBlue`.
            token.system = "symbol:" + symbol
        } else if let m = firstMatch(nsColorPattern, value), let system = m[1] {
            token.system = system
        } else if let m = firstMatch(systemPattern, value), let system = m[1] {
            token.system = system
        }
    }

    static func parseFont(_ value: String, name: String, file: String) -> FontToken {
        var f = FontToken(name: name, style: nil, size: nil, weight: nil, design: nil, family: nil, file: file)
        if let m = firstMatch(fontStylePattern, value) { f.style = m[1] }
        if let m = firstMatch(fontSizePattern, value), let s = m[1].flatMap(Double.init) { f.size = s }
        if let m = firstMatch(fontWeightPattern, value) { f.weight = m[1] ?? m[2] }
        else if value.contains(".bold()") { f.weight = "bold" }
        if let m = firstMatch(fontDesignPattern, value) { f.design = m[1] }
        if let m = firstMatch(fontFamilyPattern, value) { f.family = m[1] }
        return f
    }

    /// `0.4`, `102/255` or `102.0 / 255.0`.
    static func fraction(_ s: String?) -> Double? {
        guard let s = s?.replacingOccurrences(of: " ", with: ""), !s.isEmpty else { return nil }
        let parts = s.split(separator: "/")
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { return a / b }
        return Double(s)
    }

    static func numericValue(_ value: String) -> Double? {
        var v = value
        if let m = firstMatch(wrappedNumberPattern, v), let inner = m[1] { v = inner }
        return Double(v)
    }

    static func rgba(hex: String) -> ComponentRGBA? {
        var h = hex.lowercased()
        if h.hasPrefix("#") { h.removeFirst() }
        if h.hasPrefix("0x") { h.removeFirst(2) }
        guard h.count == 6 || h.count == 8, let n = UInt64(h, radix: 16) else { return nil }
        if h.count == 8 {
            return ComponentRGBA(red: Double((n >> 24) & 0xFF) / 255, green: Double((n >> 16) & 0xFF) / 255,
                                 blue: Double((n >> 8) & 0xFF) / 255, alpha: Double(n & 0xFF) / 255)
        }
        return ComponentRGBA(red: Double((n >> 16) & 0xFF) / 255, green: Double((n >> 8) & 0xFF) / 255, blue: Double(n & 0xFF) / 255)
    }

    // MARK: Asset catalogs

    /// Reads a color set's `Contents.json`: the any-appearance color and the dark one, when given.
    public static func colorSet(_ json: Data) -> (light: ComponentRGBA?, dark: ComponentRGBA?, system: String?) {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let colors = root["colors"] as? [[String: Any]] else { return (nil, nil, nil) }
        var light: ComponentRGBA?, dark: ComponentRGBA?, system: String?
        for entry in colors {
            guard let color = entry["color"] as? [String: Any] else { continue }
            let appearances = entry["appearances"] as? [[String: Any]] ?? []
            let isDark = appearances.contains { ($0["value"] as? String) == "dark" }
            let isOther = !isDark && !appearances.isEmpty
            if let reference = color["reference"] as? String { if !isDark && !isOther { system = reference }; continue }
            guard let c = color["components"] as? [String: Any] else { continue }
            func component(_ key: String) -> Double? {
                if let n = c[key] as? Double { return n > 1 ? n / 255 : n }
                guard let s = c[key] as? String else { return nil }
                if s.lowercased().hasPrefix("0x"), let n = UInt64(s.dropFirst(2), radix: 16) { return Double(n) / 255 }
                guard let n = Double(s) else { return nil }
                return s.contains(".") || n <= 1 ? n : n / 255
            }
            guard let r = component("red"), let g = component("green"), let b = component("blue") else { continue }
            let value = ComponentRGBA(red: r, green: g, blue: b, alpha: component("alpha") ?? 1)
            if isDark { dark = value } else if !isOther { light = value }
        }
        return (light, dark, system)
    }

    // MARK: Text helpers

    /// Drops a trailing `//` comment, keeping `//` inside strings (such as URLs).
    static func stripComment(_ line: String) -> String {
        var inString = false, previous: Character = " ", out = ""
        for ch in line {
            if ch == "\"" && previous != "\\" { inString.toggle() }
            if ch == "/" && previous == "/" && !inString { out.removeLast(); return out }
            out.append(ch)
            previous = ch
        }
        return out
    }

    static func stripStrings(_ line: String) -> String {
        stringPattern.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "\"\"")
    }

    static func firstMatch(_ re: NSRegularExpression, _ s: String) -> [String?]? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } }
    }

    static func re(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

    static let typePattern = re(#"^\s*((?:(?:public|open|internal|fileprivate|private|final|@\w+(?:\([^)]*\))?)\s+)*)(struct|class|enum|extension|actor)\s+([A-Za-z_][\w.]*)\s*(?:<[^>{]*>)?\s*(?::\s*([^{]*))?(?:where[^{]*)?\{?"#)
    static let memberPattern = re(#"^\s*((?:(?:public|open|internal|nonisolated|@\w+)\s+)*)static\s+(?:let|var)\s+(\w+)\s*(?::\s*([\w.]+))?\s*=\s*(.+?)\s*$"#)
    static let modifierPattern = re(#"func\s+(\w+)\s*\([^)]*\)\s*->\s*some\s+View"#)
    static let rgbPattern = re(#"Color\(\s*(?:\.\w+\s*,\s*)?red:\s*([0-9./ ]+?)\s*,\s*green:\s*([0-9./ ]+?)\s*,\s*blue:\s*([0-9./ ]+?)\s*(?:,\s*opacity:\s*([0-9./ ]+?)\s*)?\)"#)
    static let whitePattern = re(#"Color\(\s*(?:\.\w+\s*,\s*)?white:\s*([0-9./ ]+?)\s*(?:,\s*opacity:\s*([0-9./ ]+?)\s*)?\)"#)
    static let hexPattern = re(#"Color\(\s*hex:\s*"?(#?(?:0x)?[0-9A-Fa-f]{6,8})"?"#)
    static let assetPattern = re(#"Color\(\s*"([^"]+)""#)
    static let assetSymbolPattern = re(#"Color\(\s*\.(\w+)\s*\)"#)
    static let nsColorPattern = re(#"Color\(\s*nsColor:\s*(?:NSColor)?\.(\w+)"#)
    static let systemPattern = re(#"^(?:Color)?\.(red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|white|gray|black|clear|primary|secondary|accentColor)\b"#)
    static let fontStylePattern = re(#"\.(largeTitle|title3|title2|title|headline|subheadline|body|callout|footnote|caption2|caption)\b"#)
    static let fontSizePattern = re(#"size:\s*([0-9]+(?:\.[0-9]+)?)"#)
    static let fontWeightPattern = re(#"weight\(\.(\w+)\)|weight:\s*\.(\w+)"#)
    static let fontDesignPattern = re(#"design:\s*\.(\w+)"#)
    static let fontFamilyPattern = re(#"custom\(\s*"([^"]+)""#)
    static let wrappedNumberPattern = re(#"^(?:CGFloat|Double|Float)\(\s*(-?[0-9.]+)\s*\)$"#)
    static let stringPattern = re(#""(?:[^"\\]|\\.)*""#)
}

// MARK: - Values typed straight into views

/// Colors, font sizes and spacing written as literals in a view instead of taken from the components. Found with plain
/// text patterns, so it is free and runs on every `hatch ready`; it can miss or over-count a little, which is why it is a
/// note, never a failure.
public enum TypedValues {
    public enum Kind: String, CaseIterable, Sendable { case color, font, size
        public var plural: String { switch self { case .color: "colors"; case .font: "font sizes"; case .size: "sizes" } }
    }

    public struct Finding: Equatable, Sendable {
        public var kind: Kind
        public var file: String
        public var line: Int
        public var text: String
    }

    static let patterns: [(Kind, NSRegularExpression)] = [
        (.color, ComponentReader.re(#"\bColor\(\s*(?:\.\w+\s*,\s*)?(?:red|white|hue):"#)),
        (.color, ComponentReader.re(#"\bColor\(\s*hex:"#)),
        (.color, ComponentReader.re(#"\bNSColor\(\s*(?:srgbRed|red|calibratedRed|deviceRed|white|calibratedWhite|hex):"#)),
        (.color, ComponentReader.re(#"#colorLiteral\("#)),
        (.font, ComponentReader.re(#"\.system\(\s*size:\s*[0-9]"#)),
        (.font, ComponentReader.re(#"\.custom\(\s*"[^"]*"\s*,\s*size:\s*[0-9]"#)),
        (.font, ComponentReader.re(#"NSFont\.(?:systemFont|monospacedSystemFont|boldSystemFont)\(ofSize:\s*[0-9]"#)),
        (.size, ComponentReader.re(#"\.padding\(\s*(?:\.\w+\s*,\s*)?[1-9][0-9]*(?:\.[0-9]+)?\s*\)"#)),
        (.size, ComponentReader.re(#"cornerRadius:\s*[1-9]"#)),
        (.size, ComponentReader.re(#"\.cornerRadius\(\s*[1-9]"#)),
        (.size, ComponentReader.re(#"spacing:\s*[1-9]"#)),
    ]

    /// The kinds of typed-in value on one line, once each.
    public static func kinds(in line: String) -> [Kind] {
        // Most lines hold none of the words the patterns need; skip them before any pattern runs.
        guard line.contains("Color(") || line.contains("colorLiteral") || line.contains("size:") || line.contains("ofSize")
                || line.contains("padding(") || line.contains("adius") || line.contains("spacing:") else { return [] }
        let code = ComponentReader.stripComment(line)
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("*") else { return [] }
        let range = NSRange(code.startIndex..., in: code)
        var found: [Kind] = []
        for (kind, re) in patterns where !found.contains(kind) && re.firstMatch(in: code, range: range) != nil { found.append(kind) }
        return found
    }

    /// Counts by kind in a whole file. A quick check for the words skips most files without running a pattern.
    public static func count(in text: String) -> [Kind: Int] {
        guard text.contains("Color(") || text.contains("NSColor(") || text.contains("colorLiteral") || text.contains("size:")
                || text.contains("ofSize") || text.contains("padding(") || text.contains("adius") || text.contains("spacing:") else { return [:] }
        var out: [Kind: Int] = [:]
        for line in text.components(separatedBy: "\n") {
            for k in kinds(in: line) { out[k, default: 0] += 1 }
        }
        return out
    }

    /// The values themselves: colors as hex and sizes as numbers, with counts, so moving them can match each one to a
    /// name in the components (decision CO12). Font sizes are left out: a size alone does not say which style it is.
    public static func literals(in text: String) -> (colors: [String: Int], sizes: [Double: Int]) {
        var colors: [String: Int] = [:], sizes: [Double: Int] = [:]
        for line in text.components(separatedBy: "\n") {
            let kinds = kinds(in: line)
            guard !kinds.isEmpty else { continue }
            let code = ComponentReader.stripComment(line)
            if kinds.contains(.color), let start = code.range(of: "Color(") {
                var token = ColorToken(name: "", light: nil, dark: nil, system: nil, file: "")
                ComponentReader.parseColor(String(code[start.lowerBound...]), into: &token)
                if let hex = token.light?.hex { colors[hex, default: 0] += 1 }
            }
            if kinds.contains(.size) {
                let range = NSRange(code.startIndex..., in: code)
                for m in sizeValuePattern.matches(in: code, range: range) {
                    if let r = Range(m.range(at: 1), in: code), let v = Double(code[r]) { sizes[v, default: 0] += 1 }
                }
            }
        }
        return (colors, sizes)
    }

    static let sizeValuePattern = ComponentReader.re(#"(?:\.padding\(\s*(?:\.\w+\s*,\s*)?|cornerRadius:\s*|\.cornerRadius\(\s*|spacing:\s*)([1-9][0-9]*(?:\.[0-9]+)?)"#)

    /// The typed-in values on lines a change adds, from `git diff -U0` output. Files under `excluding` (the components
    /// folder, relative to the repository root) are skipped: that is where values belong.
    public static func inDiff(_ diff: String, excluding: String?) -> [Finding] {
        let skip = excluding.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var file: String?, lineNo = 0, out: [Finding] = []
        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("+++ ") {
                let path = String(line.dropFirst(4))
                file = path == "/dev/null" ? nil : (path.hasPrefix("b/") ? String(path.dropFirst(2)) : path)
                if let f = file, !f.hasSuffix(".swift") || (skip.map { f.hasPrefix($0) } ?? false) { file = nil }
            } else if line.hasPrefix("@@") {
                // @@ -12,3 +14,5 @@: added lines start at 14.
                if let plus = line.split(separator: " ").first(where: { $0.hasPrefix("+") }),
                   let start = Int(plus.dropFirst().split(separator: ",").first ?? "") { lineNo = start }
            } else if line.hasPrefix("+"), !line.hasPrefix("+++") {
                if let f = file {
                    let text = String(line.dropFirst())
                    for k in kinds(in: text) {
                        out.append(Finding(kind: k, file: f, line: lineNo, text: text.trimmingCharacters(in: .whitespaces)))
                    }
                }
                lineNo += 1
            }
        }
        return out
    }
}

// MARK: - Looking at an app's code

/// A folder that looks like it holds components, with what is in it.
public struct ComponentsCandidate: Equatable, Sendable {
    /// Relative to the app repository's root.
    public var path: String
    public var isPackage: Bool
    public var product: String?
    public var catalog: ComponentCatalog

    public init(path: String, isPackage: Bool, product: String?, catalog: ComponentCatalog) {
        self.path = path; self.isPackage = isPackage; self.product = product; self.catalog = catalog
    }

    public var config: ComponentsConfig { ComponentsConfig(path: path, product: isPackage ? product : nil) }

    /// "12 colors, 6 type styles, 3 sizes, 9 views".
    public var summary: String { ComponentsScan.describe(catalog) }

    var score: Int { catalog.colors.count * 2 + catalog.fonts.count * 2 + catalog.sizes.count + catalog.views.count + (isPackage ? 5 : 0) }
}

/// What Hatch finds in an app's clone: folders that look like components, and how many values are typed into views
/// elsewhere. Read from disk only; a large app takes a second or two, so callers run it off the main thread.
public struct ComponentsScan: Equatable, Sendable {
    public var candidates: [ComponentsCandidate]
    public var typed: [TypedValues.Kind: Int]
    /// Files with the most typed-in values, most first (relative paths).
    public var typedFiles: [(path: String, count: Int)]
    public var swiftFiles: Int
    /// Colors typed into views, by hex, with how often each appears (decision CO12).
    public var colorLiterals: [String: Int]
    /// Padding, spacing and corner radii typed into views, by value, with how often each appears.
    public var sizeLiterals: [Double: Int]

    public init(candidates: [ComponentsCandidate], typed: [TypedValues.Kind: Int], typedFiles: [(path: String, count: Int)], swiftFiles: Int,
                colorLiterals: [String: Int] = [:], sizeLiterals: [Double: Int] = [:]) {
        self.candidates = candidates; self.typed = typed; self.typedFiles = typedFiles; self.swiftFiles = swiftFiles
        self.colorLiterals = colorLiterals; self.sizeLiterals = sizeLiterals
    }

    public var typedTotal: Int { typed.values.reduce(0, +) }
    /// Few typed-in values: a new or small app, where one ticket starts the components. Otherwise they are moved over
    /// one kind at a time.
    public var isSmall: Bool { typedTotal < ComponentsScan.smallLimit }
    public static let smallLimit = 30

    public static func == (a: ComponentsScan, b: ComponentsScan) -> Bool {
        a.candidates == b.candidates && a.typed == b.typed && a.swiftFiles == b.swiftFiles
            && a.colorLiterals == b.colorLiterals && a.sizeLiterals == b.sizeLiterals
            && a.typedFiles.map(\.path) == b.typedFiles.map(\.path) && a.typedFiles.map(\.count) == b.typedFiles.map(\.count)
    }

    /// "142 colors, 87 font sizes and 310 sizes typed into views", or nil when there are none.
    public var typedSummary: String? {
        let parts = TypedValues.Kind.allCases.compactMap { k in typed[k].flatMap { $0 > 0 ? "\($0) \(k.plural)" : nil } }
        guard !parts.isEmpty else { return nil }
        return Self.join(parts)
    }

    static func describe(_ c: ComponentCatalog) -> String {
        var parts: [String] = []
        func add(_ n: Int, _ one: String, _ many: String) { if n > 0 { parts.append("\(n) \(n == 1 ? one : many)") } }
        add(c.colors.count, "color", "colors")
        add(c.fonts.count, "type style", "type styles")
        add(c.sizes.count, "size", "sizes")
        add(c.views.filter { $0.kind == .view }.count, "view", "views")
        add(c.views.filter { $0.kind != .view }.count, "style", "styles")
        return parts.isEmpty ? "Nothing found yet" : join(parts)
    }

    static func join(_ parts: [String]) -> String {
        parts.count < 2 ? parts.joined() : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }
}

public enum ComponentsScanner {
    static let skippedFolders: Set<String> = [".git", ".build", ".swiftpm", "DerivedData", "Pods", "Carthage", "node_modules",
                                              "build", "vendor", ".hatch", "worktrees", "xcuserdata", "SourcePackages", "checkouts"]

    /// Build output and downloaded dependencies: never the app's own code.
    static func skips(_ name: String) -> Bool {
        skippedFolders.contains(name) || name.hasPrefix("build-") || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcassets")
            || name.hasSuffix(".xcworkspace") || name.hasSuffix(".app")
    }
    /// Folder names that usually hold components: `DesignSystem`, `AcmeUI`, `Theme`, `Components`, `Styles`, `Tokens`.
    static let namePattern = ComponentReader.re(#"(?i:design ?system|components|theme|styles?|tokens|appearance)$|UI$|UIKit$"#)

    /// Looks through the app's clone. `excluding` is a components folder already chosen, left out of the typed-in count.
    public static func scan(appRoot: String, excluding: String? = nil) -> ComponentsScan {
        let root = URL(fileURLWithPath: appRoot).resolvingSymlinksInPath()
        let files = swiftFiles(under: root)
        var packageDirs: [String] = [], namedDirs: [String] = []
        // Folders: local packages (a Package.swift below the root) and folders named like components.
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in e {
                let name = url.lastPathComponent
                if skips(name) { e.skipDescendants(); continue }
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let rel = relative(url, to: root)
                if rel.split(separator: "/").count > 5 { e.skipDescendants(); continue }
                if rel.split(separator: "/").contains(where: { $0.hasSuffix("Tests") }) { continue }
                if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { packageDirs.append(rel) }
                else if namePattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil { namedDirs.append(rel) }
            }
        }
        var candidates: [ComponentsCandidate] = []
        for dir in packageDirs {
            let full = root.appendingPathComponent(dir).path
            let cat = catalog(at: full, isPackage: true)
            let named = namePattern.firstMatch(in: (dir as NSString).lastPathComponent, range: NSRange(location: 0, length: (dir as NSString).lastPathComponent.utf16.count)) != nil
            guard cat.tokenCount >= 2 || (named && !cat.isEmpty) else { continue }
            candidates.append(ComponentsCandidate(path: dir, isPackage: true, product: product(inPackageAt: full), catalog: cat))
        }
        // A named folder inside a package that is itself components is part of it; inside any other package (often
        // the app itself is one) it stands on its own.
        let accepted = candidates.map(\.path)
        for dir in namedDirs where !accepted.contains(where: { dir.hasPrefix($0 + "/") }) && !namedDirs.contains(where: { dir.hasPrefix($0 + "/") }) {
            let cat = catalog(at: root.appendingPathComponent(dir).path, isPackage: false)
            guard cat.tokenCount >= 2 || cat.views.count >= 2 else { continue }
            candidates.append(ComponentsCandidate(path: dir, isPackage: false, product: nil, catalog: cat))
        }
        candidates.sort { $0.score > $1.score }

        // Only the chosen folder (or the likeliest one) holds values by right; a second set's values count as typed in,
        // so they are not invisible (decision CO9).
        let skip = [excluding ?? candidates.first?.path].compactMap { $0 }.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var typed: [TypedValues.Kind: Int] = [:], perFile: [(String, Int)] = []
        var colors: [String: Int] = [:], sizes: [Double: Int] = [:]
        for url in files {
            let rel = relative(url, to: root)
            if skip.contains(where: { rel.hasPrefix($0) }) || rel.split(separator: "/").contains(where: { $0.hasSuffix("Tests") }) { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let counts = TypedValues.count(in: text)
            let n = counts.values.reduce(0, +)
            guard n > 0 else { continue }
            for (k, v) in counts { typed[k, default: 0] += v }
            perFile.append((rel, n))
            let found = TypedValues.literals(in: text)
            for (k, v) in found.colors { colors[k, default: 0] += v }
            for (k, v) in found.sizes { sizes[k, default: 0] += v }
        }
        perFile.sort { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
        return ComponentsScan(candidates: candidates, typed: typed, typedFiles: perFile.prefix(8).map { (path: $0.0, count: $0.1) }, swiftFiles: files.count,
                              colorLiterals: colors, sizeLiterals: sizes)
    }

    /// Everything in a components folder: tokens and views from its Swift files, colors from its asset catalogs.
    public static func catalog(at folder: String, isPackage: Bool) -> ComponentCatalog {
        let root = URL(fileURLWithPath: folder).resolvingSymlinksInPath()
        var cat = ComponentCatalog()
        for url in swiftFiles(under: root) {
            let rel = relative(url, to: root)
            if rel.split(separator: "/").contains(where: { $0.hasSuffix("Tests") }) || url.lastPathComponent == "Package.swift" { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            ComponentReader.read(text, file: rel, requirePublic: isPackage, into: &cat)
        }
        // Color sets: they fill in tokens that name them (`Color("Accent")`) and are listed on their own otherwise.
        var assets: [(name: String, file: String, light: ComponentRGBA?, dark: ComponentRGBA?, system: String?)] = []
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in e {
                if skippedFolders.contains(url.lastPathComponent) { e.skipDescendants(); continue }
                guard url.pathExtension == "colorset", let data = try? Data(contentsOf: url.appendingPathComponent("Contents.json")) else { continue }
                let v = ComponentReader.colorSet(data)
                assets.append((url.deletingPathExtension().lastPathComponent, relative(url, to: root), v.light, v.dark, v.system))
            }
        }
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        var used = Set<String>()
        for i in cat.colors.indices {
            guard let ref = cat.colors[i].system, let colon = ref.firstIndex(of: ":") else { continue }
            let name = String(ref[ref.index(after: colon)...])
            if let a = assets.first(where: { key($0.name) == key(name) }) {
                cat.colors[i].light = a.light; cat.colors[i].dark = a.dark; cat.colors[i].system = a.system
                used.insert(a.name)
            } else {
                // A named color set that is not in this folder; a dot name with no color set is a system color.
                cat.colors[i].system = ref.hasPrefix("symbol:") ? name : nil
            }
        }
        for a in assets where !used.contains(a.name) {
            cat.colors.append(ColorToken(name: a.name, light: a.light, dark: a.dark, system: a.system, file: a.file))
        }
        return cat
    }

    /// The first library a package offers, which is what the app and a Proposal import.
    static func product(inPackageAt folder: String) -> String? {
        guard let text = try? String(contentsOfFile: (folder as NSString).appendingPathComponent("Package.swift"), encoding: .utf8) else { return nil }
        let re = ComponentReader.re(#"\.library\(\s*name:\s*"([^"]+)""#)
        if let name = ComponentReader.firstMatch(re, text)?[1] ?? nil { return name }
        return ComponentReader.firstMatch(ComponentReader.re(#"\.target\(\s*name:\s*"([^"]+)""#), text)?[1] ?? nil
    }

    static func swiftFiles(under root: URL) -> [URL] {
        var out: [URL] = []
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in e {
            let name = url.lastPathComponent
            if skips(name) { e.skipDescendants(); continue }
            if url.pathExtension == "swift" { out.append(url) }
            if out.count >= 20_000 { break }
        }
        return out
    }

    static func relative(_ url: URL, to root: URL) -> String {
        let path = url.resolvingSymlinksInPath().path, base = root.path
        guard path.hasPrefix(base) else { return path }
        return String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

// MARK: - Conflicts

/// One name defined with different values, in two sets of components or twice in one (decision CO11).
public struct NameClash: Equatable, Sendable {
    public struct Value: Equatable, Sendable {
        /// The folder of the set, relative to the app's root, and the file inside it.
        public var folder: String
        public var file: String
        /// "#2B59C2", "Headline, semibold" or "12".
        public var value: String
    }
    public var name: String
    public var values: [Value]
}

/// A value typed into views and the name in the components it matches, exactly or nearly (decision CO12).
public struct ValueMatch: Equatable, Sendable {
    public var literal: String
    public var count: Int
    public var name: String?
    public var nameValue: String?
    public var exact: Bool
}

public enum ComponentConflicts {
    /// Names whose values differ, within the chosen set and between it and the others. Same value is not a clash.
    public static func clashes(chosen: ComponentsCandidate, others: [ComponentsCandidate]) -> [NameClash] {
        var byName: [String: [NameClash.Value]] = [:], order: [String] = []
        for set in [chosen] + others {
            for (name, file, value) in values(set.catalog) {
                if byName[name] == nil { order.append(name) }
                byName[name, default: []].append(NameClash.Value(folder: set.path, file: file, value: value))
            }
        }
        return order.compactMap { name in
            let vs = byName[name]!
            guard vs.count > 1, Set(vs.map(\.value)).count > 1 else { return nil }
            return NameClash(name: name, values: vs)
        }
    }

    static func values(_ c: ComponentCatalog) -> [(String, String, String)] {
        c.colors.map { t in (t.name, t.file, t.light.map { $0.hex + (t.dark.map { "/" + $0.hex } ?? "") } ?? t.system ?? "?") }
            + c.fonts.map { ($0.name, $0.file, $0.summary) }
            + c.sizes.map { ($0.name, $0.file, ComponentCatalog.number($0.value)) }
    }

    /// How often each name's last part (`.accent` for `Color.accent`) appears in the app's Swift files, to say which
    /// value most views already use. A text count: close enough to recommend, never used to decide by itself.
    public static func usage(of names: [String], appRoot: String) -> [String: Int] {
        let members = Dictionary(names.map { ($0, "." + ($0.split(separator: ".").last.map(String.init) ?? $0)) }, uniquingKeysWith: { a, _ in a })
        var out: [String: Int] = [:]
        for url in ComponentsScanner.swiftFiles(under: URL(fileURLWithPath: appRoot)) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (name, member) in members where text.contains(member) {
                out[name, default: 0] += text.components(separatedBy: member).count - 1
            }
        }
        return out
    }

    /// Typed-in colors matched to the components' colors: equal (replace without asking) or within a few steps of one
    /// (a merge the owner approves). Without components, near duplicates among the typed-in colors themselves.
    public static func colorMatches(_ literals: [String: Int], catalog: ComponentCatalog?) -> [ValueMatch] {
        let named = (catalog?.colors ?? []).compactMap { t in t.light.map { (t.name, $0) } }
        return matches(literals.compactMap { k, v in ComponentReader.rgba(hex: k).map { (k, $0, v) } }, named: named, near: { colorDistance($0, $1) < 0.03 }, show: { $0.hex })
    }

    public static func sizeMatches(_ literals: [Double: Int], catalog: ComponentCatalog?) -> [ValueMatch] {
        let named = (catalog?.sizes ?? []).map { ($0.name, $0.value) }
        return matches(literals.map { (ComponentCatalog.number($0.key), $0.key, $0.value) }, named: named,
                       near: { abs($0 - $1) <= max(1, 0.1 * max($0, $1)) && $0 != $1 }, show: { ComponentCatalog.number($0) })
    }

    static func matches<V: Equatable>(_ literals: [(String, V, Int)], named: [(String, V)], near: (V, V) -> Bool, show: (V) -> String) -> [ValueMatch] {
        let sorted = literals.sorted { $0.2 > $1.2 || ($0.2 == $1.2 && $0.0 < $1.0) }
        var out: [ValueMatch] = []
        for (i, lit) in sorted.enumerated() {
            if let n = named.first(where: { $0.1 == lit.1 }) {
                out.append(ValueMatch(literal: lit.0, count: lit.2, name: n.0, nameValue: show(n.1), exact: true))
            } else if let n = named.first(where: { near($0.1, lit.1) }) {
                out.append(ValueMatch(literal: lit.0, count: lit.2, name: n.0, nameValue: show(n.1), exact: false))
            } else if named.isEmpty, let more = sorted[..<i].first(where: { near($0.1, lit.1) }) {
                // No names yet: a rarer value next to a more used one is probably meant to be the same.
                out.append(ValueMatch(literal: lit.0, count: lit.2, name: nil, nameValue: more.0, exact: false))
            }
        }
        return out
    }

    static func colorDistance(_ a: ComponentRGBA, _ b: ComponentRGBA) -> Double {
        let d = [a.red - b.red, a.green - b.green, a.blue - b.blue, a.alpha - b.alpha]
        return d.map { $0 * $0 }.reduce(0, +).squareRoot()
    }
}

// MARK: - The tickets that start or grow the components

/// The draft tickets Hatch adds for the components (decisions CO3, CO9 to CO12). They are drafts: the owner reads and
/// submits them, so nothing starts working on the app without a yes. All carry the area `Components`, which the
/// Components page and a Decide session filtered to components look for.
public enum ComponentsSetup {
    public struct Draft: Equatable, Sendable {
        public var type: TicketType
        public var title: String
        public var body: String
        /// A Question Hatch has already prepared: its options, so the owner can choose without an agent (CO11).
        public var options: [QuestionOption] = []
        public var area: String? = ComponentsSetup.area
        public init(type: TicketType, title: String, body: String, options: [QuestionOption] = []) {
            self.type = type; self.title = title; self.body = body; self.options = options
        }
    }

    public static let area = "Components"
    public static let startTitle = "Start the components package"

    /// One Tweak for a new or small app; for a larger one a Theme holding the start and one Tweak per kind of value.
    /// `existing` names component folders already in the app, so the agent reuses them instead of adding another set (CO10).
    public static func drafts(appName: String, config: ComponentsConfig, scan: ComponentsScan?, existing: [String] = []) -> [Draft] {
        let product = config.product ?? (config.path as NSString).lastPathComponent
        var start = """
            Make a local Swift package at `\(config.path)` inside the app repository, with one library, `\(product)`, and add it to the app as a local package.

            Put in it:
            - Colors with names that say what they are for (`surface`, `accent`, `textSecondary`), as `public extension Color` statics. Map them to the system colors the app uses today, or to Apple's semantic colors where it has none, so the look does not change yet.
            - Type as `public extension Font` statics mapped to system text styles (`.headline`, `.body`), so Dynamic Type keeps working.
            - A spacing and corner-radius scale as `public enum Spacing` and `public enum Radius` with `CGFloat` statics.
            - Two or three views the app already repeats, if there are any (a card, a primary button).

            Keep it small: only what \(appName) uses. Do not change screens in this ticket beyond importing the package.

            """
        if !existing.isEmpty {
            start += "The app already has components in \(existing.map { "`\($0)`" }.joined(separator: ", ")). Start from what is there: move it into the package instead of writing a second set.\n\n"
        }
        if let scan, !scan.isSmall, let summary = scan.typedSummary {
            start += "The app types \(summary) straight into views today. Name the values used most often so the next tickets can move them over.\n"
        }
        guard let scan, !scan.isSmall else { return [Draft(type: .tweak, title: startTitle, body: start)] }

        let drafts = [Draft(type: .theme, title: "Components for \(appName)",
                            body: "Move \(appName)'s colors, type and sizes into `\(config.path)` one kind at a time, so no single change touches every screen. Submit the start first; the others build on it. After these, views that still type values in move over when a ticket touches them.\n"),
                      Draft(type: .tweak, title: startTitle, body: start)]
        return drafts + moveDrafts(config: config, scan: scan, catalog: nil)
    }

    /// One Tweak per kind of value typed into views, to move them into the components. With the components' catalog,
    /// each ticket lists the values that equal a name (replace them) and the ones close to a name (propose a merge in
    /// the plan); without it, the typed-in values that look meant to be the same (decision CO12).
    public static func moveDrafts(config: ComponentsConfig, scan: ComponentsScan, catalog: ComponentCatalog? = nil) -> [Draft] {
        let product = config.product ?? (config.path as NSString).lastPathComponent
        var drafts: [Draft] = []
        let files = scan.typedFiles.prefix(5).map { "`\($0.path)` (\($0.count))" }.joined(separator: ", ")
        for kind in TypedValues.Kind.allCases {
            guard let n = scan.typed[kind], n > 0 else { continue }
            let what: String
            var matches: [ValueMatch] = []
            switch kind {
            case .color: what = "colors (`Color(red:…)`, `Color(hex:)`, `NSColor(…)`)"; matches = ComponentConflicts.colorMatches(scan.colorLiterals, catalog: catalog)
            case .font: what = "font sizes (`.system(size:)`, `.custom(_:size:)`)"
            case .size: what = "padding, spacing and corner radii written as numbers"; matches = ComponentConflicts.sizeMatches(scan.sizeLiterals, catalog: catalog)
            }
            var body = """
                Replace the \(n) \(what) in views with names from `\(product)`. Add a name when one is missing; reuse one when two values are meant to be the same.

                Work area by area. If it is more than about 30 files, do the most used values first and say in a note what is left.

                """
            if !files.isEmpty { body += "Most of them are in \(files).\n\n" }
            let exact = matches.filter(\.exact).prefix(8), near = matches.filter { !$0.exact }.prefix(8)
            if !exact.isEmpty {
                body += "Equal to a name, replace without asking: " + exact.map { "\($0.literal) → \($0.name!) (\($0.count))" }.joined(separator: ", ") + ".\n\n"
            }
            if !near.isEmpty {
                body += "Close to " + (near.first?.name == nil ? "a more used value" : "a name") + ", probably meant to be the same: "
                    + near.map { "\($0.literal) (\($0.count)) ~ \($0.name ?? $0.nameValue ?? "")" + ($0.name != nil ? " \($0.nameValue ?? "")" : "") }.joined(separator: ", ")
                    + ". List the merges you propose in your plan; the owner approves them before you change anything, because a merge changes how the app looks.\n\n"
            }
            body += "Otherwise the look must not change; check the screens you touched in light and dark.\n"
            drafts.append(Draft(type: .tweak, title: "Move typed-in \(kind.plural) into components", body: body))
        }
        return drafts
    }

    /// Merging a second set of components into the chosen one (decision CO9).
    public static func mergeDraft(into chosen: ComponentsCandidate, from other: ComponentsCandidate) -> Draft {
        Draft(type: .tweak, title: "Merge \((other.path as NSString).lastPathComponent) into \((chosen.path as NSString).lastPathComponent)", body: """
            `\(other.path)` is a second set of components (\(other.summary)) next to `\(chosen.path)`, the one the project uses. Move what it has into `\(chosen.path)` and change the views that use it.

            Where both define a name with different values, follow the decision on the Question about them; do not choose yourself. Reuse a name when the values are equal. Delete `\(other.path)` when nothing uses it any more.

            """)
    }

    /// The Question about names with two values, prepared by Hatch with its options, so it needs no agent (CO11).
    /// Recommended: keep the chosen set's values, the ones Proposals import.
    public static func clashQuestion(_ clashes: [NameClash], chosen: ComponentsCandidate, usage: [String: Int]) -> Draft? {
        guard !clashes.isEmpty else { return nil }
        let names = clashes.count == 1 ? "`\(clashes[0].name)`" : "\(clashes.count) names"
        var body = "These names have different values in the app's components. Only you know which is right.\n\n"
        for c in clashes.prefix(12) {
            body += "- `\(c.name)`" + (usage[c.name].map { " (used about \($0) times)" } ?? "") + ": "
                + c.values.map { "\($0.value) in `\($0.folder)`" }.joined(separator: ", ") + "\n"
        }
        if clashes.count > 12 { body += "- and \(clashes.count - 12) more\n" }
        let chosenName = (chosen.path as NSString).lastPathComponent
        let options = [
            QuestionOption(key: "A", title: "Keep \(chosenName)'s values", detail: "The other values change to match", recommended: true,
                           why: "\(chosenName) is the set the project uses and Proposals import; its values are what most new work will see.",
                           gain: "One value per name, matching the package", cost: "Views that used the other values change slightly"),
            QuestionOption(key: "B", title: "Keep the other set's values", detail: "\(chosenName) changes to match",
                           gain: "Views that use the other set do not change", cost: "Everything built on \(chosenName) changes slightly"),
            QuestionOption(key: "C", title: "Keep both, rename the other set's", detail: "Both values stay under different names",
                           gain: "Nothing changes now", cost: "Two names that look alike; the choice comes back later"),
        ]
        var draft = Draft(type: .question, title: "Two values for \(names)", body: body, options: options)
        draft.area = area
        return draft
    }
}
