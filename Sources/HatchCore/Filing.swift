import Foundation

// Filing (section X of DECISIONS.md): the owner writes a prompt, Iris works out what it is, and Hatch applies what she is
// sure of. Everything she sets is recorded with its old value, so the ticket can show it with a way to change it.

/// The way a ticket's work goes (decision WF-R1). Iris picks it when she files the ticket; the type is the label on
/// GitHub and in lists, and follows from the path.
public enum WorkPath: String, CaseIterable, Codable, Sendable {
    /// Asks, wonders or compares: an answer, or options to choose from.
    case question
    /// How something looks, is laid out or feels: a web draft first, a Swift Stage only when needed.
    case visual
    /// Behaviour or structure with more than one sensible way: a written proposal.
    case approaches
    /// Something wrong with a known cause (steps, a crash log): built straight away, a failing test first.
    case bug
    /// Something wrong with an unknown cause (slow, sometimes): investigated first, with numbers.
    case investigate
    /// One obvious change.
    case small
    /// Maintenance: a dependency, CI, docs, Spec text.
    case chore
    /// Several things in one prompt: a Theme with one child per part.
    case split

    public var displayName: String {
        switch self {
        case .question: "Question"
        case .visual: "Visual change"
        case .approaches: "Change with approaches"
        case .bug: "Bug, cause known"
        case .investigate: "Problem, cause unknown"
        case .small: "Small change"
        case .chore: "Chore"
        case .split: "Several things"
        }
    }

    public var type: TicketType {
        switch self {
        case .question: .question
        case .visual, .approaches: .proposal
        case .bug, .investigate: .bug
        case .small, .chore: .tweak
        case .split: .theme
        }
    }

    /// How the finished work is verified unless Iris says otherwise (decision WF-K2): what can be seen goes to a
    /// Preview, speed is checked by numbers, and the rest by its tests and CI.
    public var defaultVerify: VerifyKind {
        switch self {
        case .visual, .small, .bug: .preview
        case .investigate: .numbers
        case .question, .approaches, .chore, .split: .ci
        }
    }

    /// Accepts the raw value, the display name, or the way models tend to write them ("bug-known", "Visual").
    public static func parse(_ text: String) -> WorkPath? {
        let s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = WorkPath(rawValue: s) { return p }
        if let p = allCases.first(where: { $0.displayName.lowercased() == s }) { return p }
        switch s.replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-") {
        case "bug-known", "known-bug", "known": return .bug
        case "unknown", "bug-unknown", "investigation", "performance", "slow": return .investigate
        case "design", "ui", "look": return .visual
        case "architecture", "structure", "proposal", "written": return .approaches
        case "tweak": return .small
        case "theme", "several", "epic": return .split
        default: return nil
        }
    }
}

/// How finished work is verified (decision WF-K2).
public enum VerifyKind: String, CaseIterable, Codable, Sendable {
    case preview, numbers, ci

    public var displayName: String {
        switch self {
        case .preview: "In a Preview"
        case .numbers: "By before and after numbers"
        case .ci: "By tests and CI"
        }
    }

    /// Whether the owner is asked to verify it (decision WF-K2): only what can be seen or measured.
    public var needsOwner: Bool { self != .ci }
}

/// Priority as stored in `ticket.priority`; the agent queue takes the highest first (decision WF-P1).
public enum TicketPriority {
    public static let low = -1, normal = 0, high = 1, urgent = 2

    public static func value(_ name: String) -> Int? {
        switch name.lowercased().trimmingCharacters(in: .whitespaces) {
        case "low": low
        case "normal", "medium", "": normal
        case "high": high
        case "urgent", "critical": urgent
        default: nil
        }
    }

    public static func name(_ value: Int) -> String {
        switch value {
        case ..<0: "Low"
        case 0: "Normal"
        case 1: "High"
        default: "Urgent"
        }
    }
}

