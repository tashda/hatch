import Foundation
import HatchCore

// Iris files new tickets (decisions V1 and section X, WF-C1 to WF-T8). The model call is the only non-deterministic
// part: Hatch gathers the candidates for free (full-text search, the components catalog), asks once, and validates
// what comes back. What she is sure of is applied; what she is not becomes a question with her guess picked.

/// Everything Iris sees about one new ticket. Candidates come from local search, so asking costs few tokens.
public struct VettingRequest: Codable, Equatable, Sendable {
    public struct TicketInfo: Codable, Equatable, Sendable {
        public var number: String
        public var type: String
        public var title: String
        public var body: String
        public var area: String?
    }
    public struct Candidate: Codable, Equatable, Sendable {
        public var number: String
        public var type: String
        public var status: String
        public var title: String
        public var snippet: String
    }
    public struct SpecHit: Codable, Equatable, Sendable {
        public var code: String
        public var text: String
    }
    public struct DecisionHit: Codable, Equatable, Sendable {
        public var number: String
        public var kind: String
        public var title: String
        public var why: String
    }
    /// A question already answered, so a second check uses the answer instead of asking again (decision WF-Q2).
    public struct Answered: Codable, Equatable, Sendable {
        public var question: String
        public var answer: String
    }
    public struct AreaInfo: Codable, Equatable, Sendable {
        public var name: String
        public var specPrefix: String?
    }
    /// Another project the ticket could move to (it shares the tickets repository; decision WF-C4).
    public struct ProjectInfo: Codable, Equatable, Sendable {
        public var key: String
        public var name: String
    }
    public var ticket: TicketInfo
    public var similar: [Candidate]
    public var specHits: [SpecHit]
    /// Earlier decisions that match, so Iris can flag a ticket that would undo one. Optional for older saved requests.
    public var decisions: [DecisionHit]? = nil
    public var areas: [AreaInfo]
    /// The owner's answers to earlier questions on this ticket. Optional for older saved requests.
    public var answered: [Answered]? = nil
    /// The project this ticket is in, and the others it could move to.
    public var project: ProjectInfo? = nil
    public var otherProjects: [ProjectInfo]? = nil
    /// The app's components, by name and value, so a design change can be checked against them (decision WF-T8).
    public var components: [String]? = nil
    /// Screenshots on the ticket as files on this Mac; Iris looks at them where the provider can (decision WF-C5).
    public var screenshots: [String]? = nil

    public init(ticket: TicketInfo, similar: [Candidate] = [], specHits: [SpecHit] = [], areas: [AreaInfo] = []) {
        self.ticket = ticket; self.similar = similar; self.specHits = specHits; self.areas = areas
    }

    /// Gathers the candidates from the store: up to 8 similar tickets, 8 Spec items, 5 decisions and the components.
    public static func build(store: HatchStore, ticketId: Int) throws -> VettingRequest {
        guard let t = try store.ticket(id: ticketId) else { throw StoreError.notFound("ticket \(ticketId)") }
        let text = t.title + " " + t.body
        let similar = try store.similarTickets(projectId: t.projectId, title: t.title, body: t.body, excluding: t.id, limit: 8)
            .filter { $0.ticket.status != .dropped }
        let hits = try store.searchSpec(projectId: t.projectId, query: text, limit: 8)
        let project = try store.project(id: t.projectId)
        let config = project?.config
        let decided = try store.searchDecisions(projectId: t.projectId, query: text, area: t.area, limit: 5)
        var request = VettingRequest(
            ticket: .init(number: t.displayNumber, type: t.type.rawValue, title: t.title, body: Text.clip(t.body, 2000), area: t.area),
            similar: similar.map { .init(number: $0.ticket.displayNumber, type: $0.ticket.type.rawValue, status: $0.ticket.status.rawValue,
                                         title: $0.ticket.title, snippet: Text.clip($0.ticket.body.replacingOccurrences(of: "\n", with: " "), 160)) },
            specHits: hits.map { .init(code: $0.code, text: Text.clip($0.text, 200)) },
            areas: (config?.areas ?? []).map { .init(name: $0.name, specPrefix: $0.specPrefix) })
        request.answered = try store.questions(ticketId: ticketId).compactMap { q in
            q.answer.map { Answered(question: Text.clip(q.text, 200), answer: Text.clip($0, 300)) }
        }
        request.decisions = decided.map { .init(number: $0.ticketNumber, kind: $0.kind.rawValue, title: Text.clip($0.title.isEmpty ? $0.summary : $0.title, 120),
                                                why: Text.clip($0.reason ?? $0.summary, 160)) }
        if let project {
            request.project = .init(key: project.key, name: project.name)
            request.otherProjects = try store.projects().filter { $0.id != project.id && (try? store.canMoveProject(t, to: $0.id)) == true }
                .map { .init(key: $0.key, name: $0.name) }
        }
        if let config, let folder = config.componentsFolder, FileManager.default.fileExists(atPath: folder) {
            let catalog = ComponentsScanner.catalog(at: folder, isPackage: config.components.map { $0.product != nil } ?? true)
            if !catalog.isEmpty { request.components = catalog.briefLines(cap: 24, values: true) }
        }
        let shots = try store.attachments(ticketId: ticketId).filter { $0.kind == "screenshot" }.prefix(3)
        let files = shots.compactMap { store.attachmentFile($0)?.path }.filter { FileManager.default.fileExists(atPath: $0) }
        if !files.isEmpty { request.screenshots = Array(files) }
        return request
    }
}

