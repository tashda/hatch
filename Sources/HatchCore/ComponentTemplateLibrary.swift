import Foundation

// The owner's own templates (CD47): any project's design system saved under a name, in one library for every project,
// so a look made once can start the next app and be compared with the others. Plain JSON files in Hatch's support folder
// (`templates/<id>.json`), written only by Hatch (rule 2). Which template new projects start from is kept beside them
// (CD46: the one marked, else macOS Native).

/// A design system saved as a template.
public struct SavedTemplate: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    /// Saving again under the same name makes the next version; a project that started from it is asked about what
    /// changed (NF3), never changed silently.
    public var version: Int
    public var savedAt: Date
    /// The app it was saved from.
    public var from: String?
    public var system: ComponentSystem

    /// As a template: the saved looks for a new app, every role provisional, no open questions.
    public var template: ComponentTemplate {
        let saved = system, id = id
        return ComponentTemplate(id: id, title: title, summary: summary) { name in
            var s = saved
            s.name = name
            s.version = 1
            s.template = id
            s.questions = []
            for i in s.roles.indices { s.roles[i].status = .provisional; s.roles[i].draft = nil; s.roles[i].decision = nil; s.roles[i].usedOn = [] }
            return s
        }
    }
}

public struct ComponentTemplateLibrary: Sendable {
    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    private struct Index: Codable { var defaultId: String? }
    private var indexURL: URL { folder.appendingPathComponent("index.json") }

    /// The owner's templates, by title.
    public func saved() -> [SavedTemplate] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }
            .compactMap { try? decoder.decode(SavedTemplate.self, from: Data(contentsOf: $0)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Shipped templates first, then the owner's.
    public var all: [ComponentTemplate] { ComponentTemplates.all + saved().map(\.template) }

    public func named(_ id: String) -> ComponentTemplate? { all.first { $0.id == id } }

    /// The template marked for new projects, if any.
    public var defaultId: String? {
        guard let data = try? Data(contentsOf: indexURL), let index = try? JSONDecoder().decode(Index.self, from: data),
              let id = index.defaultId, named(id) != nil else { return nil }
        return id
    }

    /// CD46: the template new projects start from: the one marked, else macOS Native.
    public var recommended: ComponentTemplate { defaultId.flatMap(named) ?? ComponentTemplates.native }

    public func setDefault(_ id: String?) throws {
        if let id, named(id) == nil { throw StoreError.notFound("No template called \(id).") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(Index(defaultId: id)).write(to: indexURL, options: .atomic)
    }

    /// Saves a system as a template. The same title saves the next version of it; a shipped template's name is refused.
    @discardableResult
    public func save(_ system: ComponentSystem, title: String, summary: String, from: String?, now: Date = Date()) throws -> SavedTemplate {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw StoreError.invalid("A template needs a name.") }
        let id = Self.slug(t)
        guard !ComponentTemplates.all.contains(where: { $0.id == id || $0.title.caseInsensitiveCompare(t) == .orderedSame }) else {
            throw StoreError.invalid("\(t) is one of Hatch's own templates; choose another name.")
        }
        let problems = system.problems()
        guard problems.isEmpty else { throw StoreError.invalid(problems[0]) }
        let previous = saved().first { $0.id == id }
        var copy = system
        copy.questions = []
        let saved = SavedTemplate(id: id, title: t, summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                                  version: (previous?.version ?? 0) + 1, savedAt: now, from: from, system: copy)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(saved).write(to: folder.appendingPathComponent("\(id).json"), options: .atomic)
        return saved
    }

    public func remove(_ id: String) throws {
        let url = folder.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw StoreError.notFound("No saved template called \(id).") }
        try FileManager.default.removeItem(at: url)
        if defaultId == nil, (try? Data(contentsOf: indexURL)) != nil { try setDefault(nil) }
    }

    /// "Hatch's look" → "hatchs-look".
    static func slug(_ title: String) -> String {
        let s = title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(s).split(separator: "-").joined(separator: "-")
    }
}

/// Two systems side by side (CD47): a template with a template, an app with a template, or two versions. One row per cell
/// of the role table (place, element, importance) that either has, in the catalog's order.
public struct ComponentComparison: Sendable {
    public struct Row: Sendable, Identifiable {
        public var place: String
        public var element: String
        public var importance: ComponentRole.Importance
        public var left: ComponentRole?
        public var right: ComponentRole?
        public var id: String { "\(place).\(element).\(importance.rawValue)" }

        /// Drawn differently: one side has no role, or the looks differ. Settings macOS uses anyway don't count, and
        /// neither does following macOS when the other side's look is what macOS draws anyway.
        public var differs: Bool {
            guard let l = left, let r = right, let element = ComponentElement.named(self.element) else { return true }
            return element.withoutDefaults(element.look(l.draft ?? l.recipe)) != element.withoutDefaults(element.look(r.draft ?? r.recipe))
        }
    }

    public var rows: [Row]
    public var differences: Int { rows.filter(\.differs).count }

    public init(_ left: ComponentSystem, _ right: ComponentSystem) {
        let placeOrder = (left.allPlaces + right.allPlaces).map(\.id)
        let elementOrder = ComponentElement.catalog.map(\.id)
        var keys: [(String, String, ComponentRole.Importance)] = []
        for s in [left, right] {
            for r in s.roles { for p in r.places where !keys.contains(where: { $0 == (p, r.element, r.importance) }) { keys.append((p, r.element, r.importance)) } }
        }
        keys.sort {
            let a = (placeOrder.firstIndex(of: $0.0) ?? 99, elementOrder.firstIndex(of: $0.1) ?? 99, ComponentRole.Importance.allCases.firstIndex(of: $0.2) ?? 9)
            let b = (placeOrder.firstIndex(of: $1.0) ?? 99, elementOrder.firstIndex(of: $1.1) ?? 99, ComponentRole.Importance.allCases.firstIndex(of: $1.2) ?? 9)
            return a < b
        }
        rows = keys.map { p, e, i in
            Row(place: p, element: e, importance: i, left: left.role(element: e, place: p, importance: i), right: right.role(element: e, place: p, importance: i))
        }
    }
}
