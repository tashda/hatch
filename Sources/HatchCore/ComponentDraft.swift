import Foundation

// Starting a system from an app that already exists (decision DS4, workflow B): the inventory's most-used look per place
// becomes a provisional role, named and described like the template's role for the same purpose when there is one, and
// every place with more than one look becomes a question for the owner. Free: no model call (DS10's optional call is
// for words only, and the template words cover the common roles).

/// One thing the owner decides about the system. Answered in the Components Designer, in Decide, or with
/// `hatch components answer`; the answer changes the system and the question leaves the list.
public struct ComponentQuestion: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// Several looks in use for one role: which is the role's look.
        case look
        /// Code that differs from its role (found by a check, DS7): fix it, make a variant, or allow it here.
        case mismatch
        /// A place and purpose with no role yet: which look it gets.
        case missingRole
        /// A provisional role used without change on a few tickets: make it agreed (DS8).
        case confirm
    }

    public struct Option: Codable, Equatable, Sendable {
        public var title: String
        /// The look this option gives the role, when it gives one.
        public var recipe: [String: String]?
        /// The app's own style or view this look uses (`MenuRowStyle`), which becomes the role's custom view.
        public var custom: String?
        /// How many uses have this look today.
        public var count: Int
        public var examples: [String]
        /// What choosing it does, one line.
        public var effect: String

        public init(title: String, recipe: [String: String]? = nil, custom: String? = nil, count: Int = 0, examples: [String] = [], effect: String) {
            self.title = title; self.recipe = recipe; self.custom = custom; self.count = count; self.examples = examples; self.effect = effect
        }
    }

    public var id: String
    public var kind: Kind
    /// The role it is about.
    public var role: String?
    public var title: String
    public var options: [Option]
    /// The recommended option (rule 3: one recommendation and its reason).
    public var recommended: Int
    public var reason: String

    public init(id: String, kind: Kind, role: String?, title: String, options: [Option], recommended: Int = 0, reason: String) {
        self.id = id; self.kind = kind; self.role = role; self.title = title; self.options = options
        self.recommended = recommended; self.reason = reason
    }
}

public enum ComponentDraft {
    /// The most looks a question offers; the rest are summed up in its title (Decide answers with keys 1 to 4).
    static let maxOptions = 4

    /// A provisional system for an app, from its inventory (DS4). The template's roles are the skeleton, because they
    /// say what each kind of button is for; the app's own looks fill them, the most used one recommended. Uses in a place
    /// the template has no role for join the role of the same purpose nearest to it (page actions join Other action,
    /// a form's buttons join Row action); only what is left gets a new role. Template roles the app does not use yet stay
    /// as provisional guesses for the first ticket that needs one.
    public static func fromApp(name: String, inventory: ComponentInventory, template: ComponentTemplate? = ComponentTemplates.glass,
                               minimumMacOS: String = ComponentSystem.referenceMacOS) -> ComponentSystem {
        let reference = (template ?? ComponentTemplates.glass).system(name: name)
        var system = ComponentSystem(name: name, template: nil, foundations: reference.foundations, places: ComponentPlace.common,
                                     roles: reference.roles, minimumMacOS: minimumMacOS)
        let placed = inventory.uses.filter { $0.place != nil && ComponentElement.named($0.element) != nil }

        // 1. Cells the skeleton lacks: join the same-purpose role whose places are nearest, if no role holds the cell.
        var assigned: [String: [ComponentInventory.Use]] = [:]
        var leftovers: [ComponentInventory.Use] = []
        for u in placed {
            if let r = system.role(element: u.element, place: u.place!, importance: u.importance) { assigned[r.id, default: []].append(u); continue }
            let family = families.first { $0.contains(u.place!) } ?? [u.place!]
            if let i = system.roles.firstIndex(where: { $0.element == u.element && $0.importance == u.importance && $0.places.contains(where: family.contains) }) {
                system.roles[i].places.append(u.place!)
                assigned[system.roles[i].id, default: []].append(u)
            } else { leftovers.append(u) }
        }
        // 2. What is left: one role per element and importance.
        var groups: [String: [ComponentInventory.Use]] = [:], order: [String] = []
        for u in leftovers {
            let key = "\(u.element)|\(u.importance.rawValue)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(u)
        }
        for key in order {
            let uses = groups[key]!
            let element = ComponentElement.named(uses[0].element)!
            let places = Array(Set(uses.compactMap(\.place))).sorted(by: placeOrder)
            let role = makeRole(element: element, importance: uses[0].importance, places: places,
                                looks: looks(uses, element: element), reference: nil, taken: Set(system.roles.map(\.id)))
            system.roles.append(role)
            assigned[role.id] = uses
        }
        // 3. Each used role takes the app's most used look; more than one look is a question.
        for i in system.roles.indices {
            guard let uses = assigned[system.roles[i].id], let element = ComponentElement.named(system.roles[i].element) else {
                system.roles[i].use += system.roles[i].use.hasSuffix(".") ? " Not used in the app yet." : ". Not used in the app yet."
                continue
            }
            system.roles[i].places.sort(by: placeOrder)
            let found = looks(uses, element: element)
            let top = sanitize(found[0].recipe.merging(found[0].look) { $1 }, element: element)
            system.roles[i].recipe = top.recipe
            system.roles[i].custom = top.custom ?? system.roles[i].custom
            if top.recipe.isEmpty && system.roles[i].custom == nil { system.roles[i].recipe = ["style": "automatic"].filter { element.parameter($0.key) != nil } }
            system.roles[i].variants = []
            if found.count > 1 { system.questions.append(question(for: system.roles[i], looks: found, reference: reference)) }
        }
        return system
    }

