import Foundation

// Rules (decision NF4): what roles cannot say. Composition (menu icons, dividers), wording (Title Case, the ellipsis),
// placement (every toolbar command also in the menu bar) and usage (system colours, standard spacing). Each kind has
// Apple's default and the page that states it; most are checked for free in the Swift text, the rest are free text that
// agents and Iris read. Nothing here calls a model.

/// A kind of rule Hatch knows: its values, Apple's choice, where that comes from, and whether Hatch can check it.
public struct ComponentRuleKind: Sendable, Identifiable {
    public var id: String
    public var title: String
    /// Values and what each says, in order.
    public var values: [(id: String, says: String)]
    /// Apple's choice, when Apple states one.
    public var appleDefault: String?
    public var sources: [String]
    /// Said when Apple's guidance is not about macOS, or the pages disagree.
    public var caveat: String?
    public var checked: Bool

    public func says(_ value: String) -> String { values.first { $0.id == value }?.says ?? value }

    public static func named(_ id: String) -> ComponentRuleKind? { catalog.first { $0.id == id } }

    public static let catalog: [ComponentRuleKind] = [
        ComponentRuleKind(id: "menuIcons", title: "Icons in menus",
                          values: [("allOrNoneInGroup", "Icons sparingly: every item in a group has one, or none does."),
                                   ("never", "No icons in menus."), ("always", "Every menu item has an icon.")],
                          appleDefault: "allOrNoneInGroup", sources: ["hig-menus", "liquid-glass"], checked: true),
        ComponentRuleKind(id: "menuDividers", title: "Dividers in menus",
                          values: [("betweenGroups", "Related items are grouped and groups are separated by a divider."), ("off", "No rule.")],
                          appleDefault: "betweenGroups", sources: ["hig-menus"], checked: true),
        ComponentRuleKind(id: "contextMenuLength", title: "Short context menus",
                          values: [("short", "Context menus stay short: about three groups at most."), ("off", "No rule.")],
                          appleDefault: "short", sources: ["hig-context-menus", "hig-menus"], checked: true),
        ComponentRuleKind(id: "contextMenuShortcuts", title: "Shortcuts in context menus",
                          values: [("hidden", "Context menus show no keyboard shortcuts."), ("shown", "Context menu items show their shortcuts.")],
                          appleDefault: "hidden", sources: ["hig-context-menus"], checked: true),
        ComponentRuleKind(id: "destructiveLast", title: "Destructive items last",
                          values: [("last", "Destructive menu items come last, after a divider."), ("off", "No rule.")],
                          appleDefault: nil, sources: ["hig-context-menus"],
                          caveat: "Apple states this for iOS, iPadOS and visionOS; for macOS it is the app's choice.", checked: true),
        ComponentRuleKind(id: "titleCase", title: "Capitalization",
                          values: [("titleCase", "Buttons and menu items use title-style capitalization (Open Recent, Show All)."),
                                   ("sentenceCase", "Buttons and menu items use sentence case."), ("off", "No rule.")],
                          appleDefault: "titleCase", sources: ["hig-menus", "hig-buttons", "hig-alerts"],
                          caveat: "Alert buttons are left out: Apple's Alerts page asks for sentence case there, its Buttons page for title case.", checked: true),
        ComponentRuleKind(id: "ellipsis", title: "Ellipsis",
                          values: [("character", "An item that needs more input ends with the ellipsis character (…), never three periods."), ("off", "No rule.")],
                          appleDefault: "character", sources: ["hig-menus"], checked: true),
        ComponentRuleKind(id: "toolbarInMenuBar", title: "Toolbar commands in the menu bar",
                          values: [("required", "Every toolbar command is also a command in the menu bar."), ("off", "No rule.")],
                          appleDefault: "required", sources: ["hig-toolbars", "hig-menu-bar"], checked: true),
        ComponentRuleKind(id: "noBarBackgrounds", title: "No custom bar backgrounds",
                          values: [("required", "No custom backgrounds on toolbars, sidebars, sheets or popovers: macOS gives them Liquid Glass."), ("off", "No rule.")],
                          appleDefault: "required", sources: ["liquid-glass", "hig-sheets"], checked: true),
        ComponentRuleKind(id: "systemColors", title: "System colours",
                          values: [("required", "Colours are system colours or named ones in the components, never typed in."), ("off", "No rule.")],
                          appleDefault: "required", sources: ["hig-color"], checked: true),
        ComponentRuleKind(id: "standardSpacing", title: "Standard spacing",
                          values: [("required", "Spacing is the system's (padding(), stacks' defaults) or a named value, never a number typed in."), ("off", "No rule.")],
                          appleDefault: "required", sources: ["hig-layout", "swiftui-padding"], checked: true),
        ComponentRuleKind(id: "note", title: "Note", values: [("text", "A rule in words, for agents and Iris; Hatch does not check it.")],
                          appleDefault: nil, sources: [], checked: false),
    ]
}

