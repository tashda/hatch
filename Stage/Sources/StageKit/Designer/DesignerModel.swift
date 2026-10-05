import SwiftUI
import Combine
import HatchCore
import HatchComponentKit
import HatchAPI

// The Components Designer (decision DS1): one place to judge and decide the design system. It reads the system from
// Hatch (or a notebook folder when run on its own) and the app's inventory from the app's folder, and changes the
// system only through Hatch (DS2). Nothing here calls a model.

/// Where the Designer reads the system and sends changes.
protocol ComponentsSource {
    func load() throws -> ComponentSystem
    /// One change: answer, agree, look, apply, discard, variant. Returns the system after it.
    func change(_ action: String, _ body: JSONValue) throws -> ComponentSystem
    /// True when changes are kept only in this window (a demo, or a notebook opened without Hatch).
    var isLocal: Bool { get }
}

/// Changes kept in memory: the demo, tests, and a notebook opened read-only.
final class LocalComponentsSource: ComponentsSource {
    private var system: ComponentSystem

    init(system: ComponentSystem) { self.system = system }
    var isLocal: Bool { true }
    func load() throws -> ComponentSystem { system }

    func change(_ action: String, _ body: JSONValue) throws -> ComponentSystem {
        func recipe() -> [String: String] { body["recipe"]?.objectValue?.compactMapValues(\.stringValue) ?? [:] }
        let role = body["role"]?.stringValue
        switch action {
        case "answer":
            let id = body["question"]?.stringValue ?? ""
            let role = system.questions.first { $0.id == id }?.role
            try system.answer(id, option: body["option"]?.intValue ?? -1)
            if body["setting"]?.boolValue == true, let role { try system.makeConfigurable(role) }
            return system
        case "agree": try system.agree(role)
        case "look": try system.setLook(role ?? "", recipe: recipe())
        case "apply": try system.applyDrafts(role)
        case "discard": try system.discardDraft(role ?? "")
        case "variant": try system.addVariant(to: role ?? "", id: body["id"]?.stringValue ?? "variant", use: body["use"]?.stringValue ?? "", recipe: recipe())
        case "follow":
            if let role { try system.followMacOS(role: role) }
            else { try system.followMacOS(ComponentFollow(element: body["element"]?.stringValue, place: body["place"]?.stringValue, area: body["area"]?.stringValue)) }
        case "unfollow": system.stopFollowing(body["scope"]?.stringValue ?? "")
        case "setting": try system.makeConfigurable(body["id"]?.stringValue ?? "")
        case "rule":
            let kind = body["kind"]?.stringValue ?? ""
            if kind == "note" {
                system.rules.append(ComponentRule(id: "note-\(system.rules.filter { $0.kind == "note" }.count + 1)", kind: "note", value: "text",
                                                  text: body["text"]?.stringValue ?? "", status: .agreed))
            } else if let info = ComponentRuleKind.named(kind), let value = body["value"]?.stringValue {
                system.rules.removeAll { $0.kind == kind }
                system.rules.append(ComponentRule(id: kind, kind: kind, value: value, text: info.says(value), status: .agreed))
            }
        case "removeRule": system.rules.removeAll { $0.id == body["id"]?.stringValue }
        case "rename": try system.rename(role ?? "", title: body["title"]?.stringValue ?? "")
        case "restore":
            if let json = body["system"]?.stringValue { system = try JSONDecoder().decode(ComponentSystem.self, from: Data(json.utf8)) }
        default: break
        }

        return system
    }
}

/// Through Hatch's local API: Hatch writes the notebook and commits it.
final class HatchComponentsSource: ComponentsSource {
    let project: String
    let client: StageClient
    init(project: String, home: URL?) {
        self.project = project
        client = home.map { StageClient(paths: HatchPaths(home: $0)) } ?? StageClient()
    }
    var isLocal: Bool { false }
    func load() throws -> ComponentSystem { try client.components(project: project) }
    func change(_ action: String, _ body: JSONValue) throws -> ComponentSystem {
        try client.changeComponents(project: project, action: action, body: body)
    }
}

/// What the main area shows for the selected element (CD10: Today vs Draft lives inside a role).
enum DesignerMode: String, CaseIterable, Identifiable {
    case inPlace, matrix
    var id: String { rawValue }
    var title: String {
        switch self { case .inPlace: "In Place"; case .matrix: "Matrix" }
    }
}

