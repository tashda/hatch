import Foundation

// The components as rules (decisions DS1 to DS12, design-review/components-designer.md). Foundations are values named by
// meaning, elements are the kinds of control, places are where an element sits, and a role is one element in one place
// for one purpose, with when to use it and when not. The role table (element × place × importance → role) is what filing,
// briefs and `hatch ready` check against, because a button is not just a button. The system lives in the notebook as
// `components/system.json`, written only by Hatch (DS2). Nothing here calls a model.

/// A project's design system: the agreed baseline and what is still provisional.
public struct ComponentSystem: Codable, Equatable, Sendable {
    /// Where it lives in the notebook (DS2).
    public static let notebookPath = "components/system.json"
    /// The readable copy for agents and people, generated from the system file.
    public static let readmePath = "components/README.md"
    public static let currentFormat = 1

    public var format: Int
    /// The app's name, for the README.
    public var name: String
    /// The baseline version. A redesign drafts the next one; accepting it makes that the baseline.
    public var version: Int
    /// The template it started from, when it did (DS6).
    public var template: String?
    public var foundations: [ComponentFoundation]
    /// Places beyond the standard ones (DS5: more as data).
    public var places: [ComponentPlace]
    public var roles: [ComponentRole]
    /// What the owner still has to decide: looks to pick at setup, mismatches found later (DS4, DS7). Answered in the
    /// Components Designer or with `hatch components answer`; each answer changes the system and leaves the list.
    public var questions: [ComponentQuestion]
    /// The oldest macOS the app runs on. macOS 27 is the reference (glass styles and the rest); generated code falls
    /// back for anything older.
    public var minimumMacOS: String

    public static let referenceMacOS = "27.0"

    public init(name: String, version: Int = 1, template: String? = nil, foundations: [ComponentFoundation] = [],
                places: [ComponentPlace] = [], roles: [ComponentRole] = [], questions: [ComponentQuestion] = [],
                minimumMacOS: String = ComponentSystem.referenceMacOS) {
        self.format = Self.currentFormat; self.name = name; self.version = version; self.template = template
        self.foundations = foundations; self.places = places; self.roles = roles; self.questions = questions
        self.minimumMacOS = minimumMacOS
    }

