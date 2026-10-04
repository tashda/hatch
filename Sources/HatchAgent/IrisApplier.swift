import Foundation
import HatchCore

public struct IrisOutcome: Equatable, Sendable {
    public var questionsAsked: Int
    public var suggestionStored: Bool
    /// The ticket's status after Iris's result was applied.
    public var status: Status
    /// The parts, when she split the ticket.
    public var split: [Int] = []
}

/// Turns Iris's answer into store changes (decision WF-T1): what she is sure of is filed at once and recorded with its old
/// value, so the owner can change it; what she is unsure of, a probable duplicate, a split and a clash with a decision or
/// a component become questions with her guess first. Older suggestions (E8, E9) are still decided with accept, edit or
/// keep mine below.
public enum IrisApplier {
    public static let name = "Iris"
    /// Rounds of questions before Iris must file with what she has (decision WF-Q1).
    public static let maxRounds = 2

    /// A question Hatch will ask, with what it does with the answer.
    struct Ask {
        var text: String
        var suggestions: [String]
        var purpose: String?
        var payload: JSONValue?
    }

    /// The question as she asked it, without the sentence Hatch adds about what happens if the owner does not answer.
    static func plainQuestion(_ text: String) -> String {
        for marker in [" I will wait for your answer.", " If you do not answer in "] {
            if let r = text.range(of: marker) { return String(text[..<r.lowerBound]) }
        }
        return text
    }

    /// How many related links Iris may make on one ticket (decision IR9).
    public static let maxRelated = 2
    /// Questions on one ticket (decision IR10).
    public static let maxQuestions = 1

