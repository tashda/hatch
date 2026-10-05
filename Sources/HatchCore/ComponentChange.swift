import Foundation

// Changing a component (decision CP3). The owner starts on the Components page with Change… on a role: what should
// change, and where (everywhere, or only in one place or area, which makes a variant). Hatch files a Proposal tied to the
// role. The agent offers two to four looks as recipes, not a Stage round, so it costs a short JSON file and no build.
// Hatch checks every recipe against the catalog, turns the looks into a question on the role (drawn in place by the
// Components Designer and its live window) and into options on the Proposal (answered in Decide). Choosing a look makes
// the role's draft and accepts the Proposal; when an agent takes it to build, Hatch applies the draft (the next baseline
// version) and the Proposal becomes the code and migration work.

public extension ComponentsSetup {
    /// The line that ties a Proposal to the role it changes.
    static func changeMarker(_ role: String) -> String { "Design system change: `\(role)`" }

    /// The role a change Proposal is about, from its marker.
    static func changedRole(inBody body: String) -> String? { value(after: "Design system change: `", in: body) }

    /// Where the change applies, from its marker: nil place and area mean everywhere.
    static func changeScope(inBody body: String) -> (place: String?, area: String?) {
        (value(after: "Change only in place: `", in: body), value(after: "Change only in area: `", in: body))
    }

    /// The design system question a change Proposal's looks become.
    static func changeQuestionId(ticketId: Int) -> String { "change.\(ticketId)" }

    private static func value(after prefix: String, in body: String) -> String? {
        guard let r = body.range(of: prefix) else { return nil }
        let rest = body[r.upperBound...]
        return rest.firstIndex(of: "`").map { String(rest[..<$0]) }
    }

    /// The Proposal for a change the owner asked for. Its body carries what the agent needs, so the brief stays small:
    /// today's look, the settings the element has, and the file format.
    static func changeDraft(role: ComponentRole, what: String, place: String? = nil, area: String? = nil, system: ComponentSystem) -> Draft {
        let scope: String
        if let place { scope = "Only in \(ComponentPlace.title(place).lowercased()): it becomes a variant of the role there." }
        else if let area { scope = "Only in the \(area) area: it becomes a variant of the role there." }
        else { scope = "Everywhere the role is used." }
        let today = role.followsMacOS ? "follows macOS" : role.lookSummary
        let settings = ComponentElement.named(role.element)?.parameters.filter(\.isLook).map { p in
            "- `\(p.id)`: " + p.values.joined(separator: ", ") + (p.foundation.map { " (or a \($0.rawValue) foundation id)" } ?? "")
        } ?? []
        let title = "Change \(role.title.lowercased())" + (place.map { " in \(ComponentPlace.title($0).lowercased())" } ?? area.map { " in \($0)" } ?? "")
        var body = """
            \(what.trimmingCharacters(in: .whitespacesAndNewlines))

            Role `\(role.id)` (\(role.title)): \(role.use) Today: \(today). \(scope)

            Offer two to four looks as recipes, not a Stage round: write `looks.json` and run `hatch offer <ticket> --components looks.json`. A recipe uses only these settings and values:
            \(settings.joined(separator: "\n"))

            ```json
            {"summary": "What differs between the looks, and which you would pick.",
             "looks": [{"id": "a", "title": "Short name", "recipe": {"style": "glassProminent"}, "gain": "One line.", "cost": "One line."}],
             "recommended": "a", "why": "The reason, and what the others cost."}
            ```

            Hatch draws the looks in their places in the Components Designer and in Decide. Do not change the app's code on this ticket until it is accepted.

            \(changeMarker(role.id))
            """
        if let place { body += "\n" + "Change only in place: `\(place)`" }
        if let area { body += "\n" + "Change only in area: `\(area)`" }
        var d = Draft(type: .proposal, title: title, body: body + "\n")
        d.area = Self.area
        return d
    }
}