    private enum CodingKeys: String, CodingKey { case format, name, version, template, foundations, places, roles, questions, minimumMacOS }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Int.self, forKey: .format) ?? Self.currentFormat
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        template = try c.decodeIfPresent(String.self, forKey: .template)
        foundations = try c.decodeIfPresent([ComponentFoundation].self, forKey: .foundations) ?? []
        places = try c.decodeIfPresent([ComponentPlace].self, forKey: .places) ?? []
        roles = try c.decodeIfPresent([ComponentRole].self, forKey: .roles) ?? []
        questions = try c.decodeIfPresent([ComponentQuestion].self, forKey: .questions) ?? []
        minimumMacOS = try c.decodeIfPresent(String.self, forKey: .minimumMacOS) ?? Self.referenceMacOS
    }

    // MARK: Reading and writing

    public static func load(from url: URL) throws -> ComponentSystem {
        try JSONDecoder().decode(ComponentSystem.self, from: Data(contentsOf: url))
    }

    /// The system file in a notebook folder, or nil when there is none yet.
    public static func load(notebook folder: String) throws -> ComponentSystem? {
        let url = URL(fileURLWithPath: folder).appendingPathComponent(notebookPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try load(from: url)
    }

    /// Writes the system file and its README into a notebook folder. Refuses a system with problems, so nothing
    /// broken reaches the agents. Committing is the caller's (HatchGit), so the core stays free of git.
    public func write(notebook folder: String) throws {
        let problems = problems()
        guard problems.isEmpty else { throw StoreError.invalid("The system would have problems: " + problems.joined(separator: " ")) }
        let base = URL(fileURLWithPath: folder)
        let file = base.appendingPathComponent(Self.notebookPath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: file, options: .atomic)
        try Data(readme().utf8).write(to: base.appendingPathComponent(Self.readmePath), options: .atomic)
    }

    /// Sorted keys and a final newline, so the same system always writes the same bytes and diffs stay small.
    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self) + Data("\n".utf8)
    }

    // MARK: Lookups

    /// The standard places and this system's own, in that order.
    public var allPlaces: [ComponentPlace] { ComponentPlace.standard + places.filter { p in !ComponentPlace.standard.contains { $0.id == p.id } } }

    /// The macOS version as a number for comparisons (`26.4` → 26.4).
    public var minimumMacOSNumber: Double { Double(minimumMacOS.split(separator: ".").prefix(2).joined(separator: ".")) ?? 27 }

    public func place(_ id: String) -> ComponentPlace? { allPlaces.first { $0.id == id } }
    public func role(_ id: String) -> ComponentRole? { roles.first { $0.id == id } }
    public func foundation(_ id: String) -> ComponentFoundation? { foundations.first { $0.id == id } }

    /// The role for an element in a place at an importance: one cell of the role table. Nil means not decided yet, which
    /// is a question for the owner, never a licence to invent a look.
    public func role(element: String, place: String, importance: ComponentRole.Importance) -> ComponentRole? {
        roles.first { $0.element == element && $0.importance == importance && $0.places.contains(place) }
    }

    /// The roles of one element, in the order the system lists them.
    public func roles(of element: String) -> [ComponentRole] { roles.filter { $0.element == element } }

    /// The elements this system has roles for, in catalog order, then any it names that the catalog lacks.
    public var elementsUsed: [String] {
        let used = Set(roles.map(\.element))
        let known = ComponentElement.catalog.map(\.id).filter(used.contains)
        return known + used.subtracting(known).sorted()
    }

    /// One element's role table: the places its roles use (in place order) down, importances across.
    public func matrix(element: String) -> (places: [ComponentPlace], importances: [ComponentRole.Importance], cells: [[ComponentRole?]]) {
        let mine = roles(of: element)
        let placeIds = Set(mine.flatMap(\.places))
        let places = allPlaces.filter { placeIds.contains($0.id) }
        let importances = ComponentRole.Importance.allCases.filter { i in mine.contains { $0.importance == i } }
        let cells = places.map { p in importances.map { i in role(element: element, place: p.id, importance: i) } }
        return (places, importances, cells)
    }

    public var counts: (agreed: Int, provisional: Int, inRedesign: Int) {
        (roles.filter { $0.status == .agreed }.count, roles.filter { $0.status == .provisional }.count,
         roles.filter { $0.status == .inRedesign }.count)
    }

    // MARK: Checks

    /// What is wrong with the system, one plain sentence each. Empty means it can be used. Hatch refuses to write a
    /// system with problems, so a hand edit or a bad template is caught before an agent reads it.
    public func problems() -> [String] {
        var out: [String] = []
        if format > Self.currentFormat { out.append("The system file is format \(format); this Hatch reads up to \(Self.currentFormat). Update Hatch.") }
        if version < 1 { out.append("The version must be 1 or more.") }

        func duplicates(_ ids: [String]) -> [String] {
            var seen = Set<String>(), dup: [String] = []
            for id in ids where !seen.insert(id).inserted && !dup.contains(id) { dup.append(id) }
            return dup
        }
        for id in duplicates(foundations.map(\.id)) { out.append("Foundation \(id) is listed twice.") }
        for id in duplicates(places.map(\.id)) { out.append("Place \(id) is listed twice.") }
        for id in duplicates(roles.map(\.id)) { out.append("Role \(id) is listed twice.") }
        for id in duplicates(questions.map(\.id)) { out.append("Question \(id) is listed twice.") }
        for p in places where ComponentPlace.standard.contains(where: { $0.id == p.id }) {
            out.append("Place \(p.id) is already a standard place; remove it from the system's own places.")
        }

        for f in foundations { out += f.problems() }

        let placeIds = Set(allPlaces.map(\.id))
        for r in roles {
            guard let element = ComponentElement.named(r.element) else {
                out.append("Role \(r.id): no element called \(r.element). Known: \(ComponentElement.catalog.map(\.id).joined(separator: ", ")).")
                continue
            }
            if r.name.isEmpty { out.append("Role \(r.id) needs a name after the element, such as \(r.element).primary.") }
            if r.use.trimmingCharacters(in: .whitespaces).isEmpty { out.append("Role \(r.id) needs a \"use when\".") }
            if r.places.isEmpty { out.append("Role \(r.id) is allowed in no place.") }
            for p in r.places where !placeIds.contains(p) { out.append("Role \(r.id): no place called \(p).") }
            if let n = r.perScreen, n < 1 { out.append("Role \(r.id): at most \(n) per screen makes no sense; use 1 or more, or leave it out.") }
            if r.recipe.isEmpty && r.custom == nil { out.append("Role \(r.id) has neither a recipe nor a custom view.") }
            out += recipeProblems(r.recipe, element: element, owner: "Role \(r.id)")
            for id in duplicates(r.variants.map(\.id)) { out.append("Role \(r.id): variant \(id) is listed twice.") }
            for v in r.variants {
                out += recipeProblems(v.recipe, element: element, owner: "Variant \(r.id).\(v.id)")
                for p in v.places ?? [] where !r.places.contains(p) { out.append("Variant \(r.id).\(v.id): \(p) is not one of its role's places.") }
            }
        }

        // One role per cell, or the table cannot answer "which one here".
        var cells: [String: String] = [:]
        for r in roles {
            for p in r.places {
                let key = "\(r.element)|\(p)|\(r.importance.rawValue)"
                if let other = cells[key] {
                    out.append("Roles \(other) and \(r.id) both claim \(r.element) in \(p) at \(r.importance.title.lowercased()) importance.")
                } else { cells[key] = r.id }
            }
        }
        return out
    }

    private func recipeProblems(_ recipe: [String: String], element: ComponentElement, owner: String) -> [String] {
        var out: [String] = []
        for key in recipe.keys.sorted() {
            let value = recipe[key]!
            guard let parameter = element.parameter(key) else {
                out.append("\(owner): \(element.title.lowercased()) has no setting \(key). Settings: \(element.parameters.map(\.id).joined(separator: ", ")).")
                continue
            }
            if parameter.values.contains(value) { continue }
            if let kind = parameter.foundation, value.hasPrefix(kind.rawValue + ".") {
                if foundation(value) == nil { out.append("\(owner): \(key) uses \(value), which is not a foundation.") }
                continue
            }
            out.append("\(owner): \(value) is not a value of \(key). Values: \(parameter.choices.joined(separator: ", ")).")
        }
        return out
    }

    // MARK: For agents

    /// The role table in a few hundred tokens (DS, workflow D): one line per role with its code, purpose and places.
    /// `looks` adds each role's look, for Iris (to spot a clash) and for drawings made in HTML.
    public func briefLines(looks: Bool = false) -> [String] {
        roles.map { r in
            let places = r.places.map { place($0)?.title ?? $0 }.joined(separator: ", ")
            var line = "- `\(r.codeName)` \(r.title)" + (r.perScreen.map { ", at most \($0) per screen" } ?? "") + ": \(places)"
            if looks { line += " — " + r.lookSummary }
            if !r.variants.isEmpty { line += "; variants " + r.variants.map { "`\(r.name)\($0.id.prefix(1).uppercased() + $0.id.dropFirst())` (\($0.use))" }.joined(separator: ", ") }
            if r.status == .inRedesign { line += " (in redesign)" }
            return line
        }
    }

    // MARK: The readable copy

    /// `components/README.md`: what agents read without Hatch (DS2). Generated, never edited by hand.
    public func readme() -> String {
        var s = "# Components\n\n"
        s += "\(name.isEmpty ? "This app" : name)'s design system, generated by Hatch from `\(Self.notebookPath)`. Do not edit this file; change the system through Hatch.\n\n"
        let c = counts
        var line = "Baseline v\(version)"
        if let template, let t = ComponentTemplates.named(template) { line += ", started from the \(t.title) template" }
        line += ". \(roles.count) roles: \(c.agreed) agreed, \(c.provisional) provisional" + (c.inRedesign > 0 ? ", \(c.inRedesign) in redesign" : "") + "."
        s += line + "\n\n"
        s += "**Rules.** Use a role, never a look typed into a view. Find the role by element, place and importance in the tables below. "
        s += "If no role fits, or the request contradicts one, ask (`hatch ask` with suggested answers); never invent a look. "
        s += "A provisional role is the current guess: use it, and say so if it looks wrong.\n"

        for elementId in elementsUsed {
            let element = ComponentElement.named(elementId)
            s += "\n## \(element?.plural ?? elementId)\n\n"
            s += "| Role | Use when | Not when | Places | Look | Code | Status |\n|---|---|---|---|---|---|---|\n"
            for r in roles(of: elementId) {
                let places = r.places.map { place($0)?.title ?? $0 }.joined(separator: ", ")
                let limit = r.perScreen.map { "; at most \($0) per screen" } ?? ""
                s += "| `\(r.id)` \(r.title) | \(Self.cell(r.use)) | \(Self.cell(r.avoid.isEmpty ? "–" : r.avoid)) | \(places)\(limit) | \(Self.cell(r.lookSummary)) | `\(r.codeName)` | \(r.status.title) |\n"
            }
            let variants = roles(of: elementId).flatMap { r in r.variants.map { (r, $0) } }
            if !variants.isEmpty {
                s += "\nVariants:\n\n"
                for (r, v) in variants {
                    let only = v.places.map { " Only in " + $0.map { place($0)?.title ?? $0 }.joined(separator: ", ") + "." } ?? ""
                    s += "- `\(r.id).\(v.id)`: \(v.use)\(only) Changes: \(ComponentRole.summary(v.recipe)).\n"
                }
            }
            let m = matrix(element: elementId)
            if m.places.count > 1 || m.importances.count > 1 {
                s += "\nWhich role where:\n\n| Place | " + m.importances.map(\.title).joined(separator: " | ") + " |\n"
                s += "|---|" + m.importances.map { _ in "---|" }.joined() + "\n"
                for (i, p) in m.places.enumerated() {
                    s += "| \(p.title) | " + m.cells[i].map { $0.map { "`\($0.id)`" } ?? "not decided" }.joined(separator: " | ") + " |\n"
                }
            }
        }

        if !foundations.isEmpty {
            s += "\n## Foundations\n\n| Name | Value | Use |\n|---|---|---|\n"
            for f in foundations { s += "| `\(f.id)` | \(Self.cell(f.valueSummary)) | \(Self.cell(f.use)) |\n" }
        }
        if !places.isEmpty {
            s += "\n## This app's own places\n\n"
            for p in places { s += "- **\(p.title)** (`\(p.id)`): \(p.summary)\n" }
        }
        return s
    }

    static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Foundations