    /// `candidates` are the tickets she was shown, most alike first. A number outside them is dropped, so she cannot close
    /// onto a ticket she never saw (decision IR8); nil allows any, for callers with no request. `anchors` lets Hatch find
    /// related tickets itself from the screens and files they name (IR9). `reply` is where her raw answer was kept.
    @discardableResult
    public static func apply(_ result: VettingResult, to ticketId: Int, store: HatchStore, candidates: [Int]? = nil, anchors: SourceAnchors? = nil,
                             reply: String? = nil) throws -> IrisOutcome {
        try store.db.transaction {
            guard let t = try store.ticket(id: ticketId) else { throw StoreError.notFound("ticket \(ticketId)") }
            guard t.status == .checking else {
                throw StoreError.invalid("\(t.displayNumber) is \(t.status.displayName), not Checking, so Iris's answer was not applied.")
            }
            let config = try store.project(id: t.projectId)?.config
            func shown(_ ref: String?) -> Ticket? {
                guard let ref, let found = try? store.resolve(ref), found.id != t.id else { return nil }
                return candidates == nil || candidates!.contains(found.id) ? found : nil
            }

            // She decides the kind of work, area and priority; the owner changes them in the Filed by Iris box (IR3, IR4).
            // She never moves a ticket to another project, and never sets High or Urgent.
            var filing = Filing()
            let path = result.effectivePath
            if let path, path != .split || result.split.count >= 2 { filing.path = path }
            if let area = result.area, let known = config?.areas.first(where: { $0.name.caseInsensitiveCompare(area) == .orderedSame }) { filing.area = known.name }
            filing.priority = result.priority.flatMap(TicketPriority.value).map { min($0, TicketPriority.normal) }
            filing.verify = result.verify

            // The owner's words stay the ticket; her reading is a labelled section after them (IR2).
            if let r = result.rewrite {
                filing.title = r.title.isEmpty ? nil : r.title
                let words = IrisReading.ownerWords(title: t.originalTitle ?? t.title, body: t.originalBody ?? IrisReading.split(t.body).words)
                let composed = IrisReading.compose(words: words, reading: r.body, assumed: result.assumed)
                filing.body = r.body.isEmpty && result.assumed.isEmpty ? nil : composed
            }

            // Related tickets are found by Hatch, not by her (IR9): two tickets are related when the owner's own words point at
            // the same file or name the same screen. The link says which. At most two, the strongest first.
            let thisText = IrisReading.ownerWords(title: t.originalTitle ?? t.title, body: t.originalBody ?? IrisReading.split(t.body).words)
            var evidence: [(ticket: Ticket, weight: Int, why: String)] = []
            if let anchors, !anchors.isEmpty {
                for id in candidates ?? [] {
                    guard let other = try store.ticket(id: id), other.id != t.id, other.status != .dropped,
                          let found = anchors.shared(thisText, IrisReading.ownerWords(title: other.originalTitle ?? other.title, body: other.originalBody ?? IrisReading.split(other.body).words))
                    else { continue }
                    evidence.append((other, found.weight, found.why))
                }
            }
            // A ticket about to be closed as a repeat gets the duplicate link only, not a related one as well.
            let dupe = shown(result.duplicateOf).flatMap { $0.status.isTerminal && $0.status != .done ? nil : $0 }
            let dupText = dupe.map { IrisReading.ownerWords(title: $0.originalTitle ?? $0.title, body: $0.originalBody ?? IrisReading.split($0.body).words) } ?? ""
            let corroborated = dupe != nil && (anchors?.shared(thisText, dupText) != nil || TextLikeness.overlap(thisText, dupText) >= TextLikeness.repeatThreshold)
            let closing = corroborated && result.duplicateSure && !(result.duplicateWhy ?? "").isEmpty
            if closing { evidence.removeAll { $0.ticket.id == dupe!.id } }
            for e in evidence.enumerated().sorted(by: { ($1.element.weight, $0.offset) < ($0.element.weight, $1.offset) }).prefix(maxRelated).map(\.element) {
                filing.related.append(e.ticket.id); filing.relatedWhy[e.ticket.id] = e.why
            }
            let linked = filing.related.count
            filing.blocks = result.blocks.compactMap { shown($0)?.id }
            if let parent = shown(result.parent), parent.type == .theme { filing.parentId = parent.id }
            filing.specTouches = result.specTouches
            let weak = result.confidence["path"].map { $0 < IrisPrompt.sureThreshold } ?? false
            try store.file(ticketId, filing, by: name, guessed: weak && filing.path != nil ? ["path"] : [], reply: reply)

            // A repeat is closed only when it names the same screen and the same problem, and says which (IR7). Anything less
            // certain is filed as it is with a link to the other ticket, and no question.
            if let dup = dupe {
                // Her word is not enough to close a ticket: Hatch must see the same screen or file named, or nearly the same words.
                if closing, let why = result.duplicateWhy {
                    let closed = try store.closeAsDuplicate(ticketId, of: dup.id, by: name, why: why)
                    return IrisOutcome(questionsAsked: 0, suggestionStored: false, status: closed.status)
                }
                // Not closed: filed as it is, with a link that says only what Hatch could check.
                if linked < maxRelated, !filing.related.contains(dup.id), corroborated {
                    try store.link(from: ticketId, to: dup.id, kind: .related, by: name,
                                   why: anchors?.shared(thisText, dupText)?.why ?? "nearly the same words")
                }
            }

            // Several things in one prompt: split at once, say so in one line, and Undo split puts it back (IR5).
            if path == .split, result.split.count >= 2, result.split.allSatisfy({ $0.path != .split }) {
                let parts = try store.splitIntoTheme(ticketId, children: result.split, by: name)
                return IrisOutcome(questionsAsked: 0, suggestionStored: false, status: try store.ticket(id: ticketId)?.status ?? .draft,
                                   split: parts.map(\.id))
            }

            // At most one question, and the rounds are capped (IR10). A low-stakes one carries her default and a deadline.
            var asks: [Ask] = []
            let rounds = try store.events(ticketId: ticketId, kinds: ["status"]).filter {
                $0.payload["from"]?.stringValue == Status.checking.rawValue && $0.payload["to"]?.stringValue == Status.needsAnswers.rawValue
            }.count
            if rounds < maxRounds, let q = result.questions.first {
                let low = q.about == nil && q.stakes == QuestionStakes.low && !q.suggestions.isEmpty
                var payload: [String: JSONValue] = [:]
                if let about = q.about { payload["about"] = .string(about) }
                if q.rerun { payload["rerun"] = .bool(true) }
                var text = q.text
                if low, let fallback = q.suggestions.first {
                    let deadline = Int(Date().timeIntervalSince1970) + QuestionStakes.waitSeconds
                    payload["stakes"] = .string(QuestionStakes.low); payload["default"] = .string(fallback); payload["by"] = .int(deadline)
                    text += " If you do not answer in \(QuestionStakes.waitSeconds / 60) minutes I will go ahead with \u{201C}\(fallback)\u{201D}."
                } else {
                    payload["stakes"] = .string(QuestionStakes.high)
                    text += " I will wait for your answer."
                }
                asks.append(Ask(text: text, suggestions: q.suggestions, purpose: q.about == nil ? nil : QuestionPurpose.conflict, payload: .object(payload)))
            }
            // The first question moves the ticket to Needs answers, by the agent.
            for a in asks { try store.ask(ticketId, text: a.text, suggestions: a.suggestions, by: name, actor: .agent, purpose: a.purpose, payload: a.payload) }

            let status: Status = asks.isEmpty
                ? try store.move(ticketId, to: .ready, actor: .hatch, reason: "filed by \(name)").status
                : .needsAnswers
            return IrisOutcome(questionsAsked: asks.count, suggestionStored: false, status: status)
        }
    }

