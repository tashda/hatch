import Foundation
import HatchCore

public struct SpecIndexResult: Equatable, Sendable {
    public var files = 0
    public var items = 0
    /// Codes that were in the index but no longer appear in any file.
    public var removed: [String] = []
    public var warnings: [String] = []
}

/// Reads the notebook's `spec/*.md` into the Spec search index (decisions L3 and PS13). Agents and Iris then get only
/// the matching items from a free local search, never the whole Spec.
public enum SpecIndexer {
    /// Spec items from these files are stored with `source` = `spec/<file>`. The same prefix is used to find stale items.
    public static let sourcePrefix = Notebook.specDir + "/"
    /// Where the Spec lived before the notebook, in the app's `.hatch/`; items from there are cleared on the next index.
    static let legacyPrefix = ".hatch/spec/"

    /// Indexes the Spec of a project's notebook clone. Nil when the project has no notebook on this Mac.
    @discardableResult
    public static func indexNotebook(project: Project, store: HatchStore) throws -> SpecIndexResult? {
        guard let dir = try store.repo(projectId: project.id, role: .notebook)?.localPath else { return nil }
        return try index(directory: URL(fileURLWithPath: dir).appendingPathComponent(Notebook.specDir), project: project, store: store)
    }

    /// Upserts every item and removes items of earlier runs whose line has disappeared. Items from other sources
    /// (for example typed in by hand) are left alone. Re-running with unchanged files changes nothing.
    @discardableResult
    public static func index(directory: URL, project: Project, store: HatchStore) throws -> SpecIndexResult {
        var result = SpecIndexResult()
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".md") }.sorted()
        var items: [(code: String, area: String?, text: String, source: String?)] = []
        var owner: [String: String] = [:]
        for name in names {
            guard let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) else {
                result.warnings.append("\(name): cannot be read as UTF-8; skipped"); continue
            }
            result.files += 1
            let doc = SpecMarkdown.parse(text)
            result.warnings += doc.warnings.map { "\(name): \($0)" }
            for e in doc.entries {
                if let other = owner[e.code] {
                    result.warnings.append("\(name): \(e.code) is also in \(other); this file wins")
                    items.removeAll { $0.code == e.code }
                }
                owner[e.code] = name
                items.append((e.code, e.area, e.text, sourcePrefix + name))
            }
        }
        try store.db.transaction {
            try store.upsertSpecItems(projectId: project.id, items: items)
            result.removed = try store.deleteSpecItems(projectId: project.id, sourcePrefix: sourcePrefix, notIn: Set(items.map(\.code)))
                + store.deleteSpecItems(projectId: project.id, sourcePrefix: legacyPrefix, notIn: [])
        }
        result.items = items.count
        return result
    }
}