/// What Iris returns. Every part is optional; an empty result means the ticket is fine as written.
public struct VettingResult: Codable, Equatable, Sendable {
    public struct Question: Codable, Equatable, Sendable {
        public var text: String
        public var suggestions: [String]
        /// What the question is about when it is a clash: "decision #12" or "component PrimaryButton" (WF-T6, WF-T8).
        public var about: String?
        public init(text: String, suggestions: [String] = [], about: String? = nil) { self.text = text; self.suggestions = suggestions; self.about = about }
    }
    public struct Rewrite: Codable, Equatable, Sendable {
        public var title: String
        public var body: String
        public var changes: [String]
        public init(title: String, body: String, changes: [String] = []) { self.title = title; self.body = body; self.changes = changes }
    }
    public struct TypeSuggestion: Codable, Equatable, Sendable {
        public var type: TicketType
        public var reason: String
        public init(type: TicketType, reason: String) { self.type = type; self.reason = reason }
    }
    public var questions: [Question]
    /// The ticket's text in its type's shape. Applied as the ticket text; the owner's words stay as the original.
    public var rewrite: Rewrite?
    /// The older way of saying the type; `path` replaces it and sets the type.
    public var typeSuggestion: TypeSuggestion?
    /// Ticket numbers (`#12`) worth linking as Related.
    public var related: [String]
    /// Spec codes this ticket would touch.
    public var specTouches: [String]
    /// Ticket number of the ticket this one probably duplicates.
    public var duplicateOf: String?

    // Filing (section X)
    public var path: WorkPath?
    public var area: String?
    public var priority: String?
    public var verify: VerifyKind?
    /// The key of the project the ticket belongs in, when it is not the current one.
    public var project: String?
    /// A Theme the ticket belongs under, like "#40".
    public var parent: String?
    /// Tickets this one must finish before.
    public var blocks: [String] = []
    /// True when Iris is sure the duplicate is the same request (WF-T5).
    public var duplicateSure: Bool = false
    /// The parts of a prompt with several things in it (WF-T4).
    public var split: [FilingChild] = []
    /// How sure Iris is about a field, 0 to 1: "path", "area", "project". Missing means sure.
    public var confidence: [String: Double] = [:]

    public init(questions: [Question] = [], rewrite: Rewrite? = nil, typeSuggestion: TypeSuggestion? = nil,
                related: [String] = [], specTouches: [String] = [], duplicateOf: String? = nil) {
        self.questions = questions; self.rewrite = rewrite; self.typeSuggestion = typeSuggestion
        self.related = related; self.specTouches = specTouches; self.duplicateOf = duplicateOf
    }

    public static func parse(_ text: String) throws -> VettingResult { try IrisResult.parse(text) }