/// One rule in a system: a kind, its value, and the owner's decision.
public struct ComponentRule: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: String
    public var value: String
    /// For a note, the rule in words; otherwise what the value says, kept so agents can read it without Hatch.
    public var text: String
    public var status: ComponentRole.Status
    public var decision: String?
    /// Becomes a setting in the app (NF5); the check accepts either way until then.
    public var configurable: Bool

    public init(id: String, kind: String, value: String, text: String, status: ComponentRole.Status = .provisional,
                decision: String? = nil, configurable: Bool = false) {
        self.id = id; self.kind = kind; self.value = value; self.text = text; self.status = status
        self.decision = decision; self.configurable = configurable
    }

    public var info: ComponentRuleKind? { ComponentRuleKind.named(kind) }
    public var isOff: Bool { value == "off" }
    /// True when the value is Apple's own.
    public var isApple: Bool { info?.appleDefault == value }

    /// Apple's choice for every kind that has one (the templates start here).
    public static var appleDefaults: [ComponentRule] {
        ComponentRuleKind.catalog.compactMap { k in
            let value = k.appleDefault ?? (k.values.contains { $0.id == "off" } ? "off" : nil)
            guard let value, k.id != "note" else { return nil }
            return ComponentRule(id: k.id, kind: k.id, value: value, text: k.says(value))
        }
    }
}

// MARK: - Checking the rules

public enum ComponentRuleCheck {
    /// A menu as written: its items in order, with dividers.
    struct MenuItem { var title: String?; var hasIcon: Bool; var destructive: Bool; var shortcut: Bool; var divider: Bool; var line: Int }
    struct Menu { var file: String; var line: Int; var context: Bool; var commands: Bool; var items: [MenuItem] }

