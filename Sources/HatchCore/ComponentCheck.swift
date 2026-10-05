import Foundation

// Keeping code on the roles (decisions DS7, workflow D): every control the inventory finds is compared with the role
// table. Free: it reuses the inventory's text pass, so it runs on every `hatch ready` and every rescan. A text check
// can misread, which is why a finding asks (fix it, make a variant, or allow it here) and never fails a build on its own.

public struct ComponentFinding: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        /// Styled by hand with a look that differs from the role for its place.
        case mismatch
        /// Styled by hand, but exactly the role's look: swap the styles for the role, nothing visible changes.
        case couldUseRole
        /// No role for this element, place and importance yet: a question for the owner, never a licence to invent.
        case noRole
        /// Uses a role outside the places it is meant for.
        case wrongPlace
        /// Uses a role the system does not have.
        case unknownRole
        /// More of a role on one screen than it allows (two main actions).
        case tooMany
        /// A rule of the system is broken (NF4); `role` holds the rule's id.
        case rule

        public var title: String {
            switch self {
            case .mismatch: "Differs from its role"
            case .couldUseRole: "Could use its role"
            case .noRole: "No role yet"
            case .wrongPlace: "Role used out of place"
            case .unknownRole: "Unknown role"
            case .tooMany: "Too many on one screen"
            case .rule: "Breaks a rule"
            }
        }
    }

    public var kind: Kind
    public var element: String
    public var place: String?
    /// The role that applies here, or the one used.
    public var role: String?
    public var file: String
    public var line: Int
    /// The look found in the code.
    public var look: String
    /// One plain sentence: what is wrong and what to do.
    public var message: String
    /// True when the place came from the code's structure (about 80% right in audits); a place guessed from a name or the
    /// page default is right far less often, so such findings are shown as unsure and never pressed on an agent.
    public var certain: Bool = true

    public var location: String { "\(file):\(line)" }
}

public enum ComponentCheck {
    /// Every finding for these uses, in file and line order.
    /// `areaOf` maps a file to its area (the project's areas and their folders), for areas that follow macOS.
    public static func findings(_ uses: [ComponentInventory.Use], system: ComponentSystem, areaOf: ((String) -> String?)? = nil) -> [ComponentFinding] {
        var out: [ComponentFinding] = []
        for u in uses {
            if let f = finding(u, system: system, area: areaOf?(u.file)) { out.append(f) }
        }
        out += tooMany(uses, system: system)
        return out.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
    }

    static func finding(_ u: ComponentInventory.Use, system: ComponentSystem, area: String? = nil) -> ComponentFinding? {
        let look = u.signature
        func make(_ kind: ComponentFinding.Kind, _ role: String?, _ message: String) -> ComponentFinding {
            let certain = u.evidence == "structure" || kind == .unknownRole
            return ComponentFinding(kind: kind, element: u.element, place: u.place, role: role, file: u.file, line: u.line, look: look,
                                    message: certain ? message : message + " (Place guessed from \(u.evidence == "name" ? "a name" : "the screen"); check it first.)",
                                    certain: certain)
        }
        let placeTitle = ComponentPlace.title(u.place).lowercased()
        if let used = u.role {
            guard let role = system.role(used) else {
                return make(.unknownRole, used, "Uses \(used), which the system does not have. Use one of its roles, or ask for a new one.")
            }
            if let place = u.place, !role.places.contains(place), role.status != .inRedesign {
                let better = system.role(element: u.element, place: place, importance: role.importance)
                    ?? ComponentRole.Importance.allCases.lazy.compactMap { system.role(element: u.element, place: place, importance: $0) }.first
                return make(.wrongPlace, used, "\(used) is not meant for a \(placeTitle)"
                            + (better.map { "; use \($0.id) (\($0.codeName)) there." } ?? "; no role covers this place yet, so ask."))
            }
            return nil
        }
        guard let place = u.place, let element = ComponentElement.named(u.element) else { return nil }
        // Where macOS decides (NF3), any look written by hand fights it.
        if system.followsMacOS(element: u.element, place: place, importance: u.importance, area: area) {
            let set = element.look(u.recipe).filter { $0.value != defaultValue($0.key, element: element) && !($0.key == "label") }
            guard !set.isEmpty else { return nil }
            return make(.mismatch, system.role(element: u.element, place: place, importance: u.importance)?.id,
                        "This follows macOS: remove \(set.keys.sorted().map { "\($0) \(set[$0]!)" }.joined(separator: ", ")) and let the system draw it.")
        }
        guard let role = system.role(element: u.element, place: place, importance: u.importance) else {
            return make(.noRole, nil, "No role for a \(element.title.lowercased()) at \(u.importance.title.lowercased()) importance in a \(placeTitle) yet. Ask with hatch ask (suggest the nearest role), do not invent a look.")
        }
        if role.status == .inRedesign { return nil }
        // Menu and alert items are drawn by the system; their look cannot differ.
        if place == "contextMenu" || place == "alert" { return nil }
        let differences = differencesFromRole(u.recipe, role: role, element: element)
        if !differences.isEmpty, role.configurable { return nil }  // becomes an app setting (NF5): other looks are fine for now
        if differences.isEmpty {
            return make(.couldUseRole, role.id, "Matches \(role.id): write \(role.codeName) instead of the styles.")
        }
        return make(.mismatch, role.id, "Differs from \(role.id) (\(role.codeName)): \(differences.joined(separator: ", ")). Use the role, or ask whether this needs a variant.")
    }