    /// The path, from `path` or, for answers in the older shape, from the suggested type.
    public var effectivePath: WorkPath? {
        if let path { return path }
        switch typeSuggestion?.type {
        case .question?: return .question
        case .sketch?, .proposal?: return .visual
        case .tweak?: return .small
        case .bug?: return .bug
        case .theme?: return .split
        case nil: return nil
        }
    }

    public func isSure(_ field: String, threshold: Double = IrisPrompt.sureThreshold) -> Bool { (confidence[field] ?? 1) >= threshold }
}

public enum IrisError: Error, CustomStringConvertible, Equatable {
    case noJSON
    case invalid(String)
    public var description: String {
        switch self {
        case .noJSON: return "Iris did not answer with a JSON object."
        case .invalid(let m): return "Iris answered with JSON Hatch cannot use: \(m)"
        }
    }
}

public enum IrisPrompt {
    /// Caps that keep the owner's attention and the token bill small (decision WF-Q1).
    public static let maxQuestions = 3
    public static let maxSuggestions = 4
    /// Below this confidence a field becomes a question with Iris's guess picked (decision WF-T3).
    public static let sureThreshold = 0.7

    /// A compact prompt that demands one JSON object and nothing else.
    public static func make(_ r: VettingRequest) -> String {
        let paths = WorkPath.allCases.map(\.rawValue).joined(separator: ", ")
        var s = """
        You are Iris, who files new tickets in Hatch. The owner wrote the ticket below as a plain prompt. Work out what it is and file it, so the owner does not have to. Reply with ONE JSON object and nothing else (no prose, no code fence).

        Fields:
        - path: one of \(paths). question: asks, wonders, compares. visual: how something looks, is laid out or feels. approaches: changes behaviour or structure with more than one sensible way. bug: something wrong with a known cause (steps, an error, a crash log). investigate: something wrong whose cause is unclear (slow, sometimes, after a while). small: one obvious change. chore: maintenance (dependency, CI, docs, Spec text). split: several separate things.
        - rewrite: the ticket in its shape, keeping every fact and inventing nothing. Bug and investigate: Steps, Expected, Actual. small and chore: Element, Change. visual and approaches: What, Why, Scope. question: the question and its context. Give "title" (short, plain), "body" and "changes".
        - area: one of the areas below, or "" if none fits. priority: urgent (crash, data loss, security), high, normal or low. verify: preview (it can be seen), numbers (speed), or ci (tests cover it).
        - project: only if the ticket clearly belongs to one of the other projects below: its key.
        - confidence: how sure you are, 0 to 1, of "path", "area" and "project". Be honest; below \(sureThreshold) the owner is asked with your guess picked.
        - questions: only what blocks the work and cannot be guessed. At most \(maxQuestions). Each has "text" and 2 to \(maxSuggestions) short "suggestions", your best guess first. None is fine and usual.
        - If the ticket would undo or contradict an earlier decision below, ask about it, naming the decision ("about": "decision #12"), with suggestions to keep the decision or replace it.
        - For visual work, check it against the components below: if it changes a shared component, or needs a colour, font or size the components do not have or that differs from one, ask about it ("about": "component NAME"), with suggestions such as changing the component everywhere, adding a variant here, or keeping the component.
        - related: numbers of related tickets from the list below. parent: a Theme from the list it belongs under. blocks: tickets it must finish before.
        - duplicateOf: a ticket number only if it is very probably the same request; duplicateSure: true only if it is plainly the same thing said again.
        - split: only for path split, the separate parts as [{"title","body","path"}], 2 to 6 of them.
        - specTouches: Spec codes from the list below that this ticket would change.

        Shape: {"path":"","rewrite":{"title":"","body":"","changes":[""]},"area":"","priority":"normal","verify":"","project":"","confidence":{"path":1,"area":1,"project":1},"questions":[{"text":"","suggestions":[""],"about":""}],"related":[""],"parent":"","blocks":[""],"duplicateOf":"","duplicateSure":false,"split":[],"specTouches":[""]}

        Ticket \(r.ticket.number)\(r.ticket.area.map { " (area \($0))" } ?? ""): \(r.ticket.title)
        \(r.ticket.body.isEmpty ? "(no more text)" : r.ticket.body)
        """
        if let shots = r.screenshots, !shots.isEmpty {
            s += "\n\nScreenshots (red marks point at what matters): " + shots.joined(separator: ", ")
        }
        if !r.areas.isEmpty {
            s += "\n\nAreas: " + r.areas.map { $0.name + ($0.specPrefix.map { " (\($0))" } ?? "") }.joined(separator: ", ")
        }
        if let others = r.otherProjects, !others.isEmpty {
            s += "\n\nThis project: \(r.project?.name ?? "?"). Other projects: " + others.map { "\($0.key) (\($0.name))" }.joined(separator: ", ")
        }
        s += "\n\nOther tickets:"
        s += r.similar.isEmpty ? " none" : "\n" + r.similar.map { "- \($0.number) [\($0.type), \($0.status)] \($0.title): \($0.snippet)" }.joined(separator: "\n")
        s += "\n\nSpec items:"
        s += r.specHits.isEmpty ? " none" : "\n" + r.specHits.map { "- \($0.code): \($0.text)" }.joined(separator: "\n")
        if let components = r.components, !components.isEmpty {
            s += "\n\nComponents:\n" + components.joined(separator: "\n")
        }
        let answered = r.answered ?? []
        if !answered.isEmpty {
            s += "\n\nAlready answered by the owner (use these; never ask them again):\n" + answered.map { "- \($0.question) → \($0.answer)" }.joined(separator: "\n")
        }
        s += "\n\nEarlier decisions:"
        let decided = r.decisions ?? []
        s += decided.isEmpty ? " none" : "\n" + decided.map { "- \($0.number) [\($0.kind)] \($0.title). Why: \($0.why)" }.joined(separator: "\n")
        return s
    }
}