/// A value named by meaning (`space.group`, not 16), so changing it is one edit and a view never types the number.
public struct ComponentFoundation: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case color, text, space, radius, material
        public var title: String {
            switch self { case .color: "Color"; case .text: "Type"; case .space: "Spacing"; case .radius: "Radius"; case .material: "Material" }
        }
    }

    /// Starts with the kind: `color.surface`, `text.cardTitle`, `space.group`.
    public var id: String
    public var kind: Kind
    public var use: String
    /// A color's own value, `#RRGGBB` or `#RRGGBBAA`.
    public var light: String?
    public var dark: String?
    /// A system color (`windowBackgroundColor`, `accentColor`), text style (`headline`) or material (`glass`).
    public var system: String?
    public var weight: String?
    public var design: String?
    /// Points, for spacing, radii and a text size without a style.
    public var value: Double?

    public init(_ id: String, _ kind: Kind, use: String, light: String? = nil, dark: String? = nil, system: String? = nil,
                weight: String? = nil, design: String? = nil, value: Double? = nil) {
        self.id = id; self.kind = kind; self.use = use; self.light = light; self.dark = dark; self.system = system
        self.weight = weight; self.design = design; self.value = value
    }

    /// "#F4F4F6 / #1C1C1E", "system windowBackgroundColor", "headline, semibold", "16 pt".
    public var valueSummary: String {
        switch kind {
        case .color:
            if let light { return light + (dark.map { " / \($0)" } ?? "") }
            return system.map { "system \($0)" } ?? "–"
        case .text:
            var parts: [String] = []
            if let system { parts.append(system) }
            if let value { parts.append(ComponentRole.number(value) + " pt") }
            if let weight { parts.append(weight) }
            if let design, design != "default" { parts.append(design) }
            return parts.isEmpty ? "–" : parts.joined(separator: ", ")
        case .space, .radius:
            return value.map { ComponentRole.number($0) + " pt" } ?? "–"
        case .material:
            return system ?? "–"
        }
    }

    func problems() -> [String] {
        var out: [String] = []
        if !id.hasPrefix(kind.rawValue + ".") || id.count <= kind.rawValue.count + 1 {
            out.append("Foundation \(id) should be named \(kind.rawValue).something, after its kind.")
        }
        switch kind {
        case .color:
            if light == nil && system == nil { out.append("Color \(id) needs a value or a system color.") }
            for hex in [light, dark].compactMap({ $0 }) where !Self.isHex(hex) { out.append("Color \(id): \(hex) is not #RRGGBB or #RRGGBBAA.") }
        case .text:
            if system == nil && value == nil { out.append("Type \(id) needs a text style or a size.") }
        case .space, .radius:
            if let value { if value < 0 { out.append("\(kind.title) \(id) cannot be negative.") } }
            else { out.append("\(kind.title) \(id) needs a value in points.") }
        case .material:
            if system == nil { out.append("Material \(id) needs a system material, such as glass or regularMaterial.") }
        }
        return out
    }

    static func isHex(_ s: String) -> Bool {
        guard s.hasPrefix("#") else { return false }
        let digits = s.dropFirst()
        return (digits.count == 6 || digits.count == 8) && digits.allSatisfy(\.isHexDigit)
    }
}

