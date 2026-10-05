import SwiftUI
import Combine
import HatchCore
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
        case "answer": try system.answer(body["question"]?.stringValue ?? "", option: body["option"]?.intValue ?? -1)
        case "agree": try system.agree(role)
        case "look": try system.setLook(role ?? "", recipe: recipe())
        case "apply": try system.applyDrafts(role)
        case "discard": try system.discardDraft(role ?? "")
        case "variant": try system.addVariant(to: role ?? "", id: body["id"]?.stringValue ?? "variant", use: body["use"]?.stringValue ?? "", recipe: recipe())
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

/// What the main area shows for the selected element.
enum DesignerMode: String, CaseIterable, Identifiable {
    case inPlace, matrix, today
    var id: String { rawValue }
    var title: String {
        switch self { case .inPlace: "In Place"; case .matrix: "Matrix"; case .today: "Today vs Draft" }
    }
}

/// What the sidebar selects.
enum DesignerSelection: Hashable {
    case foundations(ComponentFoundation.Kind)
    case element(String)
}

@MainActor
final class DesignerModel: ObservableObject {
    @Published private(set) var system: ComponentSystem
    @Published private(set) var inventory: ComponentInventory?
    @Published var selection: DesignerSelection?
    @Published var selectedRole: String?
    @Published var mode: DesignerMode = .inPlace
    @Published var sample = SampleContent()
    @Published var dark = false
    @Published var largeText = false
    /// A problem worth showing: Hatch is away, or a change was refused.
    @Published private(set) var notice: String?
    @Published private(set) var busy = false

    let source: ComponentsSource
    let appName: String

    init(source: ComponentsSource, inventory: ComponentInventory? = nil) throws {
        self.source = source
        let s = try source.load()
        system = s
        appName = s.name
        self.inventory = inventory
        selection = s.elementsUsed.first.map { .element($0) }
        selectedRole = s.elementsUsed.first.flatMap { s.roles(of: $0).first?.id }
    }

    // MARK: Reading

    var selectedElement: String? { if case .element(let e) = selection { return e }; return nil }
    var role: ComponentRole? { selectedRole.flatMap { system.role($0) } }

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

    func answer(_ q: ComponentQuestion, option: Int) { run("answer", ["question": .string(q.id), "option": .int(option)]) }
    func agree(_ role: ComponentRole) { run("agree", ["role": .string(role.id)]) }
    func agreeAll() { run("agree", [:]) }
    func discard(_ role: ComponentRole) { run("discard", ["role": .string(role.id)]) }
    func apply(_ role: ComponentRole?) { run("apply", role.map { ["role": .string($0.id)] } ?? [:]) }

    /// Steps one setting of the selected role (‹ ›). A provisional role changes at once; an agreed one gets a draft.
    func step(_ parameter: ComponentParameter, by delta: Int) {
        guard let role else { return }
        var recipe = role.draft ?? role.recipe
        let values = parameter.values + (system.foundations.filter { parameter.foundation == $0.kind }.map(\.id))
        let current = recipe[parameter.id].flatMap { values.firstIndex(of: $0) } ?? 0
        let next = (current + delta + values.count) % values.count
        recipe[parameter.id] = values[next]
        run("look", ["role": .string(role.id), "recipe": .object(recipe.mapValues { .string($0) })])
    }

    private func run(_ action: String, _ body: JSONValue) {
        busy = true
        defer { busy = false }
        do {
            system = try source.change(action, body)
            notice = nil
            if let id = selectedRole, system.role(id) == nil { selectedRole = nil }
        } catch {
            notice = "\(error)"
        }
    }
}
