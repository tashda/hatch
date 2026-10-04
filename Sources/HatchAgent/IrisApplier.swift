import Foundation
import HatchCore

public struct IrisOutcome: Equatable, Sendable {
    public var questionsAsked: Int
    public var suggestionStored: Bool
    /// The ticket's status after Iris's result was applied.
    public var status: Status
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

    @discardableResult
    public static func apply(_ result: VettingResult, to ticketId: Int, store: HatchStore) throws -> IrisOutcome {
        try store.db.transaction {
            guard let t = try store.ticket(id: ticketId) else { throw StoreError.notFound("ticket \(ticketId)") }
            guard t.status == .checking else {
                throw StoreError.invalid("\(t.displayNumber) is \(t.status.displayName), not Checking, so Iris's answer was not applied.")
            }
            // At most two rounds of questions (decision WF-Q1): after that Iris files with what she has.
            let rounds = try store.events(ticketId: ticketId, kinds: ["status"]).filter {
                $0.payload["from"]?.stringValue == Status.checking.rawValue && $0.payload["to"]?.stringValue == Status.needsAnswers.rawValue
            }.count
            let mayAsk = rounds < maxRounds
            let config = try store.project(id: t.projectId)?.config
            var asks: [Ask] = []

            // What she is sure of is filed now.
            var filing = Filing()
            let path = result.effectivePath
            if let path, path != .split {
                if result.isSure("path") || !mayAsk { filing.path = path }
                else { asks.append(fieldQuestion(QuestionPurpose.path, "Is this a \(path.displayName.lowercased())?", guess: path.displayName,
                                                 others: alternatives(to: path).map(\.displayName))) }
            }
            if let r = result.rewrite {
                filing.title = r.title.isEmpty ? nil : r.title
                filing.body = r.body.isEmpty ? nil : r.body
            }
            if let area = result.area, let known = config?.areas.first(where: { $0.name.caseInsensitiveCompare(area) == .orderedSame }) {
                if result.isSure("area") || !mayAsk { filing.area = known.name }
                else {
                    let others = (config?.areas ?? []).map(\.name).filter { $0 != known.name }.prefix(2)
                    asks.append(fieldQuestion(QuestionPurpose.area, "Which part of the app is this about?", guess: known.name, others: Array(others)))
                }
            }
            filing.priority = result.priority.flatMap(TicketPriority.value)
            filing.verify = result.verify
            if let key = result.project, let target = try store.projects().first(where: { $0.key == key }), target.id != t.projectId,
               try store.canMoveProject(t, to: target.id) {
                if result.isSure("project") || !mayAsk { filing.projectId = target.id }
                else { asks.append(fieldQuestion(QuestionPurpose.project, "Does this belong to \(target.name)?", guess: target.key, others: [IrisChoices.keepProject])) }
            }
            filing.related = result.related.compactMap { (try? store.resolve($0))?.id }.filter { $0 != t.id }
            filing.blocks = result.blocks.compactMap { (try? store.resolve($0))?.id }.filter { $0 != t.id }
            if let ref = result.parent, let parent = try? store.resolve(ref), parent.type == .theme { filing.parentId = parent.id }
            filing.specTouches = result.specTouches
            try store.file(ticketId, filing, by: name)

            // A plain repeat is closed onto the original; a likely one is asked (decision WF-T5).
            if let ref = result.duplicateOf, let dup = try? store.resolve(ref), dup.id != t.id, !dup.status.isTerminal || dup.status == .done {
                if result.duplicateSure {
                    let closed = try store.closeAsDuplicate(ticketId, of: dup.id, by: name)
                    return IrisOutcome(questionsAsked: 0, suggestionStored: false, status: closed.status)
                }
                if mayAsk {
                    asks.insert(Ask(text: "Is this the same as \(dup.displayNumber) \(dup.title)?", suggestions: [IrisChoices.duplicateYes, IrisChoices.duplicateNo],
                                    purpose: QuestionPurpose.duplicate, payload: ["of": .int(dup.id)]), at: 0)
                }
            }
            // Several things in one prompt: one card to confirm the split (decision WF-T4).
            if path == .split, result.split.count >= 2, mayAsk {
                let names = result.split.map(\.title).joined(separator: "; ")
                let children: JSONValue = .array(result.split.map { ["title": .string($0.title), "body": .string($0.body),
                                                                    "path": $0.path.map { .string($0.rawValue) } ?? .null] })
                asks.insert(Ask(text: "This reads as \(result.split.count) separate things: \(names). Split it into a Theme with one ticket each?",
                                suggestions: [IrisChoices.splitYes, IrisChoices.splitNo], purpose: QuestionPurpose.split, payload: ["children": children]), at: 0)
            }
            // Her own questions; a clash with a decision or a component says what it is about (WF-T6, WF-T8).
            if mayAsk {
                for q in result.questions {
                    asks.append(Ask(text: q.text, suggestions: q.suggestions, purpose: q.about == nil ? nil : QuestionPurpose.conflict,
                                    payload: q.about.map { ["about": .string($0)] }))
                }
            }
            asks = Array(asks.prefix(IrisPrompt.maxQuestions))
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