// MARK: - Places

/// Where an element sits. The same few places recur in every macOS app, so a role can be looked up by place.
public struct ComponentPlace: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String

    public init(_ id: String, _ title: String, _ summary: String) { self.id = id; self.title = title; self.summary = summary }

    /// Two places most apps need beyond the standard ones (the templates add them, and the inventory finds Page): the
    /// content area of a screen, and the actions under a page title.
    public static let page = ComponentPlace("page", "Page", "The content area of a screen or sheet, where cards, sheets and toasts appear.")
    public static let actionRow = ComponentPlace("actionRow", "Action row", "The actions under a page or ticket title.")
    /// A floating glass bar or rail over the content: the Liquid Glass way to keep a few controls at hand (macOS 26 and later).
    public static let floating = ComponentPlace("floating", "Floating", "A floating glass bar or rail over the content, like a dock or a command bar (macOS 26 and later).")
    public static let common: [ComponentPlace] = [page, actionRow, floating]

    /// A place's title from the standard and common lists, or its id.
    public static func title(_ id: String?) -> String {
        guard let id else { return "Place unknown" }
        return (standard + common).first { $0.id == id }?.title ?? id
    }

    /// The places every system has (DS5). A system adds its own in `places`.
    public static let standard: [ComponentPlace] = [
        ComponentPlace("toolbar", "Toolbar", "The window's toolbar."),
        ComponentPlace("sheetFooter", "Sheet footer", "The buttons at the bottom of a sheet or dialog."),
        ComponentPlace("bottomBar", "Bottom bar", "A bar pinned to the bottom of a pane, with the pane's actions."),
        ComponentPlace("listRow", "List row", "One row of a list, table or queue."),
        ComponentPlace("card", "Card", "Inside a card or a grouped box on a page."),
        ComponentPlace("inspector", "Inspector", "The trailing inspector or a side panel about the selection."),
        ComponentPlace("popover", "Popover", "A popover or a small floating panel."),
        ComponentPlace("form", "Form", "A settings form or another grouped form."),
        ComponentPlace("emptyState", "Empty state", "What a pane shows when there is nothing in it."),
        ComponentPlace("contextMenu", "Context menu", "A right-click menu or the items of a More menu."),
        ComponentPlace("alert", "Alert", "An alert or a confirmation dialog."),
    ]
}

