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
    /// True when the owner undid a split of this ticket: Iris must not split it again (IR5).
    public var noSplit: Bool? = nil

    public init(ticket: TicketInfo, similar: [Candidate] = [], specHits: [SpecHit] = [], areas: [AreaInfo] = []) {
        self.ticket = ticket; self.similar = similar; self.specHits = specHits; self.areas = areas
    }

    /// Gathers the candidates from the store: up to 8 similar tickets, 8 Spec items, 5 decisions and the components.
    public static func build(store: HatchStore, ticketId: Int) throws -> VettingRequest {
        guard let t = try store.ticket(id: ticketId) else { throw StoreError.notFound("ticket \(ticketId)") }
        // Her own earlier reading is not the owner's text: a second check starts from the owner's words.
        let words = IrisReading.split(t.body).words
        let text = t.title + " " + words
        // A ticket is never compared with the Theme it was split from or its sibling parts (decision IR6).
        var family: Set<Int> = Set(t.parentId.map { [$0] } ?? [])
        if let parent = t.parentId { family.formUnion(try store.tickets(TicketFilter(parentId: parent)).map(\.id)) }
        family.formUnion(try store.tickets(TicketFilter(parentId: t.id)).map(\.id))
        family.formUnion(try store.splitFamily(of: t.id))
        let similar = try store.similarTickets(projectId: t.projectId, title: t.title, body: words, excluding: t.id, limit: 8 + family.count)
            .filter { $0.ticket.status != .dropped && !family.contains($0.ticket.id) }.prefix(8)
        let hits = try store.searchSpec(projectId: t.projectId, query: text, limit: 8)
        let project = try store.project(id: t.projectId)
        let config = project?.config
        let decided = try store.searchDecisions(projectId: t.projectId, query: text, area: t.area, limit: 5)
        var request = VettingRequest(
            ticket: .init(number: t.displayNumber, type: t.type.rawValue, title: t.title, body: Text.clipMiddle(words, 2000), area: t.area),
            similar: similar.map { .init(number: $0.ticket.displayNumber, type: $0.ticket.type.rawValue, status: $0.ticket.status.rawValue,
                                         title: $0.ticket.title, snippet: Text.clip($0.ticket.body.replacingOccurrences(of: "\n", with: " "), 160)) },
            specHits: hits.map { .init(code: $0.code, text: Text.clip($0.text, 200)) },
            areas: (config?.areas ?? []).map { .init(name: $0.name, specPrefix: $0.specPrefix) })
        request.answered = try store.questions(ticketId: ticketId).compactMap { q in
            q.answer.map { Answered(question: Text.clip(IrisApplier.plainQuestion(q.text), 200), answer: Text.clip($0, 300)) }
        }
        request.decisions = decided.map { .init(number: $0.ticketNumber, kind: $0.kind.rawValue, title: Text.clip($0.title.isEmpty ? $0.summary : $0.title, 120),
                                                why: Text.clip($0.reason ?? $0.summary, 160)) }
        if let project {
            request.project = .init(key: project.key, name: project.name)
            request.otherProjects = try store.projects().filter { $0.id != project.id && (try? store.canMoveProject(t, to: $0.id)) == true }
                .map { .init(key: $0.key, name: $0.name) }
        }
        if let notebook = config?.repo(.notebook)?.localPath, let system = try? ComponentSystem.load(notebook: notebook) {
            // The role table, with looks, so a visual ticket can be checked against it (WF-T8, DS).
            request.components = ["Roles (element in a place for a purpose):"] + system.briefLines(looks: true)
        } else if let config, let folder = config.componentsFolder, FileManager.default.fileExists(atPath: folder) {
            let catalog = ComponentsScanner.catalog(at: folder, isPackage: config.components.map { $0.product != nil } ?? true)
            if !catalog.isEmpty { request.components = catalog.briefLines(cap: 24, values: true) }
        }
        let shots = try store.attachments(ticketId: ticketId).filter { $0.kind == "screenshot" }.prefix(3)
        let files = shots.compactMap { store.attachmentFile($0)?.path }.filter { FileManager.default.fileExists(atPath: $0) }
        if !files.isEmpty { request.screenshots = Array(files) }
        if try store.splitWasUndone(ticketId) { request.noSplit = true }
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
        /// "low": a wrong guess is cheap, so Iris goes ahead with her first suggestion if the owner does not answer.
        /// "high" (and any clash): the ticket waits (decision IR12).
        public var stakes: String?
        /// True when the answer could change what kind of work the ticket is, so Iris must run again after it (IR13).
        public var rerun: Bool = false
        public init(text: String, suggestions: [String] = [], about: String? = nil, stakes: String? = nil, rerun: Bool = false) {
            self.text = text; self.suggestions = suggestions; self.about = about; self.stakes = stakes; self.rerun = rerun
        }
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
    /// True when the ticket names the same screen and the same problem as the duplicate (WF-T5, IR7).
    public var duplicateSure: Bool = false
    /// Which screen and which problem, in one line. Without it a duplicate is never closed.
    public var duplicateWhy: String?
    /// One line for each related ticket, keyed by the number she gave: the screen or file both name (IR9).
    public var relatedWhy: [String: String] = [:]
    /// What she read into the ticket that the owner did not say (IR2).
    public var assumed: [String] = []
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
        case .sweep?: return .sweep
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
    /// A prompt with more things than this is cut here; below it, every thing the owner wrote becomes a ticket.
    public static let maxSplitParts = 12
    /// Below this confidence a field becomes a question with Iris's guess picked (decision WF-T3).
    public static let sureThreshold = 0.7

    /// A compact prompt that demands one JSON object and nothing else. The rules at the top come from the owner's answers on
    /// the Iris scenarios page (decisions IR1 to IR15).
    public static func make(_ r: VettingRequest) -> String {
        let paths = WorkPath.allCases.map(\.rawValue).joined(separator: ", ")
        var s = """
        You are Iris, who files new tickets in Hatch. The owner wrote the ticket below as a plain prompt. File it so the owner does not have to. Reply with ONE JSON object and nothing else (no prose, no code fence).

        Rules that outrank everything below:
        - Use only what the owner wrote, their answers, the screenshots and the lists below. Never invent a fact, name, step, number or screenshot mark. What you read in that was not said goes in "assumed".
        - Decide; do not ask. The owner can change what you file. Ask only if two readings lead to different work, or it would undo a decision below. At most one question. Never ask how to build something, what kind of ticket it is, what the owner already said, or what a screenshot shows.

        Fields:
        - path: one of \(paths). question: wants an answer or an explanation of how things are or why; asking to see options, or how something should look or work, is not a question but visual or approaches. visual: how something looks, is laid out or feels, when the owner wants to see options or gives no exact change. approaches: changes behaviour or structure with more than one sensible way, or asks how it should work. bug: something wrong with a known cause (steps, an error, a crash log). investigate: something wrong whose cause is unclear (slow, sometimes, after a while). small: one obvious change, including a visual one the owner states exactly (a value, a label, a colour, an icon: "add 4pt", "rename X to Y", "use the accent colour" are small, not visual). chore: maintenance (dependency, CI, docs, Spec text). sweep: one change, template or standard for all of a kind of thing (\"all the cards in the Inspector\", \"a template for our cards\"); not for one thing or unrelated things; do not list them, Hatch finds them. split: several unrelated things, each becoming its own ticket; the same change in several places, or one problem with several facets, is one ticket, not a split.
        - title: short and plain, in the owner's own words where you can.
        - reading: your structured reading, kept apart from the owner's words. Bug and investigate: Steps, Expected, Actual. small and chore: Element, Change. visual and approaches: What, Why, Scope. sweep: What (the one change), Why, Family (the kind of thing, in the owner's words). question: the question and its context. Only facts from the owner, their answers or the screenshots.
        - assumed: a list of what you read into the ticket that was not said. [] if nothing.
        - area: the name of the area below that contains the screen or feature the ticket is about, even when the ticket does not name the area (the invoice table belongs to Billing if Billing is an area); the name, never its code. "" when no listed area plainly contains it: a wrong area is worse than none. priority: low or normal; never high or urgent, the owner sets those. verify: preview (it can be seen), numbers (speed), or ci (tests cover it).
        - confidence: how sure you are, 0 to 1, of "path". It only marks a weak guess for the owner to check.
        - questions: usually none. Each has "text", 2 to \(maxSuggestions) short "suggestions" with your best answer first, "stakes" ("low" if a wrong guess is cheap and your first suggestion is fine to go ahead with, "high" if not), and "rerun": true only if the answer could change what kind of work this is.
        - If the ticket would undo or contradict an earlier decision below, ask about it, naming the decision ("about": "decision #12"), stakes high, with suggestions to keep the decision or replace it.
        - If a visual change would alter a component listed below for everyone who uses it, ask once ("about": "component NAME"), stakes high; never for a sweep. Do not ask about a colour, font or size the list lacks; the builder adds those.
        - When the components are roles: if the ticket asks for a look that contradicts a role in its place (a big blue Save where Save is the main action), needs a role the list lacks, or would put a second main action on a screen, ask once ("about": "component ROLE"), stakes high, with suggestions in this order: use the role as it is, add a variant for this place, change the role everywhere.
        - Do not list related tickets: Hatch links tickets that name the same screen or file by itself.
        - duplicateOf: a ticket number from the list below if it may be the same request. duplicateSure: true only if this ticket names the same screen and the same problem as that ticket; then duplicateWhy says which screen and which problem in one line.
        - split: only for path split, the unrelated parts as [{"title","body","path"}], one for each thing the owner asked for (2 to \(maxSplitParts)); never leave a thing out or merge two unrelated things; each part's path never split.\(r.noSplit == true ? " The owner undid a split of this ticket: do not use path split." : "")
        - specTouches: Spec codes from the list below that this ticket would change.

        Shape: {"path":"","title":"","reading":"","assumed":[""],"area":"","priority":"normal","verify":"","confidence":{"path":1},"questions":[{"text":"","suggestions":[""],"stakes":"low","about":"","rerun":false}],"duplicateOf":"","duplicateSure":false,"duplicateWhy":"","split":[],"specTouches":[""]}

        Ticket \(r.ticket.number)\(r.ticket.area.map { " (area \($0))" } ?? ""): \(r.ticket.title)
        \(r.ticket.body.isEmpty ? "(no more text)" : r.ticket.body)
        """
        if let shots = r.screenshots, !shots.isEmpty {
            s += "\n\nScreenshots (attached to this message; any marks on them point at what matters): " + shots.joined(separator: ", ")
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
                                         "duplicateOf", "duplicate_of", "path", "area", "priority", "split", "confidence", "reading", "assumed", "title",
                                         "duplicateWhy", "duplicate_why"]

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
                let stakes = Self.text(d["stakes"])?.lowercased()
                result.questions.append(.init(text: text, suggestions: Array(strings(d["suggestions"]).prefix(IrisPrompt.maxSuggestions)),
                                              about: Self.text(d["about"]), stakes: stakes == QuestionStakes.low || stakes == QuestionStakes.high ? stakes : nil,
                                              rerun: (d["rerun"] as? Bool) ?? false))
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
        // The newer shape: a title, her reading and what she assumed. It fills `rewrite`, which the applier keeps apart from
        // the owner's words.
        let newTitle = text(o["title"]) ?? "", reading = text(o["reading"]) ?? ""
        if result.rewrite == nil, !newTitle.isEmpty || !reading.isEmpty { result.rewrite = .init(title: newTitle, body: reading) }
        result.assumed = strings(o["assumed"])
        if let ts = o["typeSuggestion"] ?? o["type_suggestion"], !(ts is NSNull), !isBlank(ts) {
            guard let d = ts as? [String: Any], let raw = d["type"] as? String else { throw IrisError.invalid("\"typeSuggestion\" needs a \"type\"") }
            guard let type = TicketType(rawValue: raw.lowercased().trimmingCharacters(in: .whitespaces)) else {
                throw IrisError.invalid("unknown ticket type '\(raw)' (use one of \(TicketType.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            result.typeSuggestion = .init(type: type, reason: (d["reason"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // For a repeat models sometimes answer path "duplicate"; `duplicateOf` already says it, so the path is left for Hatch.
        if let raw = text(o["path"]), !["duplicate", "duplicates", "dup", "repeat"].contains(raw.lowercased()) {
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
        // Related tickets are `[{"ticket","why"}]`; plain numbers are read too, but without a reason they are not linked.
        for item in (o["related"] as? [Any]) ?? [] {
            if let d = item as? [String: Any], let ref = number(d["ticket"] ?? d["number"]) {
                result.related.append(ref)
                if let why = text(d["why"]) { result.relatedWhy[ref] = why }
            } else if let ref = number(item) { result.related.append(ref) }
        }
        if o["related"] is String, let ref = number(o["related"]) { result.related.append(ref) }
        result.specTouches = strings(o["specTouches"] ?? o["spec_touches"])
        result.duplicateOf = number(o["duplicateOf"] ?? o["duplicate_of"])
        result.duplicateSure = (o["duplicateSure"] as? Bool) ?? (o["duplicate_sure"] as? Bool) ?? false
        result.duplicateWhy = text(o["duplicateWhy"] ?? o["duplicate_why"])
        if let parts = o["split"] as? [Any] {
            result.split = parts.compactMap { item -> FilingChild? in
                guard let d = item as? [String: Any], let title = text(d["title"]) else { return nil }
                return FilingChild(title: title, body: text(d["body"]) ?? "", path: text(d["path"]).flatMap(WorkPath.parse))
            }
            result.split = Array(result.split.prefix(IrisPrompt.maxSplitParts))
        }
        if let c = o["confidence"] as? [String: Any] {
            for (k, v) in c { if let n = v as? NSNumber, !(v is Bool) { result.confidence[k] = min(max(n.doubleValue, 0), 1) } }
        }
        return result
    }
}
