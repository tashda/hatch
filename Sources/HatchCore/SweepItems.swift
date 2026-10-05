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

    /// The owner leaves an item out ("Leave out" on the item list): it is not built and does not count. Only what is not built yet.
    @discardableResult
    func dropSweepItem(ticketId: Int, key: String, by: String = "owner") throws -> SweepItem {
        guard let item = try sweepItems(ticketId: ticketId).first(where: { $0.key == key }) else { throw StoreError.invalid("There is no item '\(key)'.") }
        guard item.state == .todo || item.state == .building else {
            throw StoreError.invalid("\(item.name) is already \(item.state.displayName.lowercased()); send it back instead of leaving it out.")
        }
        return try setSweepItem(ticketId: ticketId, key: key, to: .dropped, by: by)
    }

    /// Puts a left-out item back.
    @discardableResult
    func restoreSweepItem(ticketId: Int, key: String, by: String = "owner") throws -> SweepItem {
        guard let item = try sweepItems(ticketId: ticketId).first(where: { $0.key == key }), item.state == .dropped else { throw StoreError.invalid("That item is not left out.") }
        return try setSweepItem(ticketId: ticketId, key: key, to: .todo, by: by)
    }

    /// The owner has looked at a built item in the Preview and it is right.
    @discardableResult
    func verifySweepItem(ticketId: Int, key: String, by: String = "owner") throws -> SweepItem {
        guard let item = try sweepItems(ticketId: ticketId).first(where: { $0.key == key }), item.state == .built else { throw StoreError.invalid("Only a built item can be verified.") }
        return try setSweepItem(ticketId: ticketId, key: key, to: .verified, by: by)
    }

    /// One item is not right: it goes back to To do with the owner's note, and the ticket goes to Fixing so an agent takes it up.
    /// The other items stay as they are.
    @discardableResult
    func sendBackSweepItem(ticketId: Int, key: String, note: String, by: String = "owner") throws -> Ticket {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw StoreError.invalid("Say what to change in this item.") }
        return try db.transaction {
            guard let item = try sweepItems(ticketId: ticketId).first(where: { $0.key == key }), item.state == .built || item.state == .verified else {
                throw StoreError.invalid("Only a built item can be sent back.")
            }
            try setSweepItem(ticketId: ticketId, key: key, to: .todo, by: by)
            let moved = try move(ticketId, to: .fixing, actor: .owner, reason: "item \(item.name) sent back")
            try addNote(ticketId, kind: .instruction, author: by, body: "Item \(item.name) (\(key)) in \(item.file): \(text)", context: ["reason": .string("fix"), "item": .string(key)])
            return moved
        }
    }

    /// "Do this" on the answer to a broad Question (decision SW9): a Sweep starts from it, with the owner's words, the answer as
    /// its first note and a link back. It goes straight to Ready: the path is decided, so Iris is not asked again.
    @discardableResult
    func promoteToSweep(from id: Int, by: String = "owner") throws -> Ticket {
        try db.transaction {
            guard let t = try ticket(id: id), t.type == .question, t.status == .yourCall || t.status == .done else {
                throw StoreError.invalid("Only an answered Question can become a Sweep.")
            }
            let answer = try notes(ticketId: id).last(where: { $0.kind == .agent })?.body ?? ""
            let words = IrisReading.ownerWords(title: t.originalTitle ?? t.title, body: t.originalBody)
            let sweep = try createTicket(projectId: t.projectId, type: .sweep, title: t.title,
                                         body: words + "\n\nStarted from the answer to \(t.displayNumber).", area: t.area, status: .draft, actor: .owner)
            if !answer.isEmpty { _ = try addNote(sweep.id, kind: .note, author: "hatch", body: "Findings from \(t.displayNumber):\n\n\(answer)") }
            try link(from: sweep.id, to: id, kind: .related, by: by, why: "made from the answer to \(t.displayNumber)")
            try file(sweep.id, Filing(path: .sweep), by: by)
            try move(sweep.id, to: .checking, actor: .owner, reason: "started from \(t.displayNumber)")
            if t.status == .yourCall { try move(id, to: .done, actor: .owner, reason: "turned into a Sweep") }
            return try move(sweep.id, to: .ready, actor: .hatch, reason: "started from \(t.displayNumber); the path is decided")
        }
    }

    /// An item that turns out big gets its own ticket (decision SW5): the Sweep leaves it out and says where it went. Only an item
    /// not built yet; the new ticket is a Small change the owner can re-path.
    @discardableResult
    func splitOffSweepItem(ticketId: Int, key: String, by: String = "owner") throws -> Ticket {
        try db.transaction {
            guard let t = try ticket(id: ticketId), let item = try sweepItems(ticketId: ticketId).first(where: { $0.key == key }) else { throw StoreError.invalid("There is no item '\(key)'.") }
            guard item.state == .todo else { throw StoreError.invalid("\(item.name) is already \(item.state.displayName.lowercased()); only an item not built yet can be split off.") }
            var body = "One item of \(t.displayNumber) (\(t.title)): \(item.name) in \(item.file)."
            if let n = item.note, !n.isEmpty { body += " " + n }
            body += "\n\nThe design accepted on \(t.displayNumber) applies; see it for the choices."
            let own = try createTicket(projectId: t.projectId, type: .tweak, title: "\(item.name): \(t.title)", body: body, area: t.area, status: .draft, actor: .owner)
            try link(from: own.id, to: ticketId, kind: .related, by: by, why: "\(item.name) was split off from this Sweep")
            try file(own.id, Filing(path: .small), by: by)
            try move(own.id, to: .checking, actor: .owner, reason: "split off from \(t.displayNumber)")
            let ready = try move(own.id, to: .ready, actor: .hatch, reason: "split off from \(t.displayNumber)")
            try setSweepItem(ticketId: ticketId, key: key, to: .dropped, by: by)
            _ = try addNote(ticketId, kind: .note, author: by, body: "\(item.name) was split off to \(ready.displayNumber).")
            return ready
        }
    }

    /// The files a ticket's plan claims. A Sweep also claims every item's file that is not left out (decision SW13): the owner accepted
    /// that list, so two tickets cannot edit the same sheet at once, and the list is not a second reason to ask for approval.
    func planClaim(for t: Ticket, declared: [String]) throws -> [String] {
        guard t.type == .sweep else { return declared }
        let itemFiles = try sweepItems(ticketId: t.id).filter { $0.state != .dropped }.map(\.file)
        return Array(Set(declared + itemFiles)).sorted()
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