// MARK: - Roles

/// One element in one place for one purpose. The unit the rules are made of.
public struct ComponentRole: Codable, Equatable, Sendable, Identifiable {
    /// How much an action or block matters where it sits: the third axis of the role table.
    public enum Importance: String, Codable, Sendable, CaseIterable {
        case main, other, quiet, destructive
        public var title: String {
            switch self { case .main: "Main"; case .other: "Other"; case .quiet: "Quiet"; case .destructive: "Destructive" }
        }
    }

    public enum Status: String, Codable, Sendable {
        /// The current guess, from a template or the app's most-used look. Used, but not yet confirmed by the owner.
        case provisional
        /// The owner confirmed it; a change is a decision.
        case agreed
        /// Part of an open redesign; checks do not flag changes to it.
        case inRedesign = "in-redesign"
        public var title: String { switch self { case .provisional: "Provisional"; case .agreed: "Agreed"; case .inRedesign: "In redesign" } }
    }

    /// `element.name`, such as `button.primary`.
    public var id: String
    public var title: String
    /// When to use it, one line.
    public var use: String
    /// When not to, one line.
    public var avoid: String
    /// The places it is allowed in.
    public var places: [String]
    public var importance: Importance
    /// At most this many on one screen (the main action: 1). Nil means no limit.
    public var perScreen: Int?
    /// The look as settings of the native control (DS3). Empty when a custom view draws it.
    public var recipe: [String: String]
    /// The view or modifier in the components package that draws it, when the recipe cannot say it all.
    public var custom: String?
    public var variants: [ComponentVariant]
    public var status: Status
    /// The decision that set it, such as `#12` or `DS6`.
    public var decision: String?
    /// A proposed new look for an agreed role, judged beside the current one (workflow E). Applying it makes the next
    /// baseline version.
    public var draft: [String: String]?