    /// Findings for every rule that is on and checkable. `files` are the app's Swift files, as the inventory read them.
    public static func findings(files: [(path: String, text: String)], uses: [ComponentInventory.Use], system: ComponentSystem) -> [ComponentFinding] {
        let rules = Dictionary(system.rules.map { ($0.kind, $0) }, uniquingKeysWith: { a, _ in a })
        func on(_ kind: String) -> ComponentRule? { rules[kind].flatMap { $0.isOff || $0.configurable ? nil : $0 } }
        var out: [ComponentFinding] = []
        func add(_ rule: ComponentRule, _ file: String, _ line: Int, _ message: String, element: String = "button") {
            out.append(ComponentFinding(kind: .rule, element: element, place: nil, role: rule.id, file: file, line: line, look: "", message: message))
        }

        var menus: [Menu] = [], commandTitles = Set<String>()
        for (path, text) in files where text.contains("Menu") || text.contains("contextMenu") || text.contains("Command") || text.contains("toolbar") {
            let s = SwiftStructure(text)
            for m in s.menus(file: path) {
                menus.append(m)
                if m.commands { for item in m.items { if let t = item.title { commandTitles.insert(normalized(t)) } } }
            }
            if let r = on("noBarBackgrounds") {
                for (i, line) in text.components(separatedBy: "\n").enumerated() {
                    let code = ComponentReader.stripComment(line)
                    if code.contains(".toolbarBackground(") && !code.contains(".hidden") || code.contains(".presentationBackground(") || code.contains("NSVisualEffectView") {
                        add(r, path, i + 1, "A custom bar or sheet background: macOS gives toolbars, sidebars, sheets and popovers Liquid Glass; remove it.", element: "page")
                    }
                }
            }
            if on("systemColors") != nil || on("standardSpacing") != nil {
                for (i, line) in text.components(separatedBy: "\n").enumerated() {
                    for kind in TypedValues.kinds(in: line) {
                        if kind == .color, let r = on("systemColors") { add(r, path, i + 1, "A colour typed in: use a system colour or a named one.", element: "page") }
                        if kind == .size, let r = on("standardSpacing"), line.contains("padding(") || line.contains("spacing:") {
                            add(r, path, i + 1, "A spacing number typed in: use the system's spacing (padding(), a stack's default) or a named value.", element: "page")
                        }
                    }
                }
            }
        }

        for m in menus {
            let groups = m.items.split { $0.divider }.map(Array.init)
            if let r = on("menuIcons") {
                for g in groups where g.count > 1 {
                    let icons = g.filter(\.hasIcon).count
                    switch r.value {
                    case "allOrNoneInGroup" where icons > 0 && icons < g.count:
                        add(r, m.file, g.first!.line, "\(icons) of \(g.count) items in this menu group have an icon: give every item in the group one, or none.")
                    case "never" where icons > 0:
                        add(r, m.file, g.first { $0.hasIcon }!.line, "Menu items with icons; the rule is no icons in menus.")
                    case "always" where icons < g.count:
                        add(r, m.file, g.first { !$0.hasIcon }!.line, "Menu items without icons; the rule is an icon on every item.")
                    default: break
                    }
                }
            }
            let real = m.items.filter { !$0.divider }
            if let r = on("menuDividers"), real.count >= 7, groups.count == 1, !m.commands {
                add(r, m.file, m.line, "\(real.count) items with no divider: group related items and separate the groups.")
            }
            if let r = on("contextMenuLength"), m.context, groups.count > 3 || real.count > 12 {
                add(r, m.file, m.line, "A context menu with \(groups.count) groups and \(real.count) items: keep context menus short, about three groups.")
            }
            if let r = on("contextMenuShortcuts"), r.value == "hidden", m.context, let item = real.first(where: \.shortcut) {
                add(r, m.file, item.line, "A keyboard shortcut on a context menu item: context menus show none.")
            }
            if let r = on("destructiveLast"), let i = real.lastIndex(where: \.destructive), i < real.count - 1 {
                add(r, m.file, real[i].line, "A destructive item is not last in its menu.")
            }
        }

        // Wording: every literal button and menu title.
        for u in uses where u.place != "alert" && (u.element == "button" || u.element == "menu") {
            guard let title = u.title else { continue }
            if let r = on("ellipsis"), title.contains("...") {
                add(r, u.file, u.line, "\"\(title)\" uses three periods: write the ellipsis character (…).", element: u.element)
            }
            if let r = on("titleCase"), let bad = capitalizationProblem(title, rule: r.value) {
                add(r, u.file, u.line, "\"\(title)\": \(bad)", element: u.element)
            }
        }

        // Every toolbar command also in the menu bar.
        if let r = on("toolbarInMenuBar") {
            for u in uses where u.place == "toolbar" && u.element == "button" {
                guard let t = u.title, !commandTitles.contains(normalized(t)) else { continue }
                add(r, u.file, u.line, "\"\(t)\" is in the toolbar but not in the menu bar's commands.")
            }
        }
        return out.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
    }

    static func normalized(_ title: String) -> String {
        title.lowercased().replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "").trimmingCharacters(in: .whitespaces)
    }

    static let smallWords: Set<String> = ["a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "of", "off", "on", "onto",
                                         "or", "the", "to", "up", "via", "vs", "with", "nor", "per", "so", "yet"]

    /// What is wrong with a title's capitalization, or nil. Titles with code, numbers only or interpolation are skipped.
    public static func capitalizationProblem(_ title: String, rule: String) -> String? {
        let words = title.split(separator: " ").map(String.init)
        guard words.count >= 2, !title.contains("\\("), !title.contains("_"), title.first?.isLetter == true else { return nil }
        let candidates = words.enumerated().filter { i, w in
            guard let f = w.first, f.isLetter, w.count > 1, w.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" || $0 == "…" || $0 == "." }) else { return false }
            return !(i > 0 && i < words.count - 1 && smallWords.contains(w.lowercased()))
        }
        switch rule {
        case "titleCase":
            let low = candidates.filter { $0.1.first!.isLowercase }.map(\.1)
            return low.isEmpty ? nil : "use title-style capitalization (\(low.joined(separator: ", ")))."
        case "sentenceCase":
            let up = candidates.dropFirst().filter { $0.1.first!.isUppercase && $0.1.dropFirst().allSatisfy(\.isLowercase) }.map(\.1)
            return up.isEmpty ? nil : "use sentence case (\(up.joined(separator: ", ")))."
        default: return nil
        }
    }
}