    static func fieldQuestion(_ purpose: String, _ text: String, guess: String, others: [String]) -> Ask {
        Ask(text: text, suggestions: Array(([guess] + others.filter { $0 != guess }).prefix(IrisPrompt.maxSuggestions)), purpose: purpose, payload: nil)
    }

    /// The paths most often confused with this one, for the choices of a path question.
    static func alternatives(to path: WorkPath) -> [WorkPath] {
        switch path {
        case .bug: [.investigate, .small]
        case .investigate: [.bug, .question]
        case .visual: [.approaches, .small]
        case .approaches: [.visual, .question]
        case .small: [.visual, .bug]
        case .chore: [.small]
        case .question: [.approaches, .visual]
        case .split: []
        }
    }

    // MARK: The owner's decision

    /// Accept: the rewrite becomes the ticket text (the original stays in `originalTitle` and `originalBody`).
    /// The type changes only when `applyType` is true, and a duplicate link is created only when `linkDuplicate` is true.
    @discardableResult
    public static func accept(ticketId: Int, store: HatchStore, applyType: Bool = false, linkDuplicate: Bool = false) throws -> Ticket {
        let s = try pending(ticketId, store)
        return try resolve(ticketId, store, s, choice: "accept", title: s.rewrite?.title, body: s.rewrite?.body, actor: .agent, applyType: applyType, linkDuplicate: linkDuplicate)
    }

    /// Edit: the owner's own version of the rewrite becomes the ticket text.
    @discardableResult
    public static func edit(ticketId: Int, title: String, body: String, store: HatchStore, applyType: Bool = false, linkDuplicate: Bool = false) throws -> Ticket {
        let s = try pending(ticketId, store)
        return try resolve(ticketId, store, s, choice: "edit", title: title, body: body, actor: .owner, applyType: applyType, linkDuplicate: linkDuplicate)
    }

    /// Keep mine: the text stays as written. The type and duplicate choices are still the owner's.
    @discardableResult
    public static func keepMine(ticketId: Int, store: HatchStore, applyType: Bool = false, linkDuplicate: Bool = false) throws -> Ticket {
        let s = try pending(ticketId, store)
        return try resolve(ticketId, store, s, choice: "keep", title: nil, body: nil, actor: .owner, applyType: applyType, linkDuplicate: linkDuplicate)
    }

    private static func pending(_ id: Int, _ store: HatchStore) throws -> VettingSuggestion {
        guard let s = try store.pendingSuggestion(ticketId: id) else { throw StoreError.invalid("There is no pending suggestion from \(name) on this ticket.") }
        return s
    }

    private static func resolve(_ id: Int, _ store: HatchStore, _ s: VettingSuggestion, choice: String, title: String?, body: String?,
                                actor: Actor, applyType: Bool, linkDuplicate: Bool) throws -> Ticket {
        try store.db.transaction {
            if title != nil || body != nil { try store.update(id, title: title, body: body, actor: actor) }
            var typeChanged = false
            if applyType, let ts = s.typeSuggestion {
                try store.changeType(id, to: ts.type, actor: .owner, reason: ts.reason); typeChanged = true
            }
            var linked = false
            if linkDuplicate, let dup = s.duplicateOf { try store.link(from: id, to: dup, kind: .duplicates); linked = true }
            try store.resolveSuggestion(ticketId: id, choice: choice, typeChanged: typeChanged, duplicateLinked: linked)
            // With nothing left to answer the ticket is ready; questions still open keep it in Needs answers.
            let t = try store.ticket(id: id)!
            if t.status == .needsAnswers, try store.questions(ticketId: id, openOnly: true).isEmpty {
                return try store.move(id, to: .ready, actor: .hatch, reason: "suggestion decided")
            }
            return t
        }
    }
}