/// Reads Iris's answer. Models wrap JSON in prose and code fences, so this finds the object instead of trusting the text.
public enum IrisResult {
    static let knownKeys: Set<String> = ["questions", "rewrite", "typeSuggestion", "type_suggestion", "related", "specTouches", "spec_touches",
                                         "duplicateOf", "duplicate_of", "path", "area", "priority", "split", "confidence"]

    public static func parse(_ text: String) throws -> VettingResult {
        let objects = jsonObjects(in: text)
        guard !objects.isEmpty else { throw IrisError.noJSON }
        let chosen = objects.first { !Set($0.keys).isDisjoint(with: knownKeys) } ?? objects[0]
        return try build(chosen)
    }

    /// Every top-level `{...}` in the text that parses as a JSON object, in order. String-aware, so braces inside text are fine.
    static func jsonObjects(in text: String) -> [[String: Any]] {
        let chars = Array(text.unicodeScalars)
        var out: [[String: Any]] = []
        var i = 0
        while i < chars.count {
            guard chars[i] == "{", let end = matchingBrace(chars, from: i) else { i += 1; continue }
            var piece = String.UnicodeScalarView()
            piece.append(contentsOf: chars[i...end])
            if let obj = (try? JSONSerialization.jsonObject(with: Data(String(piece).utf8))) as? [String: Any] {
                out.append(obj); i = end + 1
            } else { i += 1 }
        }
        return out
    }