/// What an agent hands in for a change Proposal: two to four looks for one role.
public struct ComponentChangeOffer: Codable, Equatable, Sendable {
    public struct Look: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var recipe: [String: String]
        public var gain: String?
        public var cost: String?
        public init(id: String, title: String, recipe: [String: String], gain: String? = nil, cost: String? = nil) {
            self.id = id; self.title = title; self.recipe = recipe; self.gain = gain; self.cost = cost
        }
    }

    /// One problem the agent can fix: a stable code, what is wrong, and how to fix it.
    public struct Problem: Equatable, Sendable {
        public var code: String
        public var message: String
        public var fix: String
    }

    public var summary: String
    public var looks: [Look]
    public var recommended: String?
    public var why: String?

    public init(summary: String = "", looks: [Look], recommended: String? = nil, why: String? = nil) {
        self.summary = summary; self.looks = looks; self.recommended = recommended; self.why = why
    }

    public static func parse(data: Data) throws -> ComponentChangeOffer {
        try JSONDecoder().decode(ComponentChangeOffer.self, from: data)
    }

    /// The gate for a change offer, run while the agent can still fix it. Every recipe is checked as the role's look in
    /// a copy of the system, so the same rules apply as anywhere else.
    public func problems(role roleId: String, system: ComponentSystem) -> [Problem] {
        guard let i = system.roles.firstIndex(where: { $0.id == roleId }), let element = ComponentElement.named(system.roles[i].element) else {
            return [Problem(code: "change.role", message: "The design system has no role `\(roleId)`.", fix: "Ask the owner; the role may have been renamed.")]
        }
        var out: [Problem] = []
        if !(2...4).contains(looks.count) {
            out.append(Problem(code: "looks.count", message: "There \(looks.count == 1 ? "is 1 look" : "are \(looks.count) looks"); the owner needs 2 to 4 to choose between.",
                               fix: "Offer 2 to 4 different looks."))
        }
        if Set(looks.map(\.id)).count != looks.count {
            out.append(Problem(code: "looks.ids", message: "Two looks share an id.", fix: "Give each look its own short id."))
        }
        let today = system.roles[i].recipe
        for look in looks {
            if !look.recipe.isEmpty, element.look(look.recipe) == element.look(today) && !system.roles[i].followsMacOS {
                out.append(Problem(code: "look.today", message: "Look '\(look.id)' is today's look.", fix: "Offer looks that differ from today; the owner can always keep today's."))
            }
            out += system.problems(look: look.recipe, forRole: roleId, label: "Look '\(look.id)'")
            if (look.gain ?? "").trimmingCharacters(in: .whitespaces).isEmpty || (look.cost ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                out.append(Problem(code: "look.gain-cost", message: "Look '\(look.id)' has no gain or cost.", fix: "Add one line of what it gains and one of what it costs."))
            }
        }
        if let r = recommended, looks.contains(where: { $0.id == r }) {
            if (why ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                out.append(Problem(code: "recommend.why", message: "The recommendation has no reason.", fix: "Say why in \"why\", and what the others cost."))
            }
        } else {
            out.append(Problem(code: "recommend.missing", message: "No look is recommended.", fix: "Set \"recommended\" to the id of the look you would ship, and say why."))
        }
        return out
    }

    /// The looks as a question on the role, with "Keep today's look" last.
    public func question(role: ComponentRole, ticketId: Int, ticketTitle: String, place: String?, area: String?) -> ComponentQuestion {
        var options = looks.map { ComponentQuestion.Option(title: $0.title, recipe: $0.recipe, effect: $0.gain ?? "") }
        options.append(.init(title: "Keep today's look", effect: "Nothing changes; the Proposal is dropped."))
        var q = ComponentQuestion(id: ComponentsSetup.changeQuestionId(ticketId: ticketId), kind: .change, role: role.id, title: ticketTitle,
                                  options: options, recommended: looks.firstIndex { $0.id == recommended } ?? 0, reason: why ?? "")
        q.ticket = ticketId; q.place = place; q.area = area
        return q
    }

    /// The same choice as options on the Proposal, for Decide. Keys are the question's option indexes.
    public var decideOptions: [QuestionOption] {
        looks.enumerated().map { i, l in
            QuestionOption(key: String(i), title: l.title, detail: ComponentRole.summary(l.recipe), recommended: l.id == recommended,
                           why: l.id == recommended ? why : nil, gain: l.gain, cost: l.cost)
        } + [QuestionOption(key: String(looks.count), title: "Keep today's look", detail: "Drops the Proposal.",
                            gain: "Nothing changes.", cost: "The change you asked for does not happen.")]
    }
}

public extension ComponentSystem {
    /// Puts an offer's question on the system, replacing the one from an earlier revision.
    mutating func addChange(_ q: ComponentQuestion) {
        questions.removeAll { $0.id == q.id }
        questions.append(q)
    }

    /// A change Proposal's question, when it is still open.
    func changeQuestion(ticketId: Int) -> ComponentQuestion? {
        questions.first { $0.id == ComponentsSetup.changeQuestionId(ticketId: ticketId) }
    }

    /// Applies a change Proposal's draft when an agent starts building it: the next baseline version. Returns true when
    /// something was applied.
    @discardableResult
    mutating func applyChange(ticketBody: String, decision: String?) throws -> Bool {
        guard let roleId = ComponentsSetup.changedRole(inBody: ticketBody), role(roleId)?.draft != nil else { return false }
        return try !applyDrafts(roleId, decision: decision).isEmpty
    }
}