    /// Places that serve the same purpose for a control: a stray cell joins the role that holds one of its family.
    static let families: [[String]] = [
        ["actionRow", "bottomBar", "sheetFooter", "page", "emptyState", "alert"],
        ["listRow", "card", "inspector", "popover", "form"],
        ["toolbar"],
        ["contextMenu"],
    ]

    /// One look and the uses that have it.
    struct Look {
        var look: [String: String]
        /// The full recipe of the most common use (behaviour included).
        var recipe: [String: String]
        var count: Int
        var examples: [String]
    }

    /// Looks of some uses, most used first, behaviour ignored (a tooltip does not make another look).
    static func looks(_ uses: [ComponentInventory.Use], element: ComponentElement) -> [Look] {
        var order: [[String: String]] = [], groups: [[String: String]: [ComponentInventory.Use]] = [:]
        for u in uses {
            // Group on the look as written, a custom style included, so `MenuRowStyle` stays its own look.
            let clean = sanitize(u.recipe, element: element)
            var look = element.look(clean.recipe)
            if let custom = clean.custom { look["style"] = "custom:" + custom }
            if groups[look] == nil { order.append(look) }
            groups[look, default: []].append(u)
        }
        return order.map { look in
            let list = groups[look]!
            // The behaviour most of them share (a default key on the main action, say).
            var full = look
            for key in element.parameters.filter({ !$0.isLook }).map(\.id) {
                var tally: [String: Int] = [:]
                for u in list { if let v = u.recipe[key] { tally[v, default: 0] += 1 } }
                if let (v, n) = tally.max(by: { $0.value < $1.value }), n * 2 > list.count { full[key] = v }
            }
            return Look(look: look, recipe: full, count: list.count, examples: ComponentInventory.firstDistinct(list.map(\.location), 3))
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : ComponentRole.summary($0.look) < ComponentRole.summary($1.look) }
    }

    /// The same look seen in several places, counted once.
    static func merge(_ looks: [Look]) -> [Look] {
        var out: [Look] = []
        for l in looks {
            if let i = out.firstIndex(where: { $0.look == l.look }) {
                out[i].count += l.count
                out[i].examples = ComponentInventory.firstDistinct(out[i].examples + l.examples, 3)
            } else { out.append(l) }
        }
        return out.sorted { $0.count > $1.count }
    }

