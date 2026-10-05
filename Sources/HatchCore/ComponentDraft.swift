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
        /// The looks an agent offered for a change the owner asked for (CP3); answering accepts or drops the Proposal.
        case change
    }

    public struct Option: Codable, Equatable, Sendable {
        public var title: String
        /// The look this option gives the role, when it gives one.
        public var recipe: [String: String]?
        /// The app's own style or view this look uses (`MenuRowStyle`), which becomes the role's custom view.
        public var custom: String?
        /// Choosing it makes the role follow macOS (NF3).
        public var follow: Bool?
        /// How many uses have this look today.
        public var count: Int
        public var examples: [String]
        /// What choosing it does, one line.
        public var effect: String

        public init(title: String, recipe: [String: String]? = nil, custom: String? = nil, follow: Bool? = nil, count: Int = 0,
                    examples: [String] = [], effect: String) {
            self.title = title; self.recipe = recipe; self.custom = custom; self.follow = follow; self.count = count
            self.examples = examples; self.effect = effect
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
    /// For a change (CP3): the Proposal's ticket id, and the place or area the change is limited to (a variant there).
    public var ticket: Int?
    public var place: String?
    public var area: String?

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
    public static func fromApp(name: String, inventory: ComponentInventory, template: ComponentTemplate? = ComponentTemplates.native,
                               minimumMacOS: String = ComponentSystem.referenceMacOS, shell: ComponentShell? = nil) -> ComponentSystem {
        let reference = (template ?? ComponentTemplates.native).system(name: name)
        // The template it is compared with (CD46): its looks are recommended where the app differs (CD28).
        var system = ComponentSystem(name: name, template: reference.template, foundations: reference.foundations, places: ComponentPlace.common,
                                     roles: reference.roles, minimumMacOS: minimumMacOS)
        system.rules = reference.rules.isEmpty ? ComponentRule.appleDefaults : reference.rules
        system.shell = shell
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
            // Nothing differs from the system's default: the app already lets macOS decide here (NF3).
            if element.look(top.recipe).isEmpty && system.roles[i].custom == nil { system.roles[i].followsMacOS = true } else { system.roles[i].followsMacOS = false }
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
            // What macOS does anyway is left out (NF1).
            if p.systemDefault == v { continue }
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
            match?.title ?? jobTitle(element: element, importance: importance, places: places),
            use: match?.use ?? "\(element.plural) at \(importance.title.lowercased()) importance in: \(where_). The app's most used look there (\(count) uses).",
            avoid: match?.avoid ?? "",
            places: places, importance: importance,
            // One main action per screen, except where it repeats with its row or card.
            perScreen: importance == .main && element.id == "button" && !places.contains(where: families[1].contains) ? 1 : nil,
            recipe: clean.recipe, custom: clean.custom, status: .provisional)
    }

    static func overlap(_ a: [String], _ b: [String]) -> Int { Set(a).intersection(b).count }

    /// Where most of a role's places are: 0 page, 1 row, 2 toolbar, 3 menu (the `families`), 4 floating.
    static func mainFamily(_ places: [String]) -> Int? {
        var tally: [Int: Int] = [:]
        for p in places { if let f = p == "floating" ? 4 : families.firstIndex(where: { $0.contains(p) }) { tally[f, default: 0] += 1 } }
        return tally.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// The id's last part for a role Hatch made up: what it is for, from where most of it sits.
    static func plainName(element: String, importance: ComponentRole.Importance, places: [String], recipe: [String: String]) -> String {
        let family = mainFamily(places)
        let suffix = family.map { ["InPage", "InRow", "InToolbar", "InMenu", "Floating"][$0] } ?? ""
        guard element == "button" else {
            switch importance {
            case .main: return "primary" + suffix
            case .destructive: return "destructive" + suffix
            case .quiet: return "quiet" + suffix
            case .other: return family.map { ["inPage", "inRow", "inToolbar", "inMenu", "floating"][$0] } ?? "standard"
            }
        }
        switch importance {
        case .main: return "primary"
        case .destructive: return "destructive"
        case .quiet:
            if recipe["style"] == "link" { return "link" }
            return Set(places).isSubset(of: ["sheetFooter", "alert"]) ? "cancel" : "quiet"
        case .other:
            switch family {
            case 2: return "toolbar"
            case 1: return "inRow"
            case 3: return "menuItem"
            default: return places.contains("alert") && places.count == 1 ? "alertAction" : "secondary"
            }
        }
    }

    /// A made-up role's title, by its job (CD2): "Main action in a row", "Menu button", never a list of places.
    static func jobTitle(element: ComponentElement, importance: ComponentRole.Importance, places: [String]) -> String {
        let qualifier = mainFamily(places).map { ["", " in a row", " in the toolbar", " in a menu", ", floating"][$0] } ?? ""
        let base: String
        switch element.id {
        case "button": base = ["main": "Main action", "other": "Other action", "quiet": "Quiet action", "destructive": "Destructive action"][importance.rawValue] ?? "Action"
        case "menu": base = "Menu button"
        default: base = element.title
        }
        return base + qualifier
    }

    /// "Row action: 3 looks in use" with each look as an option. The recommendation follows CD28: never a look Apple's
    /// guidance argues against; Follow macOS where the starting template lets macOS draw it; the template's own look,
    /// offered even when the app doesn't use it (CD5); and only then the most used look. The reason names the rule.
    static func question(for role: ComponentRole, looks: [Look], reference: ComponentSystem?) -> ComponentQuestion {
        let element = ComponentElement.named(role.element)!
        let total = looks.reduce(0) { $0 + $1.count }
        let shown = Array(looks.prefix(maxOptions))
        var options = shown.map { l in
            let clean = sanitize(l.recipe.merging(l.look) { $1 }, element: element)
            return ComponentQuestion.Option(title: ComponentWords.look(element: role.element, recipe: element.look(clean.recipe)), recipe: clean.recipe, custom: clean.custom, count: l.count,
                                     examples: l.examples,
                                     effect: "Make this the look of \(role.id); the \(total - l.count) uses with other looks move to it when their screens are next touched.")
        }
        let templateName = ComponentTemplates.named(reference?.template ?? "")?.title ?? "starting"
        let ref = reference?.roles(of: role.element)
            .filter { $0.importance == role.importance && overlap($0.places, role.places) > 0 }
            .max { overlap($0.places, role.places) < overlap($1.places, role.places) }
        // Apple's guidance, checked on the option as if it were the role's look (redundant settings don't count).
        func againstApple(_ recipe: [String: String]) -> ComponentAdvice? {
            var r = role; r.recipe = recipe; r.draft = nil; r.followsMacOS = false
            return ComponentSystem(name: "check", roles: [r]).advice().first { $0.kind != .redundant }
        }
        // The template's look, when it has one of its own and Apple has nothing against it, is always an option.
        var templateIndex: Int?
        if let ref, !ref.followsMacOS, againstApple(ref.recipe) == nil {
            let target = element.withoutDefaults(element.look(ref.recipe))
            if let i = options.firstIndex(where: { element.withoutDefaults(element.look($0.recipe ?? [:])) == target }) {
                templateIndex = i
            } else {
                let recipe = sanitize(ref.recipe, element: element).recipe
                options.append(ComponentQuestion.Option(title: ComponentWords.look(element: role.element, recipe: element.look(recipe)), recipe: recipe,
                                                        effect: "The \(templateName) template's look; all \(total) uses move to it when their screens are next touched."))
                templateIndex = options.count - 1
            }
        }
        options.append(ComponentQuestion.Option(title: "Follow macOS", follow: true,
                                                effect: "No look of its own: macOS decides, now and in later versions. Hand styling here is flagged."))
        let followIndex = options.count - 1
        options.append(ComponentQuestion.Option(title: "Not sure yet",
                                                effect: "Keep the most used look as a provisional guess and decide when a ticket needs it."))
        let rest = looks.count - shown.count
        let places = role.places.map { ComponentPlace.title($0).lowercased() }.joined(separator: ", ")
        var reason = "\(looks.count) looks are in use in \(places)" + (rest > 0 ? " (\(rest) rare ones not shown)" : "") + ". "
        let recommended: Int
        if ref?.followsMacOS == true {
            recommended = followIndex
            reason += "The \(templateName) template lets macOS draw it here, so a look of its own would only repeat or fight macOS."
        } else if let templateIndex {
            recommended = templateIndex
            reason += templateIndex < shown.count
                ? "This is the \(templateName) template's look, and \(shown[templateIndex].count) of \(total) already look like it."
                : "This is the \(templateName) template's look; the app doesn't use it yet."
        } else if let i = shown.indices.first(where: { againstApple(options[$0].recipe ?? [:]) == nil }) {
            recommended = i
            reason += i == 0
                ? "It is the look most of them have today (\(shown[0].count) of \(total)), so choosing it changes the fewest screens."
                : "The most used look goes against Apple's guidance (\(againstApple(options[0].recipe ?? [:])!.message)), so the next most used one (\(shown[i].count) of \(total))."
        } else {
            recommended = followIndex
            reason += "Every look in use goes against Apple's guidance, so macOS should draw it."
        }
        return ComponentQuestion(
            id: "look.\(role.id)", kind: .look, role: role.id,
            title: ComponentWords.lookQuestion(role),
            options: options, recommended: recommended, reason: reason)
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
        guard let q = questions.first(where: { $0.id == questionId }) else { throw ComponentAnswerError.noQuestion(questionId) }
        guard q.options.indices.contains(option) else { throw ComponentAnswerError.noOption(option + 1) }
        let chosen = q.options[option]
        if q.kind == .change, let roleId = q.role {
            // A change: the chosen look becomes the role's draft, or a variant where the change is limited to.
            if let recipe = chosen.recipe {
                try acceptDesign(role: roleId, look: recipe, place: q.place, area: q.area, use: q.title, decision: decision)
            }
        } else if let roleId = q.role, chosen.follow == true {
            try followMacOS(role: roleId, decision: decision)
        } else if let roleId = q.role, let recipe = chosen.recipe {
            guard let ri = roles.firstIndex(where: { $0.id == roleId }) else { throw ComponentAnswerError.noRole(roleId) }
            roles[ri].recipe = recipe
            roles[ri].custom = chosen.custom
            roles[ri].status = .agreed
            roles[ri].decision = decision ?? roles[ri].decision
        }
        questions.removeAll { $0.id == questionId }
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

    /// How many built tickets without change before Hatch offers to agree a provisional role (DS8).
    static let confirmAfter = 3

    /// Records that a built ticket used these provisional roles as they are (DS8). At three tickets a role gets a confirm
    /// question: agree to it as it is, or not yet. Returns the roles that just reached three.
    @discardableResult
    mutating func recordUse(roles used: Set<String>, ticket: String) -> [String] {
        var reached: [String] = []
        for i in roles.indices where used.contains(roles[i].id) && roles[i].status == .provisional && !roles[i].usedOn.contains(ticket) {
            roles[i].usedOn.append(ticket)
            let r = roles[i]
            // Every third use: after "Not yet" it asks again three tickets later, never on each one.
            guard r.usedOn.count % Self.confirmAfter == 0, !questions.contains(where: { $0.role == r.id }) else { continue }
            questions.append(ComponentQuestion(
                id: "confirm.\(r.id)", kind: .confirm, role: r.id,
                title: "\(r.title): used on \(r.usedOn.count) tickets without change",
                options: [
                    .init(title: "Agree to it as it is", recipe: r.followsMacOS ? nil : r.recipe, follow: r.followsMacOS ? true : nil,
                          effect: "\(r.id) becomes agreed; changing it later is a decision."),
                    .init(title: "Not yet", effect: "It stays a provisional guess."),
                ],
                recommended: 0,
                reason: "Tickets \(r.usedOn.joined(separator: ", ")) used it as it is, so it already works in practice; agreeing makes it the rule."))
            reached.append(r.id)
        }
        return reached
    }

    /// "Like this, and make it a setting" (NF5): the role or rule keeps its current choice as the default and becomes
    /// configurable; the check accepts other looks until the app has the setting. Returns the draft ticket that asks for it.
    @discardableResult
    mutating func makeConfigurable(_ id: String, alternatives: [String] = []) throws -> ComponentsSetup.Draft {
        if let i = roles.firstIndex(where: { $0.id == id }) {
            roles[i].configurable = true
            let r = roles[i]
            let others = alternatives.isEmpty ? "" : "\n\nThe other looks people may pick:\n" + alternatives.map { "- \($0)" }.joined(separator: "\n")
            return ComponentsSetup.Draft(type: .tweak, title: "Make \(r.title.lowercased()) a setting",
                body: """
                    \(name)'s design system keeps \(r.id) (\(r.lookSummary)) as the default and wants it to be a setting people can change.

                    Add a setting in the app's Settings for how \(r.title.lowercased()) look, with the current look as the default\(r.followsMacOS ? " (following macOS)" : ""). The generated `\(r.codeName)` reads the setting; screens keep using the role. Until this is built, Hatch's check accepts the other looks for \(r.id).\(others)

                    """)
        }
        if let i = rules.firstIndex(where: { $0.id == id }) {
            rules[i].configurable = true
            let r = rules[i]
            let kind = r.info
            let values = kind?.values.filter { $0.id != "off" }.map { "- \($0.says)" }.joined(separator: "\n") ?? ""
            return ComponentsSetup.Draft(type: .tweak, title: "Make \((kind?.title ?? r.kind).lowercased()) a setting",
                body: """
                    \(name)'s design system keeps the rule "\(r.text)" as the default and wants it to be a setting people can change.

                    Add a setting in the app's Settings with these choices, the current one as the default:
                    \(values)

                    Until this is built, Hatch's check does not hold the app to the rule.

                    """)
        }
        throw ComponentAnswerError.noRole(id)
    }

    /// Makes a role follow macOS (NF3): its look settings go, behaviour (key, tooltip, confirmation) stays, and it is agreed.
    mutating func followMacOS(role roleId: String, decision: String? = nil) throws {
        guard let i = roles.firstIndex(where: { $0.id == roleId }), let element = ComponentElement.named(roles[i].element) else {
            throw ComponentAnswerError.noRole(roleId)
        }
        roles[i].recipe = roles[i].recipe.filter { element.parameter($0.key)?.isLook == false || $0.key == "label" }
        roles[i].custom = nil
        roles[i].draft = nil
        roles[i].variants = []
        roles[i].followsMacOS = true
        roles[i].status = .agreed
        roles[i].decision = decision ?? roles[i].decision
        questions.removeAll { $0.role == roleId && $0.kind == .look }
    }

    /// Makes a whole group follow macOS: an element in a place, or an area. Roles it covers follow too.
    mutating func followMacOS(_ scope: ComponentFollow) throws {
        guard scope.element != nil || scope.place != nil || scope.area != nil else { throw StoreError.invalid("Say what follows macOS: an element, a place or an area.") }
        follows.removeAll { $0.id == scope.id }
        follows.append(scope)
        if scope.area == nil {
            for r in roles where (scope.element == nil || r.element == scope.element) && (scope.place == nil || r.places == [scope.place!]) {
                try followMacOS(role: r.id, decision: scope.decision)
            }
        }
    }

    /// Stops following macOS for a group (roles keep following until changed one by one).
    mutating func stopFollowing(_ scopeId: String) { follows.removeAll { $0.id == scopeId } }

    /// Changes a role's look. A provisional role takes it at once (it is still being decided); an agreed one gets it as
    /// a draft beside its current look and goes into redesign, because changing it changes every screen that uses it.
    mutating func setLook(_ roleId: String, recipe: [String: String]) throws {
        guard let i = roles.firstIndex(where: { $0.id == roleId }) else { throw ComponentAnswerError.noRole(roleId) }
        if roles[i].followsMacOS {
            // Giving a following role a look of its own is a redesign of it.
            roles[i].followsMacOS = false
            roles[i].draft = recipe
            roles[i].status = .inRedesign
        } else if roles[i].status == .provisional {
            roles[i].recipe = recipe
        } else {
            roles[i].draft = recipe == roles[i].recipe ? nil : recipe
            roles[i].status = roles[i].draft == nil ? .agreed : .inRedesign
        }
    }

    /// Makes drafts the roles' looks (one role, or all with drafts) and starts the next baseline version. Returns the
    /// roles that changed.
    @discardableResult
    mutating func applyDrafts(_ roleId: String? = nil, decision: String? = nil) throws -> [String] {
        var changed: [String] = []
        for i in roles.indices where roles[i].draft != nil && (roleId == nil || roles[i].id == roleId) {
            roles[i].recipe = roles[i].draft!
            roles[i].draft = nil
            roles[i].status = .agreed
            roles[i].decision = decision ?? roles[i].decision
            changed.append(roles[i].id)
        }
        if let roleId, changed.isEmpty, role(roleId) == nil { throw ComponentAnswerError.noRole(roleId) }
        if !changed.isEmpty { version += 1 }
        return changed
    }

    /// Drops a draft: the role keeps its agreed look.
    mutating func discardDraft(_ roleId: String) throws {
        guard let i = roles.firstIndex(where: { $0.id == roleId }) else { throw ComponentAnswerError.noRole(roleId) }
        roles[i].draft = nil
        if roles[i].status == .inRedesign { roles[i].status = .agreed }
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

// MARK: - Putting a system in place

public extension ComponentsSetup {
    static let systemThemeTitle = "Put the design system in place"

    /// Draft tickets after a system is started (workflow A step 3, B step 5): a Theme with the generated code first, then
    /// the mechanical swaps (nothing visible changes), then the controls whose look differs from their role. Drafts only:
    /// the owner submits them (CO3).
    static func systemDrafts(_ system: ComponentSystem, config: ComponentsConfig, coverage: (usingRole: Int, matching: Int, total: Int)?) -> [Draft] {
        let product = config.product ?? (config.path as NSString).lastPathComponent
        var drafts = [
            Draft(type: .theme, title: systemThemeTitle,
                  body: "\(system.name)'s design system is in the notebook (`\(ComponentSystem.notebookPath)`, rules in `\(ComponentSystem.readmePath)`). These tickets put it into the code one step at a time: the generated roles first, then the swaps that change nothing visible, then the controls that look different from their role. Submit the first; the others build on it.\n"),
            Draft(type: .tweak, title: "Generate the role code",
                  body: """
                    Run `hatch components generate --package` in the app's clone. It writes `Roles.swift` and `Foundations.swift` into `\(config.path)` (library `\(product)`), with `.buttonRole(...)` and the other role modifiers and the named values (`Palette`, `Typography`, `Space`, `Radius`).

                    Add the package to the app if it is not there yet, import `\(product)` where views need it, and build. Do not change any screen in this ticket. Never edit the generated files: they are written again from the system.

                    """),
        ]
        let matching = coverage.map { " (\($0.matching) today)" } ?? ""
        drafts.append(Draft(type: .tweak, title: "Use the roles where the look already matches",
                            body: """
                                `hatch components check` lists controls styled by hand whose look is already their role's\(matching) ("Could use its role"). Replace their style modifiers with the role (`.buttonRole(.inRow)` and so on). Nothing visible changes, so screenshots before and after must match.

                                """))
        drafts.append(Draft(type: .tweak, title: "Move the controls that differ onto their roles",
                            body: """
                                `hatch components check` lists controls whose look differs from their role ("Differs from its role") and places with no role yet. For each group: use the role, or ask with `hatch ask` and suggest use the role (first), add a variant, or allow it here. Never invent a look. Split this ticket by area if it touches more than a few screens.

                                """))
        return drafts
    }
}

// MARK: - Questions in Decide

public extension ComponentsSetup {
    /// The line that ties a prepared Question ticket to its design system question.
    static func questionMarker(_ id: String) -> String { "Design system question: `\(id)`" }

    /// The design system question a ticket stands for, from its marker.
    static func componentQuestionId(inBody body: String) -> String? {
        guard let r = body.range(of: "Design system question: `") else { return nil }
        let rest = body[r.upperBound...]
        return rest.firstIndex(of: "`").map { String(rest[..<$0]) }
    }

    /// A design system question as a prepared Question ticket, answered in Decide like any other (DC9): its options
    /// with the recommendation, and what each gains and costs (DC5).
    static func questionDraft(_ q: ComponentQuestion, system: ComponentSystem) -> Draft {
        let total = q.options.reduce(0) { $0 + $1.count }
        // Plain words, worked out from the system each time so questions written by an older Hatch read the same.
        let role = q.role.flatMap { system.role($0) }
        let element = role.flatMap { ComponentElement.named($0.element) }
        func words(_ o: ComponentQuestion.Option) -> String {
            guard let r = o.recipe, let role, let element else { return o.title }
            return ComponentWords.look(element: role.element, recipe: element.look(r)) + (o.custom.map { " (\($0))" } ?? "")
        }
        let options = q.options.enumerated().map { i, o -> QuestionOption in
            let gain: String, cost: String
            if o.follow == true { gain = "macOS decides, now and in later versions."; cost = "Hand styling there is flagged." }
            else if o.recipe == nil { gain = "Nothing changes now."; cost = "Stays a guess until a ticket needs it." }
            else { gain = "\(o.count) of \(total) already look like this."; cost = "\(total - o.count) move to it when their screens are touched." }
            return QuestionOption(key: String(i), title: words(o), detail: o.recipe == nil ? o.effect : (o.examples.isEmpty ? nil : "e.g. " + o.examples.joined(separator: ", ")),
                                  recommended: i == q.recommended, why: i == q.recommended ? q.reason : nil, gain: gain, cost: cost)
        }
        let body = """
            \(q.reason)

            Answering here changes \(system.name)'s design system (`\(ComponentSystem.notebookPath)` in the notebook). The Components Designer draws every option in its places.

            \(questionMarker(q.id))

            """
        let title = q.kind == .look && role != nil ? ComponentWords.lookQuestion(role!) : q.title
        var d = Draft(type: .question, title: title, body: body, options: options)
        d.area = area
        return d
    }
}

public extension HatchStore {
    /// Keeps Decide in step with the design system: a prepared Question for each open question without one, and drops
    /// the ones whose question was answered elsewhere (the Designer, the CLI), and rewords the ones still waiting.
    /// Returns what changed.
    @discardableResult
    func syncComponentQuestions(projectId: Int, system: ComponentSystem) throws -> (added: Int, dropped: Int, updated: Int) {
        var filter = TicketFilter(); filter.projectId = projectId; filter.area = ComponentsSetup.area
        let existing = try tickets(filter).filter { $0.type == .question }
        var byQuestion: [String: Ticket] = [:]
        for t in existing { if let id = ComponentsSetup.componentQuestionId(inBody: t.body) { byQuestion[id] = t } }
        let open = Set(system.questions.map(\.id))
        var added = 0, dropped = 0
        // A change's looks are answered on its Proposal (CP3), not on a Question of their own.
        for q in system.questions where byQuestion[q.id] == nil && q.kind != .change {
            let d = ComponentsSetup.questionDraft(q, system: system)
            let t = try createTicket(projectId: projectId, type: .question, title: d.title, body: d.body, area: d.area)
            try setQuestionOptions(ticketId: t.id, d.options)
            added += 1
        }
        for (id, t) in byQuestion where !open.contains(id) && t.status == .draft {
            try move(t.id, to: .dropped, actor: .hatch, reason: "answered in the Components Designer")
            dropped += 1
        }
        // Questions still waiting take the current wording (titles and options in plain words).
        var updated = 0
        for q in system.questions where q.kind != .change {
            guard let t = byQuestion[q.id], t.status == .draft else { continue }
            let d = ComponentsSetup.questionDraft(q, system: system)
            var changed = false
            if t.title != d.title || t.body != d.body { try update(t.id, title: d.title, body: d.body, actor: .hatch); changed = true }
            if try questionOptions(ticketId: t.id) != d.options { try setQuestionOptions(ticketId: t.id, d.options); changed = true }
            if changed { updated += 1 }
        }
        return (added, dropped, updated)
    }
}

public extension ComponentSystem {
    /// Applies a choice made in Decide on a prepared Question ticket (its option key is the option's index).
    /// Returns false when the ticket is not a design system question, or the question is already answered.
    @discardableResult
    mutating func applyDecided(ticketBody: String, choice: String, decision: String?, ticketId: Int? = nil) throws -> Bool {
        let change = ticketId.map { ComponentsSetup.changeQuestionId(ticketId: $0) }
        guard let id = ComponentsSetup.componentQuestionId(inBody: ticketBody) ?? change, questions.contains(where: { $0.id == id }),
              let index = Int(choice) else { return false }
        try answer(id, option: index, decision: decision)
        return true
    }
}
