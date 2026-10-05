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
    /// The owner's templates and the one marked for new projects (CD46, CD47).
    func templates() throws -> (defaultId: String?, saved: [SavedTemplate])
    /// save, default, remove: through Hatch only.
    func changeTemplates(_ action: String, _ body: JSONValue) throws -> (defaultId: String?, saved: [SavedTemplate])
}

/// Changes kept in memory: the demo, tests, and a notebook opened read-only.
final class LocalComponentsSource: ComponentsSource {
    private var system: ComponentSystem

    init(system: ComponentSystem) { self.system = system }
    var isLocal: Bool { true }
    func load() throws -> ComponentSystem { system }

    /// Read from Hatch's library; saving needs Hatch (rule 2: Hatch is the only writer).
    func templates() throws -> (defaultId: String?, saved: [SavedTemplate]) {
        let lib = ComponentTemplateLibrary(folder: HatchPaths.current().templatesFolder)
        return (lib.defaultId, lib.saved())
    }
    func changeTemplates(_ action: String, _ body: JSONValue) throws -> (defaultId: String?, saved: [SavedTemplate]) {
        throw StoreError.invalid("Templates are saved through Hatch: open the Designer from Hatch's Components page.")
    }

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
        case "answerLook": try system.answer(body["question"]?.stringValue ?? "", look: recipe())
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
        case "fallback": try system.setFallback(role ?? "", parameter: body["parameter"]?.stringValue ?? "", value: body["value"]?.stringValue)
        case "restore", "replace":
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
    func templates() throws -> (defaultId: String?, saved: [SavedTemplate]) { try client.componentTemplates() }
    func changeTemplates(_ action: String, _ body: JSONValue) throws -> (defaultId: String?, saved: [SavedTemplate]) {
        try client.changeTemplates(action, body: body)
    }
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

/// A change to many roles at once (CD24): an element, a place, or an element in a place. Each role can change
/// everywhere it sits or only in the place (a variant with a reason, CD26). Previewed, then kept as one change.
struct DesignerBatch: Equatable {
    struct Item: Equatable, Identifiable {
        var role: String
        var recipe: [String: String]
        var follow: Bool
        /// Where else the role sits, so the sheet can say what "everywhere" reaches.
        var otherPlaces: [String]
        var onlyHere: Bool
        var id: String { role }
    }
    var title: String
    /// The place the change is about, when it is one.
    var place: String?
    var items: [Item]
    /// Why the place is different, for its variants.
    var reason = ""
}

/// What the sidebar selects.
enum DesignerSelection: Hashable {
    /// Every element in every place, as one drawn matrix (CD33).
    case all
    /// Templates compared with each other and with this app (CD47).
    case templates
    /// Every open question, grouped by control (the owner: a view of what needs deciding, not only "next").
    case decide
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
    /// Draws every look as the app's oldest supported macOS will: newer values replaced by their fallbacks.
    @Published var oldestMacOS = false
    /// The role is open on its own level (CD8): "‹ Buttons · Main action", drawn in every place it sits.
    @Published var focused = false
    /// The looks being tried, by role (CD13): one role, or every role of a batch change (CD24).
    @Published private(set) var previews: [String: DesignerPreview] = [:]
    /// The batch change being previewed, if the previews come from one.
    @Published private(set) var batch: DesignerBatch?
    /// The selected role's preview, or the only one.
    var preview: DesignerPreview? { selectedRole.flatMap { previews[$0] } ?? (previews.count == 1 ? previews.values.first : nil) }
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
    /// The window's scheme: Light or Dark; Both keeps the Mac's and draws each place in both.
    var liveScheme: ColorScheme { appearance == .dark ? .dark : appearance == .light ? .light : systemScheme }
    /// A problem worth showing: Hatch is away, or a change was refused.
    @Published private(set) var notice: String?
    @Published private(set) var busy = false

    let source: ComponentsSource
    let appName: String
    /// The owner's saved templates and the one marked for new projects (CD46, CD47).
    @Published private(set) var savedTemplates: [SavedTemplate] = []
    @Published private(set) var defaultTemplateId: String?
    /// The live window's state, and how to open it (the app delegate sets it).
    let live = LiveState()
    var openLiveWindow: (() -> Void)?