/// What Hatch does with the answer to a question (`question.purpose`).
public enum QuestionPurpose {
    /// The answer is the ticket's area.
    public static let area = "field:area"
    /// The answer is the path's display name.
    public static let path = "field:path"
    /// The answer is a project key, or the keep choice.
    public static let project = "field:project"
    /// `payload.of` is the ticket this one probably repeats.
    public static let duplicate = "duplicate"
    /// `payload.children` are the tickets Iris would split this one into.
    public static let split = "split"
    /// A clash with an earlier decision or a component (WF-T6, WF-T8): the answer is context for Iris's next check.
    public static let conflict = "conflict"

    /// Questions Hatch acts on by itself; the others are answered for Iris to read on her next check.
    public static func isActedOn(_ purpose: String?) -> Bool {
        guard let purpose else { return false }
        return purpose.hasPrefix("field:") || purpose == duplicate || purpose == split
    }
}

/// The answers Iris offers on the questions Hatch acts on, so the answer can be matched exactly.
public enum IrisChoices {
    public static let splitYes = "Split it"
    public static let splitNo = "Keep it as one ticket"
    public static let duplicateYes = "Same thing: add it there"
    public static let duplicateNo = "Different: keep both"
    public static let keepProject = "Keep it here"
}

/// One child of a split, as Iris proposes it.
public struct FilingChild: Codable, Equatable, Sendable {
    public var title: String
    public var body: String
    public var path: WorkPath?
    public init(title: String, body: String = "", path: WorkPath? = nil) { self.title = title; self.body = body; self.path = path }
}

/// What Iris files on a ticket. Nil leaves a field as it is.
public struct Filing: Equatable, Sendable {
    public var path: WorkPath?
    public var title: String?
    public var body: String?
    public var area: String?
    public var priority: Int?
    public var verify: VerifyKind?
    public var related: [Int] = []
    public var parentId: Int?
    public var blocks: [Int] = []
    public var specTouches: [String] = []
    public var projectId: Int?
    public init(path: WorkPath? = nil, title: String? = nil, body: String? = nil, area: String? = nil, priority: Int? = nil,
                verify: VerifyKind? = nil, related: [Int] = [], parentId: Int? = nil, blocks: [Int] = [], specTouches: [String] = [],
                projectId: Int? = nil) {
        self.path = path; self.title = title; self.body = body; self.area = area; self.priority = priority; self.verify = verify
        self.related = related; self.parentId = parentId; self.blocks = blocks; self.specTouches = specTouches; self.projectId = projectId
    }
}