    public init(_ id: String, _ title: String, use: String, avoid: String = "", places: [String], importance: Importance,
                perScreen: Int? = nil, recipe: [String: String] = [:], custom: String? = nil, variants: [ComponentVariant] = [],
                status: Status = .provisional, decision: String? = nil) {
        self.id = id; self.title = title; self.use = use; self.avoid = avoid; self.places = places; self.importance = importance
        self.perScreen = perScreen; self.recipe = recipe; self.custom = custom; self.variants = variants
        self.status = status; self.decision = decision
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, use, avoid, places, importance, perScreen, recipe, custom, variants, status, decision, draft
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        use = try c.decodeIfPresent(String.self, forKey: .use) ?? ""
        avoid = try c.decodeIfPresent(String.self, forKey: .avoid) ?? ""
        places = try c.decodeIfPresent([String].self, forKey: .places) ?? []
        importance = try c.decodeIfPresent(Importance.self, forKey: .importance) ?? .other
        perScreen = try c.decodeIfPresent(Int.self, forKey: .perScreen)
        recipe = try c.decodeIfPresent([String: String].self, forKey: .recipe) ?? [:]
        custom = try c.decodeIfPresent(String.self, forKey: .custom)
        variants = try c.decodeIfPresent([ComponentVariant].self, forKey: .variants) ?? []
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .provisional
        decision = try c.decodeIfPresent(String.self, forKey: .decision)
        draft = try c.decodeIfPresent([String: String].self, forKey: .draft)
    }

    public var element: String { id.split(separator: ".", maxSplits: 1).first.map(String.init) ?? id }
    public var name: String { id.split(separator: ".", maxSplits: 1).dropFirst().first.map(String.init) ?? "" }