extension SwiftStructure {
    /// Menus in this file: a Menu's content, a context menu, the app's command menus. Items are flattened through `if`,
    /// `Group` and `Section`; a `ForEach` counts as one item.
    func menus(file: String) -> [ComponentRuleCheck.Menu] {
        var out: [ComponentRuleCheck.Menu] = []
        for brace in braceOpens {
            guard let o = owner(ofBrace: brace) else { continue }
            let context = o.dotted && o.name == "contextMenu"
            let commands = (o.dotted && o.name == "commands") || (!o.dotted && ["CommandMenu", "CommandGroup"].contains(o.name))
            let menu = !o.dotted && o.name == "Menu" && (o.label == nil || o.label == "content")
            guard context || commands || menu else { continue }
            out.append(ComponentRuleCheck.Menu(file: file, line: line(of: brace), context: context, commands: commands, items: menuItems(in: brace)))
        }
        return out
    }

    func menuItems(in brace: Int) -> [ComponentRuleCheck.MenuItem] {
        guard partner[brace] > brace else { return [] }
        var items: [ComponentRuleCheck.MenuItem] = []
        var i = brace + 1
        let close = partner[brace]
        while i < close {
            let c = b[i]
            if c == UInt8(ascii: "("), partner[i] > i { i = partner[i] + 1; continue }
            if c == UInt8(ascii: "{"), partner[i] > i {
                // A plain block (an `if` body, a Group): its items count as this menu's.
                items += menuItems(in: i); i = partner[i] + 1; continue
            }
            guard Self.isIdentStart(c), !Self.isIdent(b[i - 1]), b[i - 1] != UInt8(ascii: "."), let id = identifier(startingAt: i) else { i += 1; continue }
            switch id.name {
            case "Divider":
                items.append(.init(title: nil, hasIcon: false, destructive: false, shortcut: false, divider: true, line: line(of: i)))
                i = id.end
            case "Button", "Toggle", "Picker", "Menu", "Link", "ShareLink":
                var p = skipSpace(id.end, newlines: false), args = "", rawArgs = ""
                if p < b.count, b[p] == UInt8(ascii: "("), partner[p] > p { args = text(p + 1, partner[p]); rawArgs = rawText(p + 1, partner[p]); p = partner[p] + 1 }
                var closures = ""
                let t = skipSpace(p, newlines: false)
                if t < b.count, b[t] == UInt8(ascii: "{"), partner[t] > t { closures += text(t + 1, partner[t]); p = partner[t] + 1 }
                let after = chain(after: p)
                for cl in after.closures where partner[cl.open] > cl.open { closures += text(cl.open + 1, partner[cl.open]) }
                let icon = args.contains("systemImage:") || args.contains("image:") || closures.contains("Label(") || closures.contains("Image(")
                items.append(.init(title: Self.firstLiteral(rawArgs), hasIcon: icon, destructive: args.contains(".destructive"),
                                   shortcut: after.modifiers.contains { $0.name == "keyboardShortcut" }, divider: false, line: line(of: i)))
                i = max(after.end, id.end)
            case "ForEach":
                items.append(.init(title: nil, hasIcon: false, destructive: false, shortcut: false, divider: false, line: line(of: i)))
                var p = skipSpace(id.end, newlines: false)
                if p < b.count, b[p] == UInt8(ascii: "("), partner[p] > p { p = partner[p] + 1 }
                let t = skipSpace(p, newlines: false)
                i = t < b.count && b[t] == UInt8(ascii: "{") && partner[t] > t ? partner[t] + 1 : id.end
            default:
                i = id.end
            }
        }
        return items
    }

    /// The text of the first string literal in a range of the original source (`"Rename…"` → `Rename…`).
    static func firstLiteral(_ raw: String) -> String? {
        guard let open = raw.firstIndex(of: "\""), raw[raw.index(after: open)...].first != "\"" else { return nil }
        let rest = raw[raw.index(after: open)...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        let value = String(rest[..<close])
        return value.isEmpty ? nil : value
    }
}