    /// "style bordered (role: glass)" for each look setting the role names that the code does differently. The role's
    /// variants count as its looks too. Settings the role leaves open, and labels the scanner could not read, never differ.
    public static func differencesFromRole(_ recipe: [String: String], role: ComponentRole, element: ComponentElement) -> [String] {
        func diffs(_ target: [String: String]) -> [String] {
            element.look(target).keys.sorted().compactMap { key in
                let want = target[key]!, have = recipe[key] ?? defaultValue(key, element: element)
                if key == "label", have == "custom" { return nil }
                if key == "show" { return nil }  // shown on hover is decided by the row, not seen in the button
                return have == want ? nil : "\(key) \(have) (role: \(want))"
            }
        }
        let main = diffs(role.recipe)
        if main.isEmpty { return [] }
        for v in role.variants {
            let merged = role.recipe.merging(v.recipe) { $1 }
            if diffs(merged).isEmpty { return [] }
        }
        return main
    }

    /// What a setting is when the code does not say: the system's default.
    static func defaultValue(_ key: String, element: ComponentElement) -> String {
        switch key {
        case "style": return "automatic"
        case "size": return "regular"
        case "shape": return "automatic"
        case "tint": return "none"
        case "indicator": return "visible"
        case "look": return "automatic"
        default: return element.parameter(key)?.values.first ?? ""
        }
    }

    /// A role with "at most N per screen" used more often in one view.
    static func tooMany(_ uses: [ComponentInventory.Use], system: ComponentSystem) -> [ComponentFinding] {
        var out: [ComponentFinding] = []
        var groups: [String: [(ComponentInventory.Use, ComponentRole)]] = [:]
        for u in uses {
            guard let view = u.view, let place = u.place else { continue }
            let role = u.role.flatMap { system.role($0) } ?? system.role(element: u.element, place: place, importance: u.importance)
            guard let role, let limit = role.perScreen, limit > 0 else { continue }
            groups["\(u.file)|\(view)|\(role.id)", default: []].append((u, role))
        }
        for (_, list) in groups {
            let sorted = list.sorted { $0.0.line < $1.0.line }
            guard let limit = sorted.first?.1.perScreen else { continue }
            // Only uses that can be on screen together count: not the other branch of an `if` or `switch`.
            var shown: [(ComponentInventory.Use, ComponentRole)] = [], extra: [(ComponentInventory.Use, ComponentRole)] = []
            for item in sorted {
                let together = shown.filter { !ComponentInventory.exclusive($0.0, item.0) }
                if together.count >= limit { extra.append(item) } else { shown.append(item) }
            }
            for (u, role) in extra {
                out.append(ComponentFinding(kind: .tooMany, element: u.element, place: u.place, role: role.id, file: u.file, line: u.line,
                                            look: u.signature,
                                            message: "\(u.view ?? "This view") shows \(shown.count + extra.count) uses of \(role.id) at once; it allows \(limit) per screen. Make the others \(system.role(element: u.element, place: u.place ?? "", importance: .other)?.id ?? "another role"), or ask."))
            }
        }
        return out
    }

    /// Everything for an app folder: the role findings and the rule findings (NF4).
    public static func all(appRoot: String, excluding: [String] = [], system: ComponentSystem, areaOf: ((String) -> String?)? = nil)
        -> (inventory: ComponentInventory, findings: [ComponentFinding]) {
        let files = ComponentInventoryScanner.appFiles(appRoot: appRoot, excluding: excluding)
        let inv = ComponentInventoryScanner.inventory(files: files)
        let found = findings(inv.uses, system: system, areaOf: areaOf) + ComponentRuleCheck.findings(files: files, uses: inv.uses, system: system)
        return (inv, found.sorted { ($0.file, $0.line) < ($1.file, $1.line) })
    }

    /// How much of the app already follows the system: uses through a role, uses whose look already matches their
    /// role (a mechanical swap), and all uses with a known place.
    public static func coverage(_ uses: [ComponentInventory.Use], system: ComponentSystem) -> (usingRole: Int, matching: Int, total: Int) {
        var usingRole = 0, matching = 0, total = 0
        for u in uses where u.place != nil {
            total += 1
            if u.role != nil { usingRole += 1; continue }
            if let f = finding(u, system: system) { if f.kind == .couldUseRole { matching += 1 } }
            else { matching += 1 }  // menu items, alerts, roles in redesign: nothing to change
        }
        return (usingRole, matching, total)
    }

    /// The lines a unified diff adds, per file (new side), for checking only what a ticket wrote.
    public static func addedLines(diff: String) -> [String: Set<Int>] {
        var out: [String: Set<Int>] = [:], file: String?, lineNo = 0
        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("+++ ") {
                let path = String(line.dropFirst(4))
                file = path == "/dev/null" ? nil : (path.hasPrefix("b/") ? String(path.dropFirst(2)) : path)
            } else if line.hasPrefix("@@") {
                if let plus = line.split(separator: " ").first(where: { $0.hasPrefix("+") }),
                   let start = Int(plus.dropFirst().split(separator: ",").first ?? "") { lineNo = start }
            } else if line.hasPrefix("+"), !line.hasPrefix("+++") {
                if let f = file { out[f, default: []].insert(lineNo) }
                lineNo += 1
            } else if line.hasPrefix(" ") {
                lineNo += 1
            }
        }
        return out
    }

    /// Findings on the lines a diff adds.
    public static func inDiff(_ findings: [ComponentFinding], diff: String) -> [ComponentFinding] {
        let added = addedLines(diff: diff)
        return findings.filter { added[$0.file]?.contains($0.line) ?? false }
    }
}