    /// How code uses it. A recipe role gets a generated modifier named after its element (`.buttonRole(.primary)`); a
    /// custom role is its own view or modifier.
    public var codeName: String { custom ?? ".\(element)Role(.\(name))" }

    /// "glass prominent, large, title and icon, capsule".
    public var lookSummary: String {
        let recipe = Self.summary(self.recipe)
        guard custom != nil else { return recipe }
        return self.recipe.isEmpty ? "custom view" : "custom view; \(recipe)"
    }

    /// The settings in the element's own order, as plain words.
    public static func summary(_ recipe: [String: String]) -> String {
        guard !recipe.isEmpty else { return "–" }
        let order = ComponentElement.catalog.flatMap { $0.parameters.map(\.id) }
        let keys = recipe.keys.sorted { (order.firstIndex(of: $0) ?? .max, $0) < (order.firstIndex(of: $1) ?? .max, $1) }
        return keys.map { "\($0) \(recipe[$0]!)" }.joined(separator: ", ")
    }

    static func number(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }
}

/// A sanctioned second look of a role, always with its reason, so "not the same everywhere" stays a decision.
public struct ComponentVariant: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// When and why, one line.
    public var use: String
    /// Only the settings that differ from the role's recipe.
    public var recipe: [String: String]
    /// Narrower places than the role's, when it applies only there.
    public var places: [String]?

    public init(_ id: String, use: String, recipe: [String: String], places: [String]? = nil) {
        self.id = id; self.use = use; self.recipe = recipe; self.places = places
    }
}

// MARK: - Elements

/// One setting of an element's recipe and the values it may take. The Designer steps through `values` with ‹ ›, and
/// code generation maps each value to SwiftUI, so both stay free.
public struct ComponentParameter: Equatable, Sendable {
    public var id: String
    public var title: String
    public var values: [String]
    /// When set, the value may also name a foundation of this kind (`radius.card`).
    public var foundation: ComponentFoundation.Kind?
    /// False for behaviour (a keyboard key, a tooltip, a confirmation): two uses that differ only there look the same.
    public var isLook: Bool

    public init(_ id: String, _ title: String, _ values: [String], foundation: ComponentFoundation.Kind? = nil, isLook: Bool = true) {
        self.id = id; self.title = title; self.values = values; self.foundation = foundation; self.isLook = isLook
    }

    /// The values as a person reads them, with "a color foundation" style hints.
    public var choices: [String] { values + (foundation.map { ["a \($0.rawValue) foundation (\($0.rawValue).…)"] } ?? []) }
}