    /// Values the catalog does not know become a custom view (`custom:MenuBarRowStyle`) or are dropped (`label custom`).
    static func sanitize(_ recipe: [String: String], element: ComponentElement) -> (recipe: [String: String], custom: String?) {
        var out: [String: String] = [:], custom: String?
        for (k, v) in recipe {
            if v.hasPrefix("custom:") { custom = String(v.dropFirst(7)); continue }
            guard let p = element.parameter(k), p.values.contains(v) || (p.foundation != nil && v.contains(".")) else { continue }
            out[k] = v
        }
        return (out, custom)
    }

    static func placeOrder(_ a: String, _ b: String) -> Bool {
        let order = (ComponentPlace.standard + ComponentPlace.common).map(\.id)
        return (order.firstIndex(of: a) ?? .max, a) < (order.firstIndex(of: b) ?? .max, b)
    }

    /// A role for one group: words from the template's role for the same element, importance and places when there
    /// is one; otherwise a plain name from where it sits.
    static func makeRole(element: ComponentElement, importance: ComponentRole.Importance, places: [String], looks: [Look],
                         reference: ComponentSystem?, taken: Set<String>) -> ComponentRole {
        let top = looks.max { $0.count < $1.count }!
        let clean = sanitize(top.recipe, element: element)
        let count = looks.reduce(0) { $0 + $1.count }
        let match = reference?.roles(of: element.id)
            .filter { $0.importance == importance }
            .max { overlap($0.places, places) < overlap($1.places, places) }
            .flatMap { overlap($0.places, places) > 0 ? $0 : nil }
        var name = match?.name ?? plainName(element: element.id, importance: importance, places: places, recipe: clean.recipe)
        if taken.contains("\(element.id).\(name)") {
            let family = places.first.flatMap { p in families.firstIndex { $0.contains(p) } }
            let suffix = family.map { ["InPage", "InRow", "InToolbar", "InMenu"][$0] } ?? "Other"
            name += suffix
            var n = 2
            while taken.contains("\(element.id).\(name)") { name = name.trimmingCharacters(in: .decimalDigits) + "\(n)"; n += 1 }
        }
        let where_ = places.map { ComponentPlace.title($0).lowercased() }.joined(separator: ", ")
        return ComponentRole(
            "\(element.id).\(name)",
            match?.title ?? "\(element.title) (\(importance.title.lowercased()), \(where_))",
            use: match?.use ?? "\(element.plural) at \(importance.title.lowercased()) importance in: \(where_). The app's most used look there (\(count) uses).",
            avoid: match?.avoid ?? "",
            places: places, importance: importance,
            // One main action per screen, except where it repeats with its row or card.
            perScreen: importance == .main && element.id == "button" && !places.contains(where: families[1].contains) ? 1 : nil,
            recipe: clean.recipe, custom: clean.custom, status: .provisional)
    }

    static func overlap(_ a: [String], _ b: [String]) -> Int { Set(a).intersection(b).count }

    static func plainName(element: String, importance: ComponentRole.Importance, places: [String], recipe: [String: String]) -> String {
        switch importance {
        case .main: return "primary"
        case .destructive: return "destructive"
        case .quiet:
            if recipe["style"] == "link" { return "link" }
            return Set(places).isSubset(of: ["sheetFooter", "alert"]) ? "cancel" : "quiet"
        case .other:
            switch places.first {
            case "toolbar": return "toolbar"
            case "listRow", "card", "inspector", "popover": return "inRow"
            case "contextMenu": return "menuItem"
            case "form": return "inForm"
            case "emptyState": return "emptyState"
            case "alert" where element == "button": return "alertAction"
            default: return element == "button" ? "secondary" : "inPage"
            }
        }
    }