    /// The app's folder, so a use can be opened in Xcode at its line (CD49).
    let appRoot: String?

    init(source: ComponentsSource, inventory: ComponentInventory? = nil, appRoot: String? = nil) throws {
        self.source = source
        self.appRoot = appRoot
        let s = try source.load()
        system = s
        appName = s.name
        self.inventory = inventory
        let scheme: ColorScheme = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        systemScheme = scheme
        appearance = scheme == .dark ? .dark : .light
        if let lib = try? source.templates() { savedTemplates = lib.saved; defaultTemplateId = lib.defaultId }
        selection = s.elementsUsed.first.map { .element($0) }
        selectedRole = s.elementsUsed.first.flatMap { s.roles(of: $0).first?.id }
    }

    // MARK: Reading

    var selectedElement: String? { if case .element(let e) = selection { return e }; return nil }
    var selectedPlace: String? { if case .place(let p) = selection { return p }; return nil }
    /// The selection draws looks on the canvas (an element, a place or all), so hard cases and roles apply.
    var showsCanvas: Bool {
        switch selection { case .element?, .place?, .all?, .templates?, .decide?: true; default: false }
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
        if let p = previews[role.id] { return p.recipe }
        return role.draft ?? role.recipe
    }
    func isPreviewing(_ role: ComponentRole) -> Bool { previews[role.id] != nil }

    /// The look as drawn on the canvas: on the oldest macOS when that hard case is on.
    func onCanvas(_ role: ComponentRole, _ recipe: [String: String]) -> [String: String] {
        guard oldestMacOS, let e = ComponentElement.named(role.element) else { return recipe }
        return e.olderLook(recipe, on: system.minimumMacOSNumber, overrides: role.fallbacks)
    }

    /// The app's oldest macOS, as people write it ("14", "15.4").
    var oldestMacOSTitle: String {
        let v = system.minimumMacOS
        return v.hasSuffix(".0") ? String(v.dropLast(2)) : v
    }

    /// A role's own fallback for one setting on older macOS (nil: the nearest look).
    func setFallback(_ role: ComponentRole, parameter: String, value: String?) {
        run("fallback", ["role": .string(role.id), "parameter": .string(parameter), "value": value.map { .string($0) } ?? .null],
            label: "\(role.title) on older macOS")
    }

    /// A look as it is drawn: settings macOS uses anyway left out, and a button's or menu's label as drawn when none is
    /// set (a button shows its title, a menu its title and icon), so two looks that draw the same compare equal.
    func drawn(_ element: String, _ recipe: [String: String]) -> [String: String] {
        guard let e = ComponentElement.named(element) else { return recipe }
        var look = e.withoutDefaults(e.look(recipe))
        if element == "button", look["label"] == "titleOnly" { look["label"] = nil }
        if element == "menu", look["label"] == "titleAndIcon" { look["label"] = nil }
        return look
    }

    /// The role would be drawn differently from today by the look being tried.
    func isChanged(_ role: ComponentRole) -> Bool {
        isPreviewing(role) && drawn(role.element, look(of: role)) != drawn(role.element, role.draft ?? role.recipe)
    }

    /// The open look question about a role, if any.
    func question(for role: ComponentRole) -> ComponentQuestion? { system.questions.first { $0.role == role.id } }

    /// Every open question, element by element in the sidebar's order, for the toolbar's queue (CD27).
    var queue: [ComponentQuestion] {
        system.elementsUsed.flatMap { questions(for: $0) }
    }

    /// Opens a role on its own level, closing any preview of another role. From a place or All it stays there, so
    /// going back returns to where it was opened (CD9).
    func open(_ roleId: String) {
        if batch == nil { previews = previews.filter { $0.key == roleId } }
        selectedRole = roleId
        if let r = system.role(roleId), !showsCanvas || (selectedElement != nil && selectedElement != page(of: r.element)) { selection = .element(page(of: r.element)) }
        focused = true
    }