/// A kind of control or block, with the settings its recipes use. The catalog is fixed in Hatch; places and roles are data.
public struct ComponentElement: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var plural: String
    public var parameters: [ComponentParameter]

    public func parameter(_ id: String) -> ComponentParameter? { parameters.first { $0.id == id } }

    /// The settings that change how it looks, without behaviour (key, tooltip, confirmation).
    public func look(_ recipe: [String: String]) -> [String: String] {
        recipe.filter { parameter($0.key)?.isLook ?? true }
    }
    public static func named(_ id: String) -> ComponentElement? { catalog.first { $0.id == id } }

    static let sizes = ["mini", "small", "regular", "large", "extraLarge"]
    static let tints = ["none", "accent", "critical"]

    public static let catalog: [ComponentElement] = [
        ComponentElement(id: "button", title: "Button", plural: "Buttons", parameters: [
            ComponentParameter("style", "Style", ["automatic", "bordered", "borderedProminent", "borderless", "plain", "link", "glass", "glassProminent"]),
            ComponentParameter("size", "Size", sizes),
            ComponentParameter("label", "Label", ["titleAndIcon", "titleOnly", "iconOnly"]),
            ComponentParameter("shape", "Shape", ["automatic", "capsule", "roundedRectangle", "circle"]),
            ComponentParameter("tint", "Tint", tints, foundation: .color),
            ComponentParameter("show", "Shown", ["always", "onHover"]),
            ComponentParameter("confirm", "Confirm first", ["no", "yes"], isLook: false),
            ComponentParameter("key", "Key", ["none", "defaultAction", "cancelAction"], isLook: false),
            ComponentParameter("tooltip", "Tooltip", ["none", "title", "shortcut"], isLook: false),
        ]),
        ComponentElement(id: "menu", title: "Menu", plural: "Menus", parameters: [
            ComponentParameter("style", "Style", ["automatic", "button", "borderlessButton"]),
            ComponentParameter("look", "Button look", ["automatic", "bordered", "borderless", "plain", "glass"]),
            ComponentParameter("indicator", "Arrow", ["visible", "hidden"]),
            ComponentParameter("label", "Label", ["titleAndIcon", "titleOnly", "iconOnly"]),
            ComponentParameter("size", "Size", sizes),
        ]),
        ComponentElement(id: "picker", title: "Picker", plural: "Pickers", parameters: [
            ComponentParameter("style", "Style", ["automatic", "menu", "segmented", "inline", "radioGroup", "palette"]),
            ComponentParameter("label", "Label", ["visible", "hidden"]),
            ComponentParameter("size", "Size", sizes),
        ]),
        ComponentElement(id: "toggle", title: "Toggle", plural: "Toggles", parameters: [
            ComponentParameter("style", "Style", ["automatic", "switch", "checkbox", "button"]),
            ComponentParameter("size", "Size", sizes),
        ]),
        ComponentElement(id: "field", title: "Text field", plural: "Text fields", parameters: [
            ComponentParameter("style", "Style", ["automatic", "roundedBorder", "plain", "squareBorder"]),
            ComponentParameter("size", "Size", sizes),
        ]),
        ComponentElement(id: "switcher", title: "Section switcher", plural: "Section switchers", parameters: [
            ComponentParameter("style", "Style", ["segmented", "menu", "dock", "sidebar", "tabs"]),
            ComponentParameter("size", "Size", sizes),
        ]),
        ComponentElement(id: "row", title: "List row", plural: "List rows", parameters: [
            ComponentParameter("density", "Density", ["compact", "regular", "airy"]),
            ComponentParameter("selection", "Selection", ["system", "fill"]),
            ComponentParameter("accessory", "Accessory", ["none", "chevron", "count"]),
            ComponentParameter("actions", "Actions", ["none", "onHover", "always"]),
            ComponentParameter("separators", "Separators", ["visible", "hidden"]),
        ]),
        ComponentElement(id: "card", title: "Card", plural: "Cards", parameters: [
            ComponentParameter("surface", "Surface", ["none", "grouped", "bordered", "material", "glass"]),
            ComponentParameter("radius", "Corners", ["none"], foundation: .radius),
            ComponentParameter("padding", "Padding", ["none"], foundation: .space),
            ComponentParameter("border", "Border", ["none", "hairline"]),
            ComponentParameter("shadow", "Shadow", ["none", "soft"]),
        ]),
        ComponentElement(id: "sheet", title: "Sheet", plural: "Sheets", parameters: [
            ComponentParameter("width", "Width", ["small", "medium", "large"]),
            ComponentParameter("footer", "Footer", ["trailing", "spread"]),
            ComponentParameter("title", "Title", ["inline", "large", "none"]),
        ]),
        ComponentElement(id: "badge", title: "Badge", plural: "Badges", parameters: [
            ComponentParameter("style", "Style", ["count", "capsule", "plain"]),
            ComponentParameter("tint", "Tint", tints, foundation: .color),
        ]),
        ComponentElement(id: "toast", title: "Toast", plural: "Toasts", parameters: [
            ComponentParameter("surface", "Surface", ["glass", "material", "solid"]),
            ComponentParameter("position", "Position", ["top", "bottom"]),
            ComponentParameter("duration", "Duration", ["short", "long"]),
        ]),
        ComponentElement(id: "emptyState", title: "Empty state", plural: "Empty states", parameters: [
            ComponentParameter("style", "Style", ["system", "custom"]),
            ComponentParameter("action", "Next step", ["none", "prominent", "link"]),
        ]),
    ]
}
