import Foundation
import HatchCore

// Iris, the vetting agent (decisions E7 to E9 and V1). The model call is the only non-deterministic part:
// Hatch gathers the candidates for free (full-text search), asks once, and validates what comes back.

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
    public var ticket: TicketInfo
    public var similar: [Candidate]
    public var specHits: [SpecHit]
    /// Earlier decisions that match, so Iris can flag a ticket that would undo one. Optional for older saved requests.
    public var decisions: [DecisionHit]? = nil
    public var areas: [AreaInfo]
    /// The owner's answers to earlier questions on this ticket. Optional for older saved requests.
    public var answered: [Answered]? = nil

    public init(ticket: TicketInfo, similar: [Candidate] = [], specHits: [SpecHit] = [], areas: [AreaInfo] = []) {
        self.ticket = ticket; self.similar = similar; self.specHits = specHits; self.areas = areas
    }

    /// Gathers the candidates from the store: up to 8 similar tickets and 8 Spec items.
    public static func build(store: HatchStore, ticketId: Int) throws -> VettingRequest {
        guard let t = try store.ticket(id: ticketId) else { throw StoreError.notFound("ticket \(ticketId)") }
        let similar = try store.similarTickets(projectId: t.projectId, title: t.title, body: t.body, excluding: t.id, limit: 8)
            .filter { $0.ticket.status != .dropped }
        let hits = try store.searchSpec(projectId: t.projectId, query: t.title + " " + t.body, limit: 8)
        let areas = try store.project(id: t.projectId)?.config?.areas ?? []
        let decided = try store.searchDecisions(projectId: t.projectId, query: t.title + " " + t.body, area: t.area, limit: 3)
        var request = VettingRequest(
            ticket: .init(number: t.displayNumber, type: t.type.rawValue, title: t.title, body: Text.clip(t.body, 2000), area: t.area),
            similar: similar.map { .init(number: $0.ticket.displayNumber, type: $0.ticket.type.rawValue, status: $0.ticket.status.rawValue,
                                         title: $0.ticket.title, snippet: Text.clip($0.ticket.body.replacingOccurrences(of: "\n", with: " "), 160)) },
            specHits: hits.map { .init(code: $0.code, text: Text.clip($0.text, 200)) },
            areas: areas.map { .init(name: $0.name, specPrefix: $0.specPrefix) })
        request.answered = try store.questions(ticketId: ticketId).compactMap { q in
            q.answer.map { Answered(question: Text.clip(q.text, 200), answer: Text.clip($0, 300)) }
        }
        request.decisions = decided.map { .init(number: $0.ticketNumber, kind: $0.kind.rawValue, title: Text.clip($0.title.isEmpty ? $0.summary : $0.title, 120),
                                                why: Text.clip($0.reason ?? $0.summary, 160)) }
        return request
    }
}

/// What Iris returns. Every part is optional; an empty result means the ticket is fine as written.
public struct VettingResult: Codable, Equatable, Sendable {
    public struct Question: Codable, Equatable, Sendable {
        public var text: String
        public var suggestions: [String]
        public init(text: String, suggestions: [String] = []) { self.text = text; self.suggestions = suggestions }
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
    public var rewrite: Rewrite?
    public var typeSuggestion: TypeSuggestion?
    /// Ticket numbers (`#12`) worth linking as Related.
    public var related: [String]
    /// Spec codes this ticket would touch.
    public var specTouches: [String]
    /// Ticket number of the ticket this one probably duplicates.
    public var duplicateOf: String?

    public init(questions: [Question] = [], rewrite: Rewrite? = nil, typeSuggestion: TypeSuggestion? = nil,
                related: [String] = [], specTouches: [String] = [], duplicateOf: String? = nil) {
        self.questions = questions; self.rewrite = rewrite; self.typeSuggestion = typeSuggestion
        self.related = related; self.specTouches = specTouches; self.duplicateOf = duplicateOf
    }

    public static func parse(_ text: String) throws -> VettingResult { try IrisResult.parse(text) }
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
    /// Caps that keep the owner's attention and the token bill small.
    public static let maxQuestions = 3
    public static let maxSuggestions = 4

    /// A compact prompt that demands one JSON object and nothing else.
    public static func make(_ r: VettingRequest) -> String {
        var s = """
        You are Iris, the vetting agent of Hatch. Check one new ticket against the other tickets and the Spec. Reply with ONE JSON object and nothing else (no prose, no code fence).

        Rules:
        - questions: only what blocks the work and cannot be guessed. Maximum \(maxQuestions). Each has "text" and 2 to \(maxSuggestions) "suggestions" (short answers the owner can click). None is fine.
        - rewrite: restructure the owner's text for its type, keeping every fact and inventing nothing. Bug: Steps, Expected, Actual. Tweak: Element, Change. Sketch: Goal, Constraints. Proposal: What, Why, Scope. Question: the question and its context. Give "title", "body" and "changes" (short list of what you changed). Omit rewrite if the text is already good.
        - typeSuggestion: only if the type looks wrong, with "type" (question, sketch, proposal, tweak, bug or theme) and "reason". A Bug without steps or expected result may be a Question. A Tweak with several reasonable fixes is a Proposal. A Question about how something should look may be a Sketch. A ticket spanning several areas may be a Theme.
        - related: numbers of tickets from the list below that are related, like "#12".
        - specTouches: Spec codes from the list below that this ticket would change.
        - duplicateOf: a ticket number only if it is very probably the same request.
        - If the ticket would undo or contradict one of the earlier decisions below, ask about it as one of the questions, naming the decision's ticket, with suggestions to keep that decision or to replace it.

        Shape: {"questions":[{"text":"","suggestions":[""]}],"rewrite":{"title":"","body":"","changes":[""]},"typeSuggestion":{"type":"","reason":""},"related":[""],"specTouches":[""],"duplicateOf":""}

        Ticket \(r.ticket.number) (\(r.ticket.type)\(r.ticket.area.map { ", area \($0)" } ?? "")): \(r.ticket.title)
        \(r.ticket.body.isEmpty ? "(no description)" : r.ticket.body)
        """
        if !r.areas.isEmpty {
            s += "\n\nAreas: " + r.areas.map { $0.name + ($0.specPrefix.map { " (\($0))" } ?? "") }.joined(separator: ", ")
        }
        s += "\n\nOther tickets:"
        s += r.similar.isEmpty ? " none" : "\n" + r.similar.map { "- \($0.number) [\($0.type), \($0.status)] \($0.title): \($0.snippet)" }.joined(separator: "\n")
        s += "\n\nSpec items:"
        s += r.specHits.isEmpty ? " none" : "\n" + r.specHits.map { "- \($0.code): \($0.text)" }.joined(separator: "\n")
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
    static let knownKeys: Set<String> = ["questions", "rewrite", "typeSuggestion", "type_suggestion", "related", "specTouches", "spec_touches", "duplicateOf", "duplicate_of"]

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
                result.questions.append(.init(text: text, suggestions: Array(strings(d["suggestions"]).prefix(IrisPrompt.maxSuggestions))))
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
        result.related = strings(o["related"])
        result.specTouches = strings(o["specTouches"] ?? o["spec_touches"])
        result.duplicateOf = number(o["duplicateOf"] ?? o["duplicate_of"])
        return result
    }
}