    /// Back to the element (Esc).
    func back() { if batch == nil { previews = [:] }; focused = false }

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
        for t in templates {
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

    /// Where a role is used in the app (CD49), by screen: the view it sits in (or its file), with each use.
    func screens(of role: ComponentRole, place: String? = nil) -> [(screen: String, uses: [ComponentInventory.Use])] {
        var order: [String] = [], groups: [String: [ComponentInventory.Use]] = [:]
        for u in uses(of: role) where place == nil || u.place == place {
            let screen = u.view ?? ((u.file as NSString).lastPathComponent as NSString).deletingPathExtension
            if groups[screen] == nil { order.append(screen) }
            groups[screen, default: []].append(u)
        }
        return order.map { ($0, groups[$0]!) }.sorted { $0.uses.count > $1.uses.count }
    }

    /// Opens a use in Xcode at its line.
    func reveal(_ use: ComponentInventory.Use) {
        let path = use.file.hasPrefix("/") ? use.file : ((appRoot ?? "") as NSString).appendingPathComponent(use.file)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xed")
        p.arguments = ["--line", String(use.line), path]
        try? p.run()
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
    func openCount(_ element: String) -> Int { members(of: element).reduce(0) { $0 + questions(for: $1).count } }

    /// The elements shown on one page: Pickers include section switchers, which are pickers that switch views.
    func members(of element: String) -> [String] {
        element == "picker" ? ["picker", "switcher"].filter { system.elementsUsed.contains($0) || $0 == "picker" } : [element]
    }
    /// The page an element is shown on (section switchers on Pickers).
    func page(of element: String) -> String { element == "switcher" ? "picker" : element }

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

    /// The values to draw as choices for a setting: macOS's default first (nil), then the others, without the value that
    /// is macOS's default (it is the first).
    func choices(of p: ComponentParameter, for role: ComponentRole? = nil) -> [String?] {
        // Deprecated values are not offered (CD52), unless the role uses one now.
        let current = role.flatMap { look(of: $0)[p.id] }
        // Twins (values macOS 27 draws alike) are offered once, as the first of them (CD21).
        let all: [String?] = [nil] + values(of: p).filter { v in
            v != p.systemDefault && (!p.deprecated.contains(v) || v == current) && (p.offered(v) == v || v == current)
                && !(p.systemDefault.map { p.offered(v) == p.offered($0) } ?? false)
        }.map { Optional($0) }
        guard let role else { return all }
        // Only looks of the role's own kind (CD51): a setting toggle is never offered as a toggle button.
        return all.filter { v in
            var r = role.draft ?? role.recipe
            r[p.id] = v
            return ComponentDraft.kind(role.element, r) == role.kind
        }
    }

    /// The values a setting can take for this system: its own and the system's foundations of its kind.
    func values(of parameter: ComponentParameter) -> [String] {
        parameter.values + system.foundations.filter { parameter.foundation == $0.kind }.map(\.id)
    }

    /// Tries a look on a role everywhere it sits, without saving (CD13).
    func tryLook(_ p: DesignerPreview) {
        if batch != nil { batch = nil; previews = [:] }
        previews = [p.role: p]
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
        if batch != nil { keepBatch(); return }
        guard let p = preview, let role = system.role(p.role) else { return }
        previews = [:]
        if let i = p.option, let q = question(for: role) {
            run("answer", ["question": .string(q.id), "option": .int(i), "setting": .bool(false)], label: "\(role.title): \(p.label)")
        } else if let q = question(for: role), !p.follow {
            // A look of the owner's own (a shape, a style) answers the open question too (CD50).
            let element = ComponentElement.named(role.element)
            run("answerLook", ["question": .string(q.id), "recipe": .object((element.map { $0.withoutDefaults(p.recipe) } ?? p.recipe).mapValues { .string($0) })],
                label: "\(role.title): \(p.label)")
        } else if p.follow, let q = question(for: role), let i = q.options.firstIndex(where: { $0.follow == true }) {
            run("answer", ["question": .string(q.id), "option": .int(i), "setting": .bool(false)], label: "\(role.title) follows macOS")
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
    func discard() { previews = [:]; batch = nil }

    // MARK: Templates (CD4, CD46, CD47)

    /// Hatch's templates, then the owner's.
    var templates: [ComponentTemplate] { ComponentTemplates.all + savedTemplates.map(\.template) }
    func template(_ id: String) -> ComponentTemplate? { templates.first { $0.id == id } }
    /// The one new projects start from: the marked one, else macOS Native.
    var recommendedTemplate: ComponentTemplate { defaultTemplateId.flatMap(template) ?? ComponentTemplates.native }

    func saveTemplate(title: String, summary: String) { changeTemplates("save", ["project": .string(projectKey), "title": .string(title), "summary": .string(summary)]) }
    func setDefaultTemplate(_ id: String?) { changeTemplates("default", ["id": id.map { .string($0) } ?? .null]) }
    func removeTemplate(_ id: String) { changeTemplates("remove", ["id": .string(id)]) }

    private var projectKey: String { (source as? HatchComponentsSource)?.project ?? appName }

    private func changeTemplates(_ action: String, _ body: JSONValue) {
        do {
            let lib = try source.changeTemplates(action, body)
            savedTemplates = lib.saved; defaultTemplateId = lib.defaultId
            notice = nil
        } catch { notice = "\(error)" }
    }

    // MARK: Batch changes (CD24 to CD26)

    /// Previews a batch change everywhere: every role it changes, at once.
    func tryBatch(_ b: DesignerBatch) {
        batch = b
        previews = Dictionary(uniqueKeysWithValues: b.items.map { ($0.role, DesignerPreview(role: $0.role, recipe: $0.recipe, follow: $0.follow, label: b.title)) })
    }

    /// Keeps a batch as one change (one commit, one undo): looks, Follow macOS, and variants for "only here".
    func keepBatch() {
        guard let b = batch else { return }
        var next = system
        do {
            for item in b.items {
                guard let role = next.role(item.role), let element = ComponentElement.named(role.element) else { continue }
                if item.onlyHere, let place = b.place {
                    try next.addVariant(to: role.id, id: place, use: b.reason.isEmpty ? "Set for \(ComponentPlace.title(place)) only." : b.reason,
                                        recipe: element.withoutDefaults(element.look(item.recipe)), places: [place])
                } else if item.follow {
                    try next.followMacOS(role: role.id)
                } else {
                    try next.setLook(role.id, recipe: element.withoutDefaults(item.recipe))
                }
            }
        } catch { notice = "\(error)"; return }
        previews = [:]
        batch = nil
        guard let data = try? next.encoded() else { return }
        run("replace", ["system": .string(String(decoding: data, as: UTF8.self)), "label": .string(b.title)], label: b.title)
    }

    /// The look a template gives a role: its role for the same element and importance, nearest by places (CD4).
    func templateLook(_ template: ComponentTemplate, for role: ComponentRole) -> (recipe: [String: String], follow: Bool)? {
        let ref = template.system(name: "ref").roles(of: role.element).filter { $0.importance == role.importance }
            .max { Set($0.places).intersection(role.places).count < Set($1.places).intersection(role.places).count }
        return ref.map { ($0.recipe, $0.followsMacOS) }
    }

    /// The roles a scope covers: an element, or an element in a place, or every element in a place.
    func roles(element: String?, place: String?) -> [ComponentRole] {
        system.roles.filter { (element == nil || $0.element == element) && (place == nil || $0.places.contains(place!)) }
    }

    /// "Use macOS Native for all buttons", or for buttons in a place (CD4).
    func batchTemplate(_ template: ComponentTemplate, element: String?, place: String?) -> DesignerBatch {
        let items = roles(element: element, place: place).compactMap { r -> DesignerBatch.Item? in
            guard let t = templateLook(template, for: r) else { return nil }
            return item(r, recipe: t.recipe, follow: t.follow, place: place)
        }
        return DesignerBatch(title: "Match \(template.title) for " + scopeTitle(element: element, place: place), place: place, items: items)
    }

    /// Places where Liquid Glass belongs for a screen's own actions (controls floating over content, not content).
    static let glassPlaces: Set<String> = ["bottomBar", "floating", "actionRow"]

    /// "Use glass where it fits" (CD53): only the style, only for buttons and menus that sit where glass belongs; a main
    /// action gets the filled glass. A role that also sits elsewhere is left alone (split it first).
    func batchGlass(element: String) -> DesignerBatch {
        let items = roles(element: element, place: nil).compactMap { r -> DesignerBatch.Item? in
            guard !r.places.isEmpty, Set(r.places).isSubset(of: Self.glassPlaces), ["button", "menu"].contains(r.element) else { return nil }
            var recipe = r.draft ?? r.recipe
            if r.element == "menu" { recipe["style"] = "button"; recipe["look"] = "glass" }
            else { recipe["style"] = r.importance == .main ? "glassProminent" : "glass" }
            if drawn(r.element, recipe) == drawn(r.element, r.draft ?? r.recipe) { return nil }
            return item(r, recipe: recipe, follow: false, place: nil)
        }
        let what = ComponentElement.named(element)?.plural.lowercased() ?? element
        return DesignerBatch(title: "Glass for \(what) where it fits", place: nil, items: items)
    }

    /// "Follow macOS for every button here" as a previewed batch.
    func batchFollow(element: String?, place: String?) -> DesignerBatch {
        let items = roles(element: element, place: place).filter { !$0.followsMacOS }.map { r in
            item(r, recipe: r.recipe.filter { ComponentElement.named(r.element)?.parameter($0.key)?.isLook == false }, follow: true, place: place)
        }
        return DesignerBatch(title: "Follow macOS for " + scopeTitle(element: element, place: place), place: place, items: items)
    }

    /// "One look for every button here": one setting to one value on every role in the scope (CD24).
    func batchSetting(_ parameter: ComponentParameter, _ value: String?, element: String, place: String?) -> DesignerBatch {
        let words = value.map { ComponentWords.value(element: element, parameter: parameter.id, value: $0) } ?? "macOS default"
        let fits = roles(element: element, place: place).filter { r in
            var tried = r.draft ?? r.recipe
            tried[parameter.id] = value
            // Only where it applies, not where macOS draws, and never turning a role into another kind of control.
            return parameter.applies(to: r.draft ?? r.recipe) && !r.places.allSatisfy { ComponentNative.systemPlaces[$0]?.allowed.isEmpty == true }
                && ComponentDraft.kind(r.element, tried) == r.kind
        }
        let items = fits.compactMap { r -> DesignerBatch.Item? in
            var recipe = r.draft ?? r.recipe
            if let value, value != parameter.systemDefault { recipe[parameter.id] = value } else { recipe[parameter.id] = nil }
            // Already like this: nothing to change.
            if recipe == (r.draft ?? r.recipe) { return nil }
            return item(r, recipe: recipe, follow: false, place: place)
        }
        return DesignerBatch(title: "\(parameter.title) \(words) for " + scopeTitle(element: element, place: place), place: place, items: items)
    }

    private func item(_ r: ComponentRole, recipe: [String: String], follow: Bool, place: String?) -> DesignerBatch.Item {
        let others = place.map { p in r.places.filter { $0 != p } } ?? []
        // A role that reaches more than three other places is changed only here unless asked (CD24's sheet suggests it).
        return DesignerBatch.Item(role: r.id, recipe: recipe, follow: follow, otherPlaces: others, onlyHere: others.count > 3)
    }

    private func scopeTitle(element: String?, place: String?) -> String {
        let what = element.flatMap { ComponentElement.named($0)?.plural.lowercased() } ?? "everything"
        return place.map { "\(what) in \(ComponentPlace.title($0))" } ?? "all \(what)"
    }

    /// The batch changes worth offering for an element or a place: only those that would change something, each with
    /// what it changes (the owner: only relevant buttons).
    func actions(element: String?, place: String?) -> [DesignerAction] {
        var out: [DesignerAction] = []
        func count(_ b: DesignerBatch) -> Int { b.items.filter { item in
            guard let r = system.role(item.role) else { return false }
            return item.follow != r.followsMacOS || drawn(r.element, item.recipe) != drawn(r.element, r.draft ?? r.recipe)
        }.count }
        func roles(_ n: Int) -> String { "\(n) role\(n == 1 ? "" : "s") change" }
        if place == nil, let element, ["button", "menu"].contains(element) {
            let n = count(batchGlass(element: element))
            if n > 0 { out.append(DesignerAction(title: "Use glass where it fits", detail: roles(n) + ", only in bottom bars, floating bars and action rows",
                                                 symbol: "drop.halffull", request: .glass(element: element))) }
        }
        for t in templates {
            let n = count(batchTemplate(t, element: element, place: place))
            if n > 0 { out.append(DesignerAction(title: "Match \(t.title)", detail: roles(n), symbol: "square.on.square", request: .template(t.id, element: element, place: place))) }
        }
        let f = count(batchFollow(element: element, place: place))
        if f > 0 { out.append(DesignerAction(title: "Follow macOS", detail: roles(f) + " to macOS's own look", symbol: "apple.logo", request: .follow(element: element, place: place))) }
        return out
    }

    /// Agrees every provisional role of an element as it is, in one change.
    func agreeAll(element: String) {
        var next = system
        for r in next.roles(of: element) where r.status == .provisional { try? next.agree(r.id) }
        guard next != system, let data = try? next.encoded() else { return }
        let title = "Agree to all \((ComponentElement.named(element)?.plural ?? element).lowercased())"
        run("replace", ["system": .string(String(decoding: data, as: UTF8.self)), "label": .string(title)], label: title)
    }

    /// What a batch sheet is asked to set up (CD24, CD26).
    enum BatchRequest: Identifiable {
        case template(String, element: String?, place: String?)
        case follow(element: String?, place: String?)
        case setting(element: String, place: String?)
        case onlyHere(role: String, place: String)
        case glass(element: String)
        var id: String {
            switch self {
            case .template(let t, let e, let p): "t.\(t).\(e ?? "").\(p ?? "")"
            case .follow(let e, let p): "f.\(e ?? "").\(p ?? "")"
            case .setting(let e, let p): "s.\(e).\(p ?? "")"
            case .onlyHere(let r, let p): "o.\(r).\(p)"
            case .glass(let e): "g.\(e)"
            }
        }
    }
    @Published var request: BatchRequest?

    /// The batch a request starts with.
    func batch(for request: BatchRequest) -> DesignerBatch? {
        switch request {
        case .template(let id, let e, let p): return template(id).map { batchTemplate($0, element: e, place: p) }
        case .follow(let e, let p): return batchFollow(element: e, place: p)
        case .setting(let e, let p):
            guard let param = ComponentElement.named(e)?.parameters.first(where: { $0.isLook }) else { return nil }
            return batchSetting(param, param.values.first, element: e, place: p)
        case .glass(let e): return batchGlass(element: e)
        case .onlyHere(let id, let p):
            guard let r = system.role(id) else { return nil }
            var b = DesignerBatch(title: "\(r.title) only in \(ComponentPlace.title(p))", place: p,
                                  items: [item(r, recipe: look(of: r), follow: previews[id]?.follow ?? false, place: p)])
            b.items[0].onlyHere = true
            return b
        }
    }

    /// Changes one item of the batch being set up: everywhere, or only in its place.
    func setOnlyHere(_ roleId: String, _ onlyHere: Bool) {
        guard var b = batch, let i = b.items.firstIndex(where: { $0.role == roleId }) else { return }
        b.items[i].onlyHere = onlyHere
        batch = b
    }
    func setBatchReason(_ reason: String) { batch?.reason = reason }

    /// Undoes the last kept change (⌘Z): Hatch writes the system as it was before it.
    func undo() {
        guard let last = undoStack.popLast(), let data = try? last.system.encoded() else { return }
        previews = [:]; batch = nil
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
