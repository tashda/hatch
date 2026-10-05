import Foundation

/// Where one item of a Sweep stands (decision SW5).
public enum SweepItemState: String, CaseIterable, Codable, Sendable {
    case todo, building, built, verified, dropped

    public var displayName: String {
        switch self {
        case .todo: "To do"
        case .building: "Building"
        case .built: "Built"
        case .verified: "Verified"
        case .dropped: "Dropped"
        }
    }

    /// Finished as far as the agent is concerned: nothing left to build on it.
    public var isSettled: Bool { self == .built || self == .verified || self == .dropped }
}

/// One of the several similar things a Sweep changes: a card, a sheet, a row. `name` is the type or view as the code spells it
/// and `file` is where it is; both are checked against the code when the survey is handed in, so an item cannot be invented.
public struct SweepItem: Identifiable, Equatable, Sendable {
    public let id: Int
    public let ticketId: Int
    /// Stable within the Sweep; the agent and the owner refer to the item by it.
    public let key: String
    public var title: String
    public var name: String
    public var file: String
    /// The group of look-alikes this item belongs to ("with actions", "read only"), so the design can say how each kind looks.
    public var kind: String?
    public var note: String?
    public var state: SweepItemState
    public var commit: String?
    public var position: Int
}

/// What the survey hands in for one item.
public struct SweepItemInput: Equatable, Sendable {
    public var key: String
    public var title: String
    public var name: String
    public var file: String
    public var kind: String?
    public var note: String?
    public init(key: String, title: String, name: String, file: String, kind: String? = nil, note: String? = nil) {
        self.key = key; self.title = title; self.name = name; self.file = file; self.kind = kind; self.note = note
    }
}

public extension HatchStore {
    private static func sweepItem(_ r: Row) -> SweepItem {
        SweepItem(id: r.int("id")!, ticketId: r.int("ticket_id")!, key: r.string("key")!, title: r.string("title")!, name: r.string("name")!,
                  file: r.string("file")!, kind: r.string("kind"), note: r.string("note"),
                  state: r.string("state").flatMap(SweepItemState.init(rawValue:)) ?? .todo, commit: r.string("commit_sha"), position: r.int("position") ?? 0)
    }

    func sweepItems(ticketId: Int) throws -> [SweepItem] {
        try db.query("SELECT * FROM sweep_item WHERE ticket_id = ? ORDER BY position, id", [.int(ticketId)], map: Self.sweepItem)
    }

    /// Saves what a survey found. An item already there keeps its state (the owner's drops and the agent's progress survive a
    /// revised survey); a new one starts as To do. An earlier item left out of the new list stays: the owner decides what goes.
    @discardableResult
    func saveSweepItems(ticketId: Int, items: [SweepItemInput]) throws -> [SweepItem] {
        try db.transaction {
            let existing = Dictionary(try sweepItems(ticketId: ticketId).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            var next = (try sweepItems(ticketId: ticketId).map(\.position).max() ?? -1) + 1
            for item in items {
                if existing[item.key] != nil {
                    try db.execute("UPDATE sweep_item SET title = ?, name = ?, file = ?, kind = ?, note = ? WHERE ticket_id = ? AND key = ?",
                                   [.text(item.title), .text(item.name), .text(item.file), .opt(item.kind), .opt(item.note), .int(ticketId), .text(item.key)])
                } else {
                    try db.execute("INSERT INTO sweep_item(ticket_id, key, title, name, file, kind, note, state, position, at) VALUES(?,?,?,?,?,?,?,?,?,?)",
                                   [.int(ticketId), .text(item.key), .text(item.title), .text(item.name), .text(item.file), .opt(item.kind), .opt(item.note),
                                    .text(SweepItemState.todo.rawValue), .int(next), .date(now())])
                    next += 1
                }
            }
            return try sweepItems(ticketId: ticketId)
        }
    }

    /// Moves one item. `commit` is recorded when it is built (one commit per item, decision SW7).
    @discardableResult
    func setSweepItem(ticketId: Int, key: String, to state: SweepItemState, commit: String? = nil, by: String) throws -> SweepItem {
        try db.transaction {
            guard let item = try sweepItems(ticketId: ticketId).first(where: { $0.key == key }) else {
                throw StoreError.invalid("There is no item '\(key)' on this ticket. The items are: " + (try sweepItems(ticketId: ticketId).map(\.key).joined(separator: ", ")))
            }
            try db.execute("UPDATE sweep_item SET state = ?, commit_sha = COALESCE(?, commit_sha) WHERE id = ?", [.text(state.rawValue), .opt(commit), .int(item.id)])
            try db.execute("UPDATE ticket SET updated_at = ? WHERE id = ?", [.date(now()), .int(ticketId)])
            try record(ticketId, actor: by, kind: "item", payload: ["key": .string(key), "from": .string(item.state.rawValue), "to": .string(state.rawValue)])
            return try sweepItems(ticketId: ticketId).first { $0.key == key }!
        }
    }

    /// Items settled out of all that count (dropped ones do not count), for "7 of 12".
    func sweepProgress(ticketId: Int) throws -> (settled: Int, total: Int) {
        let items = try sweepItems(ticketId: ticketId).filter { $0.state != .dropped }
        return (items.filter(\.state.isSettled).count, items.count)
    }
}

/// A first list of the things a Sweep may change, from a free name scan (decision SW5): the app's views whose names share a word
/// with the owner's text ("cards" finds DecideCard and AgentCard). The preparing agent confirms, removes and adds; the list only
/// saves it from starting from nothing.
public enum SweepCandidates {
    static let ignored: Set<String> = ["view", "views", "this", "that", "with", "from", "have", "into", "should", "there", "their", "them", "what", "which",
                                       "would", "could", "about", "look", "looks", "make", "want", "like", "same", "some", "every", "each", "other",
                                       "change", "please", "show", "shows", "today", "currently", "current", "types", "type", "option", "options"]

    static func stem(_ w: String) -> String { w.hasSuffix("ies") && w.count > 5 ? String(w.dropLast(3)) + "y" : (w.hasSuffix("s") && w.count > 4 ? String(w.dropLast()) : w) }

    /// `DecideSessionView` to ["decide", "session", "view"].
    static func tokens(_ name: String) -> [String] {
        var out: [String] = [], current = ""
        for ch in name {
            if ch.isUppercase, !current.isEmpty, !(current.last?.isUppercase ?? false) { out.append(current.lowercased()); current = "" }
            if ch.isLetter || ch.isNumber { current.append(ch) } else if !current.isEmpty { out.append(current.lowercased()); current = "" }
        }
        if !current.isEmpty { out.append(current.lowercased()) }
        return out
    }

    /// Views most like the text first; `pathPrefix` turns a path in the scanned folder into one relative to the app.
    public static func scan(text: String, views: [ViewEntry], pathPrefix: String = "", limit: Int = 40) -> [(name: String, file: String)] {
        let words = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map { stem(String($0)) }.filter { $0.count >= 4 && !ignored.contains($0) })
        guard !words.isEmpty else { return [] }
        var scored: [(name: String, file: String, score: Int)] = []
        for v in views where v.kind == .view {
            let leaf = String(v.name.split(separator: ".").last ?? Substring(v.name))
            let hit = Set(tokens(leaf).map { stem($0) }.filter { words.contains($0) })
            if !hit.isEmpty { scored.append((leaf, pathPrefix + v.file, hit.count)) }
        }
        var seen = Set<String>()
        return scored.sorted { ($1.score, $0.name) < ($0.score, $1.name) }.filter { seen.insert($0.name).inserted }.prefix(limit).map { ($0.name, $0.file) }
    }
}