/// How the canvas is drawn (CD15): light, dark, or each place in both side by side. Only the canvas and the live
/// window change; the inspector stays as the system draws it.
enum DesignerAppearance: String, CaseIterable, Identifiable {
    case light, dark, both
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// A look being tried on a role and drawn everywhere it sits, not saved until Keep (CD13).
struct DesignerPreview: Equatable {
    var role: String
    var recipe: [String: String]
    /// Following macOS: no look of its own.
    var follow = false
    /// The open question's option it comes from, so Keep answers it.
    var option: Int?
    /// What it is, for the canvas and the undo menu ("Glass", "Most used", "Style: Filled").
    var label: String
}

/// What the sidebar selects.
enum DesignerSelection: Hashable {
    /// Every element in every place, as one drawn matrix (CD33).
    case all
    /// One place with every element in it (CD9).
    case place(String)
    case foundations(ComponentFoundation.Kind)
    case element(String)
    case rules
}

@MainActor
final class DesignerModel: ObservableObject {
    @Published private(set) var system: ComponentSystem
    @Published private(set) var inventory: ComponentInventory?
    @Published var selection: DesignerSelection?
    @Published var selectedRole: String?
    @Published var mode: DesignerMode = .inPlace
    @Published var sample = SampleContent()
    @Published var appearance: DesignerAppearance
    @Published var largeText = false
    /// Draws prominent controls as in a window that is not in front (CD15).
    @Published var inactive = false
    /// The role is open on its own level (CD8): "‹ Buttons · Main action", drawn in every place it sits.
    @Published var focused = false
    /// The look being tried, if any (CD13).
    @Published private(set) var preview: DesignerPreview?
    /// Systems before each kept change, newest last, for ⌘Z (CD23).
    @Published private(set) var undoStack: [(label: String, system: ComponentSystem)] = []
    /// The appearance of the Mac when the Designer opened, so Light and Dark are explicit (B1: macOS doesn't go back from a
    /// forced dark appearance when it is set to "none").
    let systemScheme: ColorScheme

    /// Dark or not, for the snapshot run and the live window.
    var dark: Bool {
        get { appearance == .dark }
        set { appearance = newValue ? .dark : .light }
    }
    /// The live window's scheme: Both shows it light.
    var liveScheme: ColorScheme { appearance == .dark ? .dark : .light }
    /// A problem worth showing: Hatch is away, or a change was refused.
    @Published private(set) var notice: String?
    @Published private(set) var busy = false

    let source: ComponentsSource
    let appName: String
    /// The live window's state, and how to open it (the app delegate sets it).
    let live = LiveState()
    var openLiveWindow: (() -> Void)?

    init(source: ComponentsSource, inventory: ComponentInventory? = nil) throws {
        self.source = source
        let s = try source.load()
        system = s
        appName = s.name
        self.inventory = inventory
        let scheme: ColorScheme = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        systemScheme = scheme
        appearance = scheme == .dark ? .dark : .light
        selection = s.elementsUsed.first.map { .element($0) }
        selectedRole = s.elementsUsed.first.flatMap { s.roles(of: $0).first?.id }
    }

    // MARK: Reading

    var selectedElement: String? { if case .element(let e) = selection { return e }; return nil }
    var selectedPlace: String? { if case .place(let p) = selection { return p }; return nil }
    /// The selection draws looks on the canvas (an element, a place or all), so hard cases and roles apply.
    var showsCanvas: Bool {
        switch selection { case .element?, .place?, .all?: true; default: false }
    }

    /// Open questions about roles that sit in a place.
    func questions(inPlace place: String) -> [ComponentQuestion] {
        system.questions.filter { q in q.role.flatMap { system.role($0) }?.places.contains(place) ?? false }
    }

    /// The places any role sits in, in the catalog's order.
    var placesUsed: [ComponentPlace] {
        let ids = Set(system.roles.flatMap(\.places))
        return system.allPlaces.filter { ids.contains($0.id) }
    }
    var role: ComponentRole? { selectedRole.flatMap { system.role($0) } }

    /// The look a role is drawn with now: the preview, then its draft, then its look.
    func look(of role: ComponentRole) -> [String: String] {
        if let p = preview, p.role == role.id { return p.recipe }
        return role.draft ?? role.recipe
    }
    func isPreviewing(_ role: ComponentRole) -> Bool { preview?.role == role.id }

    /// The open look question about a role, if any.
    func question(for role: ComponentRole) -> ComponentQuestion? { system.questions.first { $0.role == role.id } }

    /// Every open question, element by element in the sidebar's order, for the toolbar's queue (CD27).
    var queue: [ComponentQuestion] {
        system.elementsUsed.flatMap { questions(for: $0) }
    }

    /// Opens a role on its own level, closing any preview of another role. From a place or All it stays there, so
    /// going back returns to where it was opened (CD9).
    func open(_ roleId: String) {
        if preview?.role != roleId { preview = nil }
        selectedRole = roleId
        if let r = system.role(roleId), !showsCanvas || (selectedElement != nil && selectedElement != r.element) { selection = .element(r.element) }
        focused = true
    }

    /// Back to the element (Esc).
    func back() { preview = nil; focused = false }