    /// "Row action: 3 looks in use" with each look as an option, the most used recommended.
    static func question(for role: ComponentRole, looks: [Look], reference: ComponentSystem?) -> ComponentQuestion {
        let element = ComponentElement.named(role.element)!
        let total = looks.reduce(0) { $0 + $1.count }
        let shown = Array(looks.prefix(maxOptions))
        var options = shown.map { l in
            let clean = sanitize(l.recipe.merging(l.look) { $1 }, element: element)
            return ComponentQuestion.Option(title: ComponentRole.summary(l.look), recipe: clean.recipe, custom: clean.custom, count: l.count,
                                     examples: l.examples,
                                     effect: "Make this the look of \(role.id); the \(total - l.count) uses with other looks move to it when their screens are next touched.")
        }
        options.append(ComponentQuestion.Option(title: "Not sure yet",
                                                effect: "Keep the most used look as a provisional guess and decide when a ticket needs it."))
        let rest = looks.count - shown.count
        let places = role.places.map { ComponentPlace.title($0).lowercased() }.joined(separator: ", ")
        var reason = "It is the look most of them have today (\(shown[0].count) of \(total)), so choosing it changes the fewest screens."
        if let ref = reference?.roles(of: role.element).first(where: { $0.importance == role.importance && overlap($0.places, role.places) > 0 }),
           let i = shown.firstIndex(where: { element.look($0.look) == element.look(ref.recipe) }), i != 0 {
            reason += " The \(ComponentTemplates.named(reference?.template ?? "")?.title ?? "template")'s look for this, the macOS 27 reference, is option \(i + 1)."
        }
        return ComponentQuestion(
            id: "look.\(role.id)", kind: .look, role: role.id,
            title: "\(role.title): \(looks.count) looks in use in \(places)" + (rest > 0 ? " (\(rest) rare ones not shown)" : ""),
            options: options, recommended: 0, reason: reason)
    }
}

// MARK: - Answers

public enum ComponentAnswerError: Error, CustomStringConvertible, Equatable {
    case noQuestion(String), noOption(Int), noRole(String)
    public var description: String {
        switch self {
        case .noQuestion(let id): "No open question \(id)."
        case .noOption(let n): "No option \(n)."
        case .noRole(let id): "The role \(id) is gone."
        }
    }
}

public extension ComponentSystem {
    /// Answers a question with one of its options (0-based). A look becomes the role's look and the role is agreed;
    /// "Not sure yet" leaves it provisional. Either way the question leaves the list. `decision` records where it was
    /// decided (`#12`, `DS4`).
    mutating func answer(_ questionId: String, option: Int, decision: String? = nil) throws {
        guard let qi = questions.firstIndex(where: { $0.id == questionId }) else { throw ComponentAnswerError.noQuestion(questionId) }
        let q = questions[qi]
        guard q.options.indices.contains(option) else { throw ComponentAnswerError.noOption(option + 1) }
        let chosen = q.options[option]
        if let roleId = q.role, let recipe = chosen.recipe {
            guard let ri = roles.firstIndex(where: { $0.id == roleId }) else { throw ComponentAnswerError.noRole(roleId) }
            roles[ri].recipe = recipe
            roles[ri].custom = chosen.custom
            roles[ri].status = .agreed
            roles[ri].decision = decision ?? roles[ri].decision
        }
        questions.remove(at: qi)
    }

    /// Marks a role agreed as it is (DS8), or every provisional role when `id` is nil.
    mutating func agree(_ id: String? = nil, decision: String? = nil) throws {
        if let id {
            guard let i = roles.firstIndex(where: { $0.id == id }) else { throw ComponentAnswerError.noRole(id) }
            roles[i].status = .agreed; roles[i].decision = decision ?? roles[i].decision
            questions.removeAll { $0.role == id && $0.kind == .confirm }
        } else {
            for i in roles.indices where roles[i].status == .provisional { roles[i].status = .agreed; roles[i].decision = decision ?? roles[i].decision }
        }
    }

    /// Keeps a second look of a role as a variant, with its reason (DS4's "keep it as a variant").
    mutating func addVariant(to roleId: String, id: String, use: String, recipe: [String: String], places: [String]? = nil) throws {
        guard let i = roles.firstIndex(where: { $0.id == roleId }) else { throw ComponentAnswerError.noRole(roleId) }
        let element = ComponentElement.named(roles[i].element)
        // Only what differs from the role.
        let differs = recipe.filter { roles[i].recipe[$0.key] != $0.value && (element?.parameter($0.key) != nil) }
        roles[i].variants.removeAll { $0.id == id }
        roles[i].variants.append(ComponentVariant(id, use: use, recipe: differs, places: places))
    }
}