public extension HatchStore {
    /// A ticket from a plain prompt (decision WF-C1): the first line becomes a working title, the whole prompt is kept as
    /// the owner's words, and Iris starts at once unless it is saved as a draft (WF-C3). The type is a placeholder until
    /// Iris files it. `from` links a follow-up an agent suggested to the ticket it came from (WF-A2).
    @discardableResult
    func capture(prompt: String, projectId: Int, draft: Bool = false, from: Int? = nil, by: String = "owner") throws -> Ticket {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw StoreError.invalid("Write what you want first.") }
        let (title, body) = Self.workingTitle(text)
        return try db.transaction {
            let t = try createTicket(projectId: projectId, type: .question, title: title, body: body, status: .draft, actor: by == "owner" ? .owner : .hatch)
            if let from {
                try link(from: t.id, to: from, kind: .related)
                try record(t.id, actor: by, kind: "suggested", payload: ["from": .int(from)])
            }
            try record(t.id, actor: by, kind: "captured", payload: ["draft": .bool(draft)])
            if draft { return t }
            return try move(t.id, to: .checking, actor: by == "owner" ? .owner : .hatch, reason: "captured; Iris files it")
        }
    }

    /// Title and body from a prompt: a short first line is the title and the rest the body; a long single line is cut at
    /// a word for the title and kept whole as the body.
    static func workingTitle(_ text: String) -> (title: String, body: String) {
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        let first = lines.first ?? text
        let rest = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if first.count <= 80 { return (first, rest) }
        var cut = String(first.prefix(77))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > 40 { cut = String(cut[..<space]) }
        return (cut + "…", text)
    }

    /// Open questions waiting for the owner across tickets, oldest first, for the menu bar and notifications (WF-Q3).
    func openQuestions(projectId: Int? = nil, limit: Int = 10) throws -> [(question: Question, ticket: Ticket)] {
        var out: [(Question, Ticket)] = []
        for t in try tickets(TicketFilter(projectId: projectId, statuses: [.needsAnswers])) {
            for q in try questions(ticketId: t.id, openOnly: true) { out.append((q, t)) }
        }
        return Array(out.sorted { $0.0.at < $1.0.at }.prefix(limit))
    }

    /// Whether Iris has filed this ticket yet (a ticket captured from a prompt has a placeholder type until then).
    func isFiled(_ t: Ticket) throws -> Bool {
        if t.path != nil { return true }
        let events = try events(ticketId: t.id, kinds: ["captured", "filed"])
        return events.contains { $0.kind == "filed" } || !events.contains { $0.kind == "captured" }
    }

    /// Applies what Iris filed in one step (decision WF-T1): path and type, title and text (the owner's words stay as the
    /// original), area, priority, verification and links. A `filed` event keeps each field's old and new value, for the
    /// ticket's "Filed by Iris" card and the digest.
    @discardableResult
    func file(_ id: Int, _ f: Filing, by: String) throws -> Ticket {
        try db.transaction {
            guard var t = try ticket(id: id) else { throw StoreError.notFound("ticket \(id)") }
            var changed: [String: JSONValue] = [:]
            func note(_ key: String, _ old: String?, _ new: String?) {
                if old != new { changed[key] = ["from": old.map(JSONValue.string) ?? .null, "to": new.map(JSONValue.string) ?? .null] }
            }

            if let projectId = f.projectId, projectId != t.projectId, try canMoveProject(t, to: projectId) {
                note("project", try project(id: t.projectId)?.key, try project(id: projectId)?.key)
                try moveProject(id, to: projectId)
                t = try ticket(id: id)!
            }
            if let path = f.path {
                note("path", t.path?.rawValue, path.rawValue)
                let verify = f.verify ?? path.defaultVerify
                note("verify", t.verify?.rawValue, verify.rawValue)
                try db.execute("UPDATE ticket SET path = ?, verify = ?, updated_at = ? WHERE id = ?",
                               [.text(path.rawValue), .text(verify.rawValue), .date(now()), .int(id)])
                if path.type != t.type {
                    note("type", t.type.rawValue, path.type.rawValue)
                    try changeType(id, to: path.type, actor: .hatch, reason: "filed by \(by) as \(path.displayName)")
                }
            } else if let verify = f.verify {
                note("verify", t.verify?.rawValue, verify.rawValue)
                try db.execute("UPDATE ticket SET verify = ? WHERE id = ?", [.text(verify.rawValue), .int(id)])
            }

            let area = f.area.flatMap { name in
                try? project(id: t.projectId)?.config?.areas.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.name
            }
            let title = f.title?.trimmingCharacters(in: .whitespacesAndNewlines).filingText
            let body = f.body?.trimmingCharacters(in: .whitespacesAndNewlines).filingText
            if title != nil || body != nil || area != nil || f.priority != nil {
                if let title, title != t.title { changed["title"] = ["from": .string(t.title), "to": .string(title)] }
                if body != nil, body != t.body { changed["body"] = ["from": .null, "to": .null] }
                note("area", t.area, area ?? t.area)
                if let p = f.priority, p != t.priority { note("priority", TicketPriority.name(t.priority), TicketPriority.name(p)) }
                _ = try update(id, title: title, body: body, actor: .agent, area: area.map { .some($0) }, priority: f.priority)
            }
            if let parent = f.parentId, parent != id, try ticket(id: parent)?.type == .theme {
                try db.execute("UPDATE ticket SET parent_id = ? WHERE id = ?", [.int(parent), .int(id)])
                changed["parent"] = ["to": .int(parent)]
            }
            for other in Set(f.related) where other != id { try link(from: id, to: other, kind: .related) }
            for other in Set(f.blocks) where other != id { try link(from: id, to: other, kind: .blocks) }
            if !f.related.isEmpty { changed["related"] = .array(f.related.map { .int($0) }) }
            if !f.blocks.isEmpty { changed["blocks"] = .array(f.blocks.map { .int($0) }) }
            if !f.specTouches.isEmpty { changed["specTouches"] = .array(f.specTouches.map { .string($0) }) }
            try record(id, actor: by, kind: "filed", payload: ["fields": .object(changed)])
            return try ticket(id: id)!
        }
    }

    /// The latest filing on a ticket, for the "Filed by Iris" card: field name to its old and new value.
    func lastFiling(ticketId: Int) throws -> (at: Date, by: String, fields: [String: JSONValue])? {
        guard let e = try events(ticketId: ticketId, kinds: ["filed"]).last else { return nil }
        return (e.at, e.actor, e.payload["fields"]?.objectValue ?? [:])
    }

    /// The owner changes the path Iris chose (the ticket's Change menu). The type follows while work has not started.
    @discardableResult
    func setPath(_ id: Int, to path: WorkPath, actor: Actor) throws -> Ticket {
        try db.transaction {
            guard let t = try ticket(id: id) else { throw StoreError.notFound("ticket \(id)") }
            try db.execute("UPDATE ticket SET path = ?, verify = ?, updated_at = ? WHERE id = ?",
                           [.text(path.rawValue), .text(path.defaultVerify.rawValue), .date(now()), .int(id)])
            try record(id, actor: actor.rawValue, kind: "path", payload: ["from": t.path.map { .string($0.rawValue) } ?? .null, "to": .string(path.rawValue)])
            if path.type != t.type { try changeType(id, to: path.type, actor: actor == .agent ? .hatch : actor, reason: "path: \(path.displayName)") }
            return try ticket(id: id)!
        }
    }

    /// The owner changes how the work will be verified (the ticket's Change menu, decision WF-K2).
    @discardableResult
    func setVerify(_ id: Int, to verify: VerifyKind, actor: Actor) throws -> Ticket {
        try db.transaction {
            guard let t = try ticket(id: id) else { throw StoreError.notFound("ticket \(id)") }
            try db.execute("UPDATE ticket SET verify = ?, updated_at = ? WHERE id = ?", [.text(verify.rawValue), .date(now()), .int(id)])
            try record(id, actor: actor.rawValue, kind: "verify", payload: ["from": t.verify.map { .string($0.rawValue) } ?? .null, "to": .string(verify.rawValue)])
            return try ticket(id: id)!
        }
    }

    // MARK: Projects

    /// A ticket can move to another project when both use the same tickets repository: only its labels change.
    func canMoveProject(_ t: Ticket, to projectId: Int) throws -> Bool {
        guard let from = try project(id: t.projectId)?.config?.ticketsRepo, let to = try project(id: projectId)?.config?.ticketsRepo else { return false }
        return from == to
    }

    func moveProject(_ id: Int, to projectId: Int) throws {
        guard let t = try ticket(id: id) else { throw StoreError.notFound("ticket \(id)") }
        guard try canMoveProject(t, to: projectId) else {
            throw StoreError.invalid("\(t.displayNumber) can only move to a project with the same tickets repository.")
        }
        try db.execute("UPDATE ticket SET project_id = ?, updated_at = ? WHERE id = ?", [.int(projectId), .date(now()), .int(id)])
        try record(id, actor: "hatch", kind: "project", payload: ["from": .int(t.projectId), "to": .int(projectId)])
        if t.status != .draft { try enqueueLabels(id) }
    }

    // MARK: Duplicates and splits

    /// The same request said again (decision WF-T5): the new text goes onto the original as a note, the two are linked,
    /// and this ticket closes. Reopen undoes it.
    @discardableResult
    func closeAsDuplicate(_ id: Int, of originalId: Int, by: String) throws -> Ticket {
        try db.transaction {
            guard let t = try ticket(id: id), let original = try ticket(id: originalId), id != originalId else {
                throw StoreError.notFound("ticket \(id) or \(originalId)")
            }
            let words = (t.originalBody ?? t.body).trimmingCharacters(in: .whitespacesAndNewlines)
            let text = "Asked again in \(t.displayNumber): \(t.originalTitle ?? t.title)" + (words.isEmpty ? "" : "\n\n\(words)")
            try addNote(original.id, kind: .note, author: by, body: text)
            try link(from: id, to: original.id, kind: .duplicates)
            try record(id, actor: by, kind: "duplicate", payload: ["of": .int(original.id)])
            return try move(id, to: .dropped, actor: .hatch, reason: "duplicate of \(original.displayNumber)")
        }
    }

    /// One prompt with several things in it becomes a Theme with one child per part (decision WF-T4). Each child goes to
    /// Iris on its own.
    @discardableResult
    func splitIntoTheme(_ id: Int, children: [FilingChild], by: String) throws -> [Ticket] {
        try db.transaction {
            guard let t = try ticket(id: id) else { throw StoreError.notFound("ticket \(id)") }
            guard children.count >= 2 else { throw StoreError.invalid("A split needs at least two parts.") }
            try db.execute("UPDATE ticket SET path = ?, verify = ? WHERE id = ?", [.text(WorkPath.split.rawValue), .text(VerifyKind.ci.rawValue), .int(id)])
            if t.type != .theme { try changeType(id, to: .theme, actor: .hatch, reason: "split by \(by)") }
            if try ticket(id: id)!.status != .draft { try move(id, to: .draft, actor: .hatch, reason: "split into \(children.count) tickets") }
            var made: [Ticket] = []
            for c in children {
                let child = try createTicket(projectId: t.projectId, type: c.path?.type ?? .question, title: c.title, body: c.body,
                                             area: t.area, parentId: id, status: .draft, actor: .hatch)
                made.append(try move(child.id, to: .checking, actor: .hatch, reason: "part of \(t.displayNumber)"))
            }
            try record(id, actor: by, kind: "split", payload: ["children": .array(made.map { .int($0.id) })])
            return made
        }
    }

    /// Acts on the answer to a question Hatch understands (field, duplicate, split). Returns false when the ticket left
    /// Needs answers because of it (closed as a duplicate, or split).
    internal func actOnAnswer(_ q: Question, text: String) throws -> Bool {
        guard let purpose = q.purpose else { return true }
        let t = try ticket(id: q.ticketId)!
        switch purpose {
        case QuestionPurpose.area:
            _ = try file(t.id, Filing(area: text), by: "owner")
        case QuestionPurpose.path:
            if let path = WorkPath.parse(text) { _ = try file(t.id, Filing(path: path), by: "owner") }
        case QuestionPurpose.project:
            if let p = try projects().first(where: { $0.key == text || $0.name == text }), p.id != t.projectId, try canMoveProject(t, to: p.id) {
                try moveProject(t.id, to: p.id)
            }
        case QuestionPurpose.duplicate:
            if text == IrisChoices.duplicateYes, let of = q.payload?["of"]?.intValue {
                try closeAsDuplicate(t.id, of: of, by: "Iris")
                return false
            }
        case QuestionPurpose.split:
            if text == IrisChoices.splitYes, let list = q.payload?["children"]?.arrayValue {
                let children = list.compactMap { c -> FilingChild? in
                    guard let title = c["title"]?.stringValue, !title.isEmpty else { return nil }
                    return FilingChild(title: title, body: c["body"]?.stringValue ?? "", path: c["path"]?.stringValue.flatMap(WorkPath.parse))
                }
                if children.count >= 2 {
                    try splitIntoTheme(t.id, children: children, by: "Iris")
                    return false
                }
            }
        default:
            break
        }
        return true
    }
}

private extension String {
    /// Nil for empty text, so an empty field Iris returns leaves the ticket as it is.
    var filingText: String? { isEmpty ? nil : self }
}