    /// The next question after the selected role's, anywhere (⌘]).
    func nextQuestion(forward: Bool = true) {
        let list = queue
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.role == selectedRole }
        let next = i.map { list[(($0 + (forward ? 1 : -1)) % list.count + list.count) % list.count] } ?? list[0]
        if let r = next.role { open(r) }
    }

    /// The looks worth trying on a role when nothing is asked about it (CD18): the current look, macOS's default,
    /// each template's look, and the app's most used look, each named by where it comes from, duplicates merged.
    func picks(for role: ComponentRole) -> [(label: String, recipe: [String: String], follow: Bool)] {
        guard let element = ComponentElement.named(role.element) else { return [] }
        var out: [(label: String, recipe: [String: String], follow: Bool)] = []
        func add(_ label: String, _ recipe: [String: String], follow: Bool = false) {
            let key = element.withoutDefaults(element.look(recipe))
            if let i = out.firstIndex(where: { element.withoutDefaults(element.look($0.recipe)) == key && $0.follow == follow }) {
                out[i].label += " · " + label
            } else { out.append((label, recipe, follow)) }
        }
        add("Current", role.draft ?? role.recipe, follow: role.followsMacOS)
        let behaviour = role.recipe.filter { element.parameter($0.key)?.isLook == false }
        add("macOS default", behaviour, follow: true)
        for t in ComponentTemplates.all {
            let ref = t.system(name: "ref").roles(of: role.element)
                .filter { $0.importance == role.importance && !Set($0.places).isDisjoint(with: role.places) }.first
            if let ref { add(t.title, ref.recipe, follow: ref.followsMacOS) }
        }
        if let top = looksToday(role).first { add("Most used in the app", top.look.merging(behaviour) { a, _ in a }) }
        return Array(out.prefix(5))
    }
    func questions(for element: String) -> [ComponentQuestion] {
        system.questions.filter { q in q.role.map { system.role($0)?.element == element } ?? false }
    }

    /// The app's uses that fall in a role's cells (its element, importance and places).
    func uses(of role: ComponentRole) -> [ComponentInventory.Use] {
        inventory?.uses.filter { $0.element == role.element && $0.importance == role.importance && $0.place.map(role.places.contains) == true } ?? []
    }

    /// The looks in use today for a role, most used first.
    func looksToday(_ role: ComponentRole) -> [(look: [String: String], count: Int, examples: [String])] {
        guard let element = ComponentElement.named(role.element) else { return [] }
        var order: [[String: String]] = [], groups: [[String: String]: [ComponentInventory.Use]] = [:]
        for u in uses(of: role) {
            let look = element.look(u.recipe)
            if groups[look] == nil { order.append(look) }
            groups[look, default: []].append(u)
        }
        return order.map { ($0, groups[$0]!.count, Array(groups[$0]!.prefix(3).map(\.location))) }.sorted { $0.count > $1.count }
    }

    /// How many open questions an element has, for the sidebar.
    func openCount(_ element: String) -> Int { questions(for: element).count }

    /// The element's state in one word, for the sidebar dot.
    func state(of element: String) -> ComponentRole.Status? {
        let roles = system.roles(of: element)
        if roles.contains(where: { $0.status == .inRedesign }) { return .inRedesign }
        if roles.contains(where: { $0.status == .provisional }) { return .provisional }
        return roles.isEmpty ? nil : .agreed
    }

    // MARK: Changing (always through the source: Hatch writes)

    func answer(_ q: ComponentQuestion, option: Int, setting: Bool = false) {
        run("answer", ["question": .string(q.id), "option": .int(option), "setting": .bool(setting)])
    }
    /// Follow macOS (NF3): one role, or every role of an element in a place.
    func follow(_ role: ComponentRole) { run("follow", ["role": .string(role.id)]) }
    func follow(element: String, place: String) { run("follow", ["element": .string(element), "place": .string(place)]) }
    func unfollow(_ scope: ComponentFollow) { run("unfollow", ["scope": .string(scope.id)]) }
    /// "Make it a setting" (NF5) for a role or a rule; Hatch drafts the ticket.
    func makeSetting(_ id: String) { run("setting", ["id": .string(id)]) }
    /// Change… (CP3): Hatch files a Proposal for the role; the looks come back as a question.
    func change(_ role: ComponentRole, what: String) { run("change", ["role": .string(role.id), "what": .string(what)]) }
    /// A new title for a role (CD2); the id stays.
    func rename(_ role: ComponentRole, to title: String) { run("rename", ["role": .string(role.id), "title": .string(title)], label: "Rename \(role.title)") }
    func setRule(_ kind: String, _ value: String) { run("rule", ["kind": .string(kind), "value": .string(value)]) }
    func addNote(_ text: String) { run("rule", ["kind": "note", "text": .string(text)]) }
    func removeRule(_ id: String) { run("removeRule", ["id": .string(id)]) }