public extension HatchStore {
    /// The owner's choice on a change Proposal (CP3), from Decide, the ticket or the Designer: a look accepts the
    /// Proposal (its build applies the look), "Keep today's look" (the last option) drops it. The caller changes the
    /// system itself, since only it knows the notebook.
    @discardableResult
    func decideComponentChange(ticketId: Int, choice key: String, reason: String?) throws -> Ticket {
        try db.transaction {
            guard let t = try ticket(id: ticketId), t.type == .proposal, ComponentsSetup.changedRole(inBody: t.body) != nil else {
                throw StoreError.invalid("Ticket \(ticketId) is not a design system change.")
            }
            let options = try questionOptions(ticketId: ticketId)
            guard let chosen = options.first(where: { $0.key == key }) else { throw StoreError.invalid("\(t.displayNumber) has no option \(key).") }
            let note = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            if chosen.key == options.last?.key {
                let moved = try move(ticketId, to: .dropped, actor: .owner, reason: "kept today's look")
                _ = try recordDecision(ticketId: ticketId, kind: .design, title: t.title, summary: "Kept today's look.", area: t.area,
                                       options: options.map { DecisionOption(key: $0.key, title: $0.title, detail: $0.detail) },
                                       choice: chosen.key, recommended: options.first(where: \.recommended)?.key, reason: note?.isEmpty == false ? note : nil)
                return moved
            }
            if let note, !note.isEmpty { try addNote(ticketId, kind: .instruction, author: "owner", body: note) }
            return try acceptProposal(ticketId: ticketId, choices: ["look": chosen.title]).ticket
        }
    }
}

public extension HatchStore {
    /// Files a change the owner asked for on the Components page or in the Designer (CP3). Hatch wrote the whole
    /// ticket from the system, so it skips Iris's check (no model call) and goes straight to Ready for an agent.
    @discardableResult
    func fileComponentChange(projectId: Int, _ d: ComponentsSetup.Draft) throws -> Ticket {
        try db.transaction {
            let t = try createTicket(projectId: projectId, type: d.type, title: d.title, body: d.body, area: d.area)
            _ = try move(t.id, to: .checking, actor: .owner, reason: "asked on the Components page")
            return try move(t.id, to: .ready, actor: .hatch, reason: "a design system change Hatch wrote; nothing to check")
        }
    }
}

// MARK: - A design for a role, from anywhere (decision SW6)

public extension ComponentSystem {
    /// Checks one look for a role as if it were the role's own: only the element's settings, only their values or a named
    /// value of the right kind, and the system still valid with it. The gate for a change offer and for a Sweep that
    /// names a role. `label` names the look in the messages. Empty means it can be saved.
    func problems(look recipe: [String: String], forRole roleId: String, label: String = "The look") -> [ComponentChangeOffer.Problem] {
        typealias Problem = ComponentChangeOffer.Problem
        guard let i = roles.firstIndex(where: { $0.id == roleId }), let element = ComponentElement.named(roles[i].element) else {
            return [Problem(code: "change.role", message: "The design system has no role `\(roleId)`.", fix: "Use a role from `hatch components roles`, or ask the owner.")]
        }
        guard !recipe.isEmpty else {
            return [Problem(code: "look.empty", message: "\(label) has no recipe.", fix: "Set at least one setting, for example {\"style\": \"bordered\"}.")]
        }
        var out: [Problem] = []
        for (key, value) in recipe.sorted(by: { $0.key < $1.key }) {
            guard let p = element.parameter(key) else {
                out.append(Problem(code: "look.setting", message: "\(label): \(element.title) has no setting `\(key)`.",
                                   fix: "Use only: " + element.parameters.map(\.id).joined(separator: ", ") + "."))
                continue
            }
            let named = foundations.filter { p.foundation == $0.kind }.map(\.id)
            if !p.values.contains(value) && !named.contains(value) {
                out.append(Problem(code: "look.value", message: "\(label): `\(key)` cannot be \"\(value)\".",
                                   fix: "Use one of: " + (p.values + named).joined(separator: ", ") + "."))
            }
        }
        // The whole system with it, once the settings themselves are right (so one mistake is said once).
        guard out.isEmpty else { return out }
        var copy = self
        copy.roles[i].recipe = recipe
        copy.roles[i].draft = nil
        copy.roles[i].followsMacOS = false
        let before = problems()
        for p in copy.problems() where p.contains(roleId) && !before.contains(p) {
            out.append(Problem(code: "look.rule", message: "\(label): \(p)", fix: "Change the recipe so the system stays valid."))
        }
        return out
    }

    /// Saves a design the owner accepted as the role's look: the role's draft, applied as the next baseline version when
    /// the work is built, or a variant when the design is only for one place or area. Refuses a look with problems.
    /// Hatch writes the system; the caller commits the notebook (the app with NotebookWriter, the API with its hook).
    mutating func acceptDesign(role roleId: String, look recipe: [String: String], place: String? = nil, area: String? = nil,
                               use: String, decision: String?) throws {
        if let first = problems(look: recipe, forRole: roleId).first { throw StoreError.invalid(first.message + " " + first.fix) }
        if let scope = place ?? area {
            try addVariant(to: roleId, id: place ?? "area-" + HatchStore.slug(scope),
                           use: place != nil ? "In \(ComponentPlace.title(scope).lowercased()): \(use)" : "In the \(scope) area: \(use)",
                           recipe: recipe, places: place.map { [$0] })
        } else {
            try setLook(roleId, recipe: recipe)
        }
        if let i = roles.firstIndex(where: { $0.id == roleId }) { roles[i].decision = decision ?? roles[i].decision }
    }
}