    private static func matchingBrace(_ c: [Unicode.Scalar], from start: Int) -> Int? {
        var depth = 0, inString = false, escaped = false
        for i in start..<c.count {
            let ch = c[i]
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                continue
            }
            if ch == "\"" { inString = true }
            else if ch == "{" { depth += 1 }
            else if ch == "}" { depth -= 1; if depth == 0 { return i } }
        }
        return nil
    }

    private static func strings(_ v: Any?) -> [String] {
        let raw: [Any] = (v as? [Any]) ?? (v.map { [$0] } ?? [])
        return raw.compactMap { item -> String? in
            if let s = item as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let n = item as? NSNumber { return "#\(n.intValue)" }
            return nil
        }.filter { !$0.isEmpty }
    }

    private static func number(_ v: Any?) -> String? {
        if let n = v as? NSNumber, !(v is Bool) { return "#\(n.intValue)" }
        if let s = (v as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty, s.lowercased() != "null", s.lowercased() != "none" { return s }
        return nil
    }

    private static func text(_ v: Any?) -> String? {
        guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s.lowercased() != "null", s.lowercased() != "none" else { return nil }
        return s
    }

    /// An object whose every value is null, empty text or an empty list (the prompt's shape echoed back).
    static func isBlank(_ v: Any) -> Bool {
        guard let d = v as? [String: Any] else { return false }
        return d.values.allSatisfy { value in
            if value is NSNull { return true }
            if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if let a = value as? [Any] { return a.allSatisfy { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? ($0 is NSNull) } }
            return false
        }
    }

    static func build(_ o: [String: Any]) throws -> VettingResult {
        var result = VettingResult()
        if let qs = o["questions"] {
            guard let list = qs as? [Any] else { throw IrisError.invalid("\"questions\" must be a list") }
            for item in list {
                if let s = item as? String { if !s.trimmingCharacters(in: .whitespaces).isEmpty { result.questions.append(.init(text: s)) }; continue }
                guard let d = item as? [String: Any] else { throw IrisError.invalid("each question must be an object with \"text\"") }
                let text = ((d["text"] ?? d["question"]) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }
                result.questions.append(.init(text: text, suggestions: Array(strings(d["suggestions"]).prefix(IrisPrompt.maxSuggestions)),
                                              about: Self.text(d["about"])))
            }
            result.questions = Array(result.questions.prefix(IrisPrompt.maxQuestions))
        }
        // Models often echo the shape with empty fields; a wholly blank object means "none", not a broken answer.
        if let rw = o["rewrite"], !(rw is NSNull), !isBlank(rw) {
            guard let d = rw as? [String: Any] else { throw IrisError.invalid("\"rewrite\" must be an object with \"title\" and \"body\"") }
            let title = (d["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let body = (d["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty && body.isEmpty { throw IrisError.invalid("\"rewrite\" has neither a title nor a body") }
            result.rewrite = .init(title: title, body: body, changes: strings(d["changes"]))
        }
        if let ts = o["typeSuggestion"] ?? o["type_suggestion"], !(ts is NSNull), !isBlank(ts) {
            guard let d = ts as? [String: Any], let raw = d["type"] as? String else { throw IrisError.invalid("\"typeSuggestion\" needs a \"type\"") }
            guard let type = TicketType(rawValue: raw.lowercased().trimmingCharacters(in: .whitespaces)) else {
                throw IrisError.invalid("unknown ticket type '\(raw)' (use one of \(TicketType.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            result.typeSuggestion = .init(type: type, reason: (d["reason"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let raw = text(o["path"]) {
            guard let path = WorkPath.parse(raw) else {
                throw IrisError.invalid("unknown path '\(raw)' (use one of \(WorkPath.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            result.path = path
        }
        result.area = text(o["area"])
        result.priority = text(o["priority"]).flatMap { TicketPriority.value($0) == nil ? nil : $0 }
        result.verify = text(o["verify"]).flatMap { VerifyKind(rawValue: $0.lowercased()) }
        result.project = text(o["project"])
        result.parent = number(o["parent"])
        result.blocks = strings(o["blocks"])
        result.related = strings(o["related"])
        result.specTouches = strings(o["specTouches"] ?? o["spec_touches"])
        result.duplicateOf = number(o["duplicateOf"] ?? o["duplicate_of"])
        result.duplicateSure = (o["duplicateSure"] as? Bool) ?? (o["duplicate_sure"] as? Bool) ?? false
        if let parts = o["split"] as? [Any] {
            result.split = parts.compactMap { item -> FilingChild? in
                guard let d = item as? [String: Any], let title = text(d["title"]) else { return nil }
                return FilingChild(title: title, body: text(d["body"]) ?? "", path: text(d["path"]).flatMap(WorkPath.parse))
            }
            result.split = Array(result.split.prefix(6))
        }
        if let c = o["confidence"] as? [String: Any] {
            for (k, v) in c { if let n = v as? NSNumber, !(v is Bool) { result.confidence[k] = min(max(n.doubleValue, 0), 1) } }
        }
        return result
    }
}