    /// Native advice (NF1) for a role.
    func advice(for role: ComponentRole) -> [ComponentAdvice] { system.advice().filter { $0.role == role.id } }
    func agree(_ role: ComponentRole) { run("agree", ["role": .string(role.id)]) }
    func agreeAll() { run("agree", [:]) }
    func discard(_ role: ComponentRole) { run("discard", ["role": .string(role.id)]) }
    func apply(_ role: ComponentRole?) { run("apply", role.map { ["role": .string($0.id)] } ?? [:]) }

    /// The values a setting can take for this system: its own and the system's foundations of its kind.
    func values(of parameter: ComponentParameter) -> [String] {
        parameter.values + system.foundations.filter { parameter.foundation == $0.kind }.map(\.id)
    }

    /// Tries a look on a role everywhere it sits, without saving (CD13).
    func tryLook(_ p: DesignerPreview) {
        preview = p
        if selectedRole != p.role { selectedRole = p.role }
    }

    /// Tries one setting of the selected role (Fine-tune, CD19). macOS's default removes the setting.
    func tryValue(_ parameter: ComponentParameter, _ value: String?) {
        guard let role else { return }
        var recipe = look(of: role)
        if let value, value != parameter.systemDefault { recipe[parameter.id] = value } else { recipe[parameter.id] = nil }
        let words = value.map { ComponentWords.value(element: role.element, parameter: parameter.id, value: $0) } ?? "macOS default"
        tryLook(DesignerPreview(role: role.id, recipe: recipe, label: "\(parameter.title): \(words)"))
    }

    /// Saves the preview as one change (CD23): an answer to the open question, Follow macOS, or a new look.
    func keep() {
        guard let p = preview, let role = system.role(p.role) else { return }
        preview = nil
        if let i = p.option, let q = question(for: role) {
            run("answer", ["question": .string(q.id), "option": .int(i), "setting": .bool(false)], label: "\(role.title): \(p.label)")
        } else if p.follow {
            run("follow", ["role": .string(role.id)], label: "\(role.title) follows macOS")
        } else {
            // Settings macOS uses anyway are left out (CD35), so nothing redundant is saved.
            let element = ComponentElement.named(role.element)
            let recipe = element.map { $0.withoutDefaults(p.recipe) } ?? p.recipe
            run("look", ["role": .string(role.id), "recipe": .object(recipe.mapValues { .string($0) })], label: "\(role.title): \(p.label)")
        }
    }

    /// The questions of an element that are easy (CD29): the recommendation is the template's look, or the look
    /// most of the uses already have (80% or more).
    func clearQuestions(_ element: String) -> [ComponentQuestion] {
        questions(for: element).filter { q in
            guard q.options.indices.contains(q.recommended) else { return false }
            if q.reason.contains("template's look") || q.reason.contains("lets macOS draw it") { return true }
            let total = q.options.reduce(0) { $0 + $1.count }
            return total > 0 && q.options[q.recommended].count * 5 >= total * 4
        }
    }

    /// Answers the easy questions with their recommendations; the roles stay provisional until agreed (DS8).
    func acceptClear(_ element: String) {
        for q in clearQuestions(element) {
            run("answer", ["question": .string(q.id), "option": .int(q.recommended), "setting": .bool(false)],
                label: "\(q.role.flatMap { system.role($0)?.title } ?? q.title): recommended")
        }
    }

    /// Drops the preview: the role is drawn as it is again (Esc).
    func discard() { preview = nil }

    /// Undoes the last kept change (⌘Z): Hatch writes the system as it was before it.
    func undo() {
        guard let last = undoStack.popLast(), let data = try? last.system.encoded() else { return }
        preview = nil
        run("restore", ["system": .string(String(decoding: data, as: UTF8.self)), "label": .string(last.label)], label: nil)
    }
    var undoLabel: String? { undoStack.last?.label }

    private func run(_ action: String, _ body: JSONValue, label: String? = "") {
        busy = true
        defer { busy = false }
        let before = system
        do {
            system = try source.change(action, body)
            notice = nil
            if let label, system != before { undoStack.append((label.isEmpty ? Self.describe(action) : label, before)) }
            if let id = selectedRole, system.role(id) == nil { selectedRole = nil; focused = false }
        } catch {
            notice = "\(error)"
        }
    }

    private static func describe(_ action: String) -> String {
        ["agree": "Agree", "apply": "Apply draft", "discard": "Discard draft", "follow": "Follow macOS", "setting": "Let people choose",
         "rule": "Rule", "removeRule": "Remove rule", "unfollow": "Stop following macOS", "variant": "Variant", "change": "Ask for looks"][action] ?? action
    }
}
