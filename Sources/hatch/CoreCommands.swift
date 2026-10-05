import Foundation
import HatchCore
import HatchGit

typealias Handler = (Context) throws -> Void

/// Commands that only need the core store. Agent-facing commands (take, offer, ready, ...) live in AgentCommands.swift.
enum CoreCommands {
    static let all: [String: Handler] = [
        "init": initProject,
        "status": status,
        "ticket": ticket,
        "next": next,
        "ask": ask,
        "plan": plan,
        "note": note,
        "search": search,
        "admin": admin,
        "components": components,
        "new": new,
        "suggest": suggest,
    ]

    // hatch new "The toast feels cramped when the message is long" [--draft] [--project key]
    // A ticket from a prompt (decision WF-C1). Hatch's app has Iris file it within seconds; `hatch vet` does it here.
    static func new(_ c: Context) throws {
        let prompt = c.args.positionals.dropFirst().joined(separator: " ")
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { throw CLIError("Usage: hatch new \"what you want\" [--draft]") }
        let t = try c.store.capture(prompt: prompt, projectId: try c.project().id, draft: c.args.flag("draft"))
        c.out.emit(t.asJSON, text: "Created \(t.displayNumber). " + (t.status == .draft ? "Saved as a draft." : "Iris files it next (the app does it by itself, or run hatch vet \(t.displayNumber))."))
    }

    // hatch suggest #151 "The same bug is in the Postgres driver"
    // An agent's follow-up (decision WF-A2): filed by Iris like any prompt, linked to where it came from.
    static func suggest(_ c: Context) throws {
        let from = try c.ticket(c.args.pos(1))
        let prompt = c.args.rest(from: 2)
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { throw CLIError("Usage: hatch suggest #151 \"what should be done next\"") }
        let t = try c.store.capture(prompt: prompt, projectId: from.projectId, from: from.id, by: from.takenBy ?? "agent")
        c.out.emit(t.asJSON, text: "Suggested \(t.displayNumber), linked to \(from.displayNumber). Iris files it; nothing starts outside its normal path. Carry on with your own ticket.")
    }

    // hatch init [--config .hatch/project.json] [--key echo --name Echo --tickets owner/repo]
    static func initProject(_ c: Context) throws {
        if let path = c.args.option("config") {
            let config = try ProjectConfig.load(from: URL(fileURLWithPath: path))
            let key = c.args.option("key") ?? config.name.lowercased().filter { $0.isLetter || $0.isNumber }
            let p = try c.store.upsertProject(key: key, name: config.name, config: config)
            c.out.emit(["project": .string(p.key), "repos": .int(config.repos.count)], text: "Project \(p.key) registered with \(config.repos.count) repositories.")
        } else if let key = c.args.option("key"), let name = c.args.option("name") {
            let tickets = c.args.option("tickets") ?? ""
            let p = try c.store.upsertProject(key: key, name: name, config: ProjectConfig(name: name, ticketsRepo: tickets))
            c.out.emit(["project": .string(p.key)], text: "Project \(p.key) registered.")
        } else {
            throw CLIError("Usage: hatch init --config <.hatch/project.json> [--key echo]   or   hatch init --key echo --name Echo [--tickets owner/repo]")
        }
    }

    // hatch components            -> the project's components as agents see them, and values typed into views
    // hatch components scan <dir>  -> what Hatch finds in any app folder (no project needed)
    // hatch components roles [--template glass] [--element button] [--matrix] [--readme] -> the design system's roles (DS2)
    // hatch components templates   -> the templates a system can start from (DS6)
    // hatch components inventory [<app folder>] [--element button] [--all] -> every control, by place and look (DS4)
    static func components(_ c: Context) throws {
        switch c.args.pos(1) {
        case "inventory": try componentInventory(c); return
        case "start": try componentStart(c); return
        case "questions": try componentQuestions(c); return
        case "answer": try componentAnswer(c); return
        case "agree": try componentAgree(c); return
        case "follow": try componentFollow(c); return
        case "refs": try componentRefs(c); return
        case "check": try componentCheck(c); return
        case "generate": try componentGenerate(c); return
        default: break
        }
        if c.args.pos(1) == "templates" {
            let list = ComponentTemplates.all
            c.out.emit(.array(list.map { ["id": .string($0.id), "title": .string($0.title), "summary": .string($0.summary)] }),
                       text: list.map { "\($0.id)  \($0.title)\n    \($0.summary)" }.joined(separator: "\n"))
            return
        }
        if c.args.pos(1) == "roles" { try componentRoles(c); return }
        if c.args.pos(1) == "scan" {
            guard let dir = c.args.pos(2) else { throw CLIError("Usage: hatch components scan <app folder>") }
            let scan = ComponentsScanner.scan(appRoot: (dir as NSString).expandingTildeInPath)
            var lines = ["\(scan.swiftFiles) Swift files."]
            if scan.candidates.isEmpty { lines.append("No components found.") }
            for cand in scan.candidates {
                lines.append("\(cand.path)\(cand.isPackage ? " (package\(cand.product.map { ", import \($0)" } ?? ""))" : " (folder in the app)"): \(cand.summary)")
            }
            lines.append(scan.typedSummary.map { "Typed into views: \($0)." } ?? "No values typed into views.")
            for f in scan.typedFiles { lines.append("  \(f.count)  \(f.path)") }
            c.out.emit(["files": .int(scan.swiftFiles), "candidates": .array(scan.candidates.map { .string($0.path) }),
                        "typed": .int(scan.typedTotal)], text: lines.joined(separator: "\n"))
            return
        }
        let project = try c.project()
        guard let config = project.config, let label = config.componentsLabel else {
            throw CLIError("\(project.name) has no components yet. Set them up in Project settings, or run hatch components scan <app folder>.")
        }
        guard let folder = config.componentsFolder, FileManager.default.fileExists(atPath: folder) else {
            throw CLIError("\(label) is not on this Mac yet (no clone, or its setup ticket has not made it).")
        }
        let catalog = ComponentsScanner.catalog(at: folder, isPackage: config.components.map { $0.product != nil } ?? true)
        var lines = ["Components: \(label)" + (config.components?.product.map { ", import \($0)" } ?? "")]
        lines += catalog.isEmpty ? ["Nothing in it yet."] : catalog.briefLines(cap: c.args.flag("all") ? 10_000 : 16, values: c.args.flag("values"))
        if let app = config.repo(.app)?.localPath {
            let scan = ComponentsScanner.scan(appRoot: app, excluding: config.components?.path)
            lines.append(scan.typedSummary.map { "Typed into views elsewhere: \($0)." } ?? "No values typed into views elsewhere.")
        }
        c.out.emit(["components": .string(label), "colors": .int(catalog.colors.count), "fonts": .int(catalog.fonts.count),
                    "sizes": .int(catalog.sizes.count), "views": .int(catalog.views.count)], text: lines.joined(separator: "\n"))
    }

    /// Every control in the app by place and look: what setup recommends from. Free: it reads Swift text.
    static func componentInventory(_ c: Context) throws {
        let root: String, excluding: [String]
        if let dir = c.args.pos(2) {
            root = (dir as NSString).expandingTildeInPath; excluding = []
        } else {
            let project = try c.project()
            guard let app = project.config?.repo(.app)?.localPath else {
                throw CLIError("\(project.name) has no app clone on this Mac. Give a folder: hatch components inventory <app folder>.")
            }
            root = app; excluding = [project.config?.components?.path].compactMap { $0 }
        }
        let inv = ComponentInventoryScanner.scan(appRoot: root, excluding: excluding)
        var elements = inv.elements
        if let only = c.args.option("element") { elements = elements.filter { $0 == only } }
        let cap = c.args.flag("all") ? Int.max : 4
        var lines = ["\(inv.uses.count) controls in \(inv.swiftFiles) Swift files."]
        for e in elements {
            let element = ComponentElement.named(e)
            lines.append("\n\(element?.plural ?? e) (\(inv.uses.filter { $0.element == e }.count))")
            for (place, count) in inv.places(of: e) {
                let looks = inv.clusters(element: e, place: place)
                let title = ComponentPlace.title(place)
                lines.append("  \(title) (\(count)): \(looks.count) look\(looks.count == 1 ? "" : "s")")
                for l in looks.prefix(cap) {
                    let n = String(l.count).padding(toLength: 4, withPad: " ", startingAt: 0)
                    lines.append("    \(n) \(l.signature)" + (l.importance == .other ? "" : " [\(l.importance.title.lowercased())]") + "   e.g. " + l.examples.joined(separator: ", "))
                }
                if looks.count > cap { lines.append("         and \(looks.count - cap) more (--all)") }
                if place == nil {
                    lines.append("    most in: " + inv.unknownFiles(element: e, limit: 4).map { "\(($0.file as NSString).lastPathComponent) \($0.count)" }.joined(separator: ", "))
                }
            }
        }
        let cov = inv.coverage
        lines.append("\nUsing a role: \(cov.withRole) of \(cov.total).")
        let json: JSONValue = ["controls": .int(inv.uses.count), "files": .int(inv.swiftFiles), "withRole": .int(cov.withRole),
                               "unknownPlace": .int(inv.uses.filter { $0.place == nil }.count),
                               "uses": .array(inv.uses.map { u in
                                   ["element": .string(u.element), "place": u.place.map { .string($0) } ?? .null, "look": .string(u.signature),
                                    "importance": .string(u.importance.rawValue), "file": .string(u.file), "line": .int(u.line),
                                    "evidence": .string(u.evidence),
                                    "trail": .array(u.trail.map { .string($0) })]
                               })]
        c.out.emit(json, text: lines.joined(separator: "\n"))
    }

    /// The rules, read from a template or from the project's notebook. Read-only: the system changes through Hatch.
    static func componentRoles(_ c: Context) throws {
        let system: ComponentSystem
        if let id = c.args.option("template") {
            guard let t = ComponentTemplates.named(id) else {
                throw CLIError("No template called \(id). Templates: \(ComponentTemplates.all.map(\.id).joined(separator: ", ")).")
            }
            system = t.system(name: (try? c.project().name) ?? "This app")
        } else {
            let project = try c.project()
            guard let notebook = project.config?.repo(.notebook)?.localPath else {
                throw CLIError("\(project.name) has no notebook on this Mac, so it has no design system here. See a template with hatch components roles --template glass.")
            }
            guard let found = try ComponentSystem.load(notebook: notebook) else {
                throw CLIError("\(project.name) has no design system yet (\(ComponentSystem.notebookPath) in the notebook). See a template with hatch components roles --template glass.")
            }
            system = found
        }
        if c.args.flag("readme") {
            c.out.emit(["readme": .string(system.readme())], text: system.readme())
            return
        }
        var elements = system.elementsUsed
        if let only = c.args.option("element") {
            guard elements.contains(only) else { throw CLIError("No roles for \(only). Elements with roles: \(elements.joined(separator: ", ")).") }
            elements = [only]
        }
        let n = system.counts
        var lines = ["\(system.name): baseline v\(system.version)" + (system.template.flatMap { ComponentTemplates.named($0)?.title }.map { ", from the \($0) template" } ?? "")
                     + ". \(system.roles.count) roles: \(n.agreed) agreed, \(n.provisional) provisional" + (n.inRedesign > 0 ? ", \(n.inRedesign) in redesign" : "") + "."]
        for e in elements {
            lines.append("\n" + (ComponentElement.named(e)?.plural ?? e))
            if c.args.flag("matrix") {
                let m = system.matrix(element: e)
                let width = max(12, (m.places.map(\.title.count).max() ?? 0) + 2)
                func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s + " " : s + String(repeating: " ", count: w - s.count) }
                lines.append("  " + pad("", width) + m.importances.map { pad($0.title, 22) }.joined())
                for (i, p) in m.places.enumerated() {
                    lines.append("  " + pad(p.title, width) + m.cells[i].map { pad($0?.id ?? "·", 22) }.joined())
                }
                continue
            }
            for r in system.roles(of: e) {
                let places = r.places.map { system.place($0)?.title ?? $0 }.joined(separator: ", ") + (r.perScreen.map { "; at most \($0) per screen" } ?? "")
                lines.append("  \(r.id)  \(r.title)  [\(r.status.title)]  \(r.codeName)")
                lines.append("      use: \(r.use)")
                if !r.avoid.isEmpty { lines.append("      not: \(r.avoid)") }
                lines.append("      where: \(places)")
                lines.append("      look: \(r.lookSummary)")
                if !r.sources.isEmpty { lines.append("      why: " + r.sources.compactMap { ComponentNative.reference($0)?.url }.joined(separator: " ")) }
                for v in r.variants { lines.append("      variant \(v.id): \(v.use) (\(ComponentRole.summary(v.recipe)))") }
            }
        }
        let problems = system.problems()
        if !problems.isEmpty { lines.append("\nProblems:\n" + problems.map { "  - " + $0 }.joined(separator: "\n")) }
        let advice = system.advice()
        if !advice.isEmpty {
            lines.append("\nAgainst Apple's guidance:\n" + advice.map { "  - \($0.message) (\(ComponentNative.reference($0.source)?.url ?? $0.source))" }.joined(separator: "\n"))
        }
        var json = JSONValue.parse(String(decoding: try system.encoded(), as: UTF8.self)).objectValue ?? [:]
        json["problems"] = .array(problems.map { .string($0) })
        c.out.emit(.object(json), text: lines.joined(separator: "\n"))
    }

    // hatch status
    static func status(_ c: Context) throws {
        let pid = try? c.project().id
        let counts = try c.store.countByTurn(projectId: pid)
        let queue = try c.store.deskQueue(projectId: pid)
        let sync = try c.store.syncCounts()
        let json: JSONValue = [
            "waitingForYou": .int(counts[.you] ?? 0), "withAgents": .int(counts[.agent] ?? 0), "withHatch": .int(counts[.hatch] ?? 0),
            "syncPending": .int(sync.pending), "syncFailed": .int(sync.failed),
            "agentsRunning": .int(try c.store.activeAgentCount()),
        ]
        var text = "Waiting for you: \(counts[.you] ?? 0)   With agents: \(counts[.agent] ?? 0)   With Hatch: \(counts[.hatch] ?? 0)\n"
        text += "Sync: \(sync.pending) pending, \(sync.failed) failed   Agents running: \(try c.store.activeAgentCount())"
        for group in queue { text += "\n\n\(group.status.displayName)\n" + group.tickets.map { "  " + $0.oneLine }.joined(separator: "\n") }
        c.out.emit(json, text: text)
    }

    // hatch ticket new|list|show|link|undo-split|reset
    static func ticket(_ c: Context) throws {
        switch c.args.pos(1) {
        case "new": try ticketNew(c)
        case "list": try ticketList(c)
        case "show": try ticketShow(c)
        case "link": try ticketLink(c)
        case "undo-split": try ticketUndoSplit(c)
        case "reset": try ticketReset(c)
        default: throw CLIError("Usage: hatch ticket new|list|show|link|undo-split|reset ...")
        }
    }

    static func ticketNew(_ c: Context) throws {
        let p = try c.project()
        guard let typeName = c.args.option("type"), let type = TicketType(rawValue: typeName) else {
            throw CLIError("--type must be one of: \(TicketType.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        guard let title = c.args.option("title") else { throw CLIError("--title is required.") }
        let parent = try c.args.option("parent").map { try c.store.resolve($0).id }
        var t = try c.store.createTicket(projectId: p.id, type: type, title: title, body: c.args.option("body") ?? "", area: c.args.option("area"), parentId: parent)
        if c.args.flag("submit") { t = try c.store.move(t.id, to: .checking, actor: .owner) }
        c.out.emit(t.asJSON, text: "Created \(t.oneLine)")
    }

    static func ticketList(_ c: Context) throws {
        var filter = TicketFilter(projectId: try? c.project().id)
        if let s = c.args.option("status") { filter.statuses = s.split(separator: ",").compactMap { Status(rawValue: String($0)) } }
        if let t = c.args.option("type") { filter.types = t.split(separator: ",").compactMap { TicketType(rawValue: String($0)) } }
        if let t = c.args.option("turn") { filter.turn = Turn(rawValue: t) }
        if let q = c.args.option("text") { filter.text = q }
        if c.args.flag("all") { filter.projectId = nil }
        let tickets = try c.store.tickets(filter)
        c.out.emit(.array(tickets.map(\.asJSON)), text: tickets.isEmpty ? "No tickets." : tickets.map(\.oneLine).joined(separator: "\n"))
    }

    static func ticketShow(_ c: Context) throws {
        let t = try c.ticket(c.args.pos(2))
        let notes = try c.store.notes(ticketId: t.id), questions = try c.store.questions(ticketId: t.id), links = try c.store.links(ticketId: t.id)
        var text = "\(t.oneLine)\nTurn: \(Theme.title(t.turn))   Revision: \(t.revision)   Taken by: \(t.takenBy ?? "nobody")\n\n\(t.body)"
        if !questions.isEmpty { text += "\n\nQuestions:\n" + questions.map { "  [\($0.isOpen ? "open" : "answered")] \($0.text)" + ($0.answer.map { " -> \($0)" } ?? "") }.joined(separator: "\n") }
        if !links.isEmpty { text += "\n\nLinks:\n" + links.map { "  \($0.link.kind.rawValue) \($0.outgoing ? "->" : "<-") \((try? c.store.ticket(id: $0.outgoing ? $0.link.toId : $0.link.fromId))??.displayNumber ?? "?")" }.joined(separator: "\n") }
        if !notes.isEmpty { text += "\n\nThread:\n" + notes.map { "  \($0.author) (\($0.kind.rawValue)): \($0.body)" }.joined(separator: "\n") }
        var json = t.asJSON.objectValue ?? [:]
        json["body"] = .string(t.body)
        json["notes"] = .array(notes.map { ["kind": .string($0.kind.rawValue), "author": .string($0.author), "body": .string($0.body)] })
        json["questions"] = .array(questions.map { ["id": .int($0.id), "text": .string($0.text), "answer": $0.answer.map { .string($0) } ?? .null] })
        c.out.emit(.object(json), text: text)
    }

    // hatch ticket reset #151: starts the ticket again from the owner's first prompt (decision IR16). For debugging.
    static func ticketReset(_ c: Context) throws {
        let t = try c.ticket(c.args.pos(2))
        let result = try TicketReset.run(store: c.store, ticketId: t.id)
        let extra = result.leftovers.isEmpty ? "" : "\nCould not remove: " + result.leftovers.joined(separator: "; ")
        c.out.emit(["ticket": .string(result.ticket.displayNumber), "status": .string(result.ticket.status.rawValue), "leftovers": .array(result.leftovers.map { .string($0) })],
                   text: "\(result.ticket.displayNumber) is back to your first prompt; Iris files it again.\(extra)")
    }

    // hatch ticket undo-split #151: puts a split back as one ticket (decision IR5). Refused once a part has started.
    static func ticketUndoSplit(_ c: Context) throws {
        let t = try c.ticket(c.args.pos(2))
        let back = try c.store.undoSplit(t.id)
        c.out.emit(["ticket": .string(back.displayNumber), "status": .string(back.status.rawValue)], text: "\(back.displayNumber) is one ticket again; Iris checks it without splitting.")
    }

    static func ticketLink(_ c: Context) throws {
        let a = try c.ticket(c.args.pos(2)), b = try c.ticket(c.args.pos(3))
        guard let kind = LinkKind(rawValue: c.args.option("kind") ?? "related") else { throw CLIError("--kind must be one of: \(LinkKind.allCases.map(\.rawValue).joined(separator: ", "))") }
        try c.store.link(from: a.id, to: b.id, kind: kind)
        c.out.emit(["from": .string(a.displayNumber), "to": .string(b.displayNumber), "kind": .string(kind.rawValue)], text: "\(a.displayNumber) \(kind.rawValue) \(b.displayNumber)")
    }

    // hatch next
    static func next(_ c: Context) throws {
        let work = try c.store.agentWork(projectId: try? c.project().id)
        let json: JSONValue = .array(work.map { ["ticket": .string($0.ticket.displayNumber), "task": .string($0.kind.rawValue), "title": .string($0.ticket.title), "type": .string($0.ticket.type.rawValue)] })
        let text = work.isEmpty ? "Nothing waiting for an agent." : work.map { "\($0.ticket.displayNumber)  \($0.kind.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \($0.ticket.title)\n    take it with: hatch take \($0.ticket.displayNumber) --agent \"Agent on \($0.ticket.displayNumber)\"" }.joined(separator: "\n")
        c.out.emit(json, text: text)
    }

    // hatch ask #151 "question" [--suggest a --suggest b] [--by Iris]
    static func ask(_ c: Context) throws {
        let t = try c.ticket(c.args.pos(1))
        let text = c.args.rest(from: 2)
        guard !text.isEmpty else { throw CLIError("Usage: hatch ask #151 \"the question\" --suggest \"your recommendation\" [--suggest \"another answer\"]...") }
        // Accept on the Desk takes the first suggestion, so a question with none cannot be answered from there (decision IR17).
        guard !c.args.list("suggest").isEmpty else {
            throw CLIError("Offer the answers you see, your recommendation first: hatch ask '\(t.displayNumber)' \"the question\" --suggest \"your recommendation\" --suggest \"another answer\". Put each option in its own --suggest, not in the question text.")
        }
        let q = try c.store.ask(t.id, text: text, suggestions: c.args.list("suggest"), by: c.args.option("by") ?? t.takenBy ?? "agent")
        let after = try c.store.ticket(id: t.id)!
        c.out.emit(["question": .int(q.id), "status": .string(after.status.rawValue)], text: "Asked. \(after.displayNumber) is now \(after.status.displayName); the owner will answer.")
    }

    // hatch plan #144 --files "a/b.swift,c/**" [--repo app]
    static func plan(_ c: Context) throws {
        let t = try c.ticket(c.args.pos(1))
        // hatch plan #144 --wait: block until the owner decides a plan that waits for approval (decision DC8).
        if c.args.flag("wait") || c.args.flag("status") {
            guard var review = try c.store.latestPlanReview(ticketId: t.id) else { throw CLIError("\(t.displayNumber) has no plan waiting for the owner.") }
            let deadline = Date().addingTimeInterval(c.args.flag("wait") ? 3600 : 0)
            while review.state == .pending && Date() < deadline {
                Thread.sleep(forTimeInterval: 5)
                review = try c.store.planReview(id: review.id) ?? review
            }
            let note = review.note.map { "\nThe owner's note: \($0)" } ?? ""
            switch review.state {
            case .approved: c.out.emit(["plan": "approved"], text: "The owner approved the plan. Go ahead." + note)
            case .sentBack: c.out.emit(["plan": "sent-back"], text: "The owner sent the plan back. Change it and run hatch plan again." + note)
            case .pending: c.out.emit(["plan": "pending"], text: "The plan still waits for the owner. Run hatch plan \(t.displayNumber) --wait to wait for the answer.")
            }
            return
        }
        let files = (c.args.option("files") ?? c.args.rest(from: 2)).split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !files.isEmpty else { throw CLIError("Usage: hatch plan #144 --files \"path/one.swift,folder/**\" [--repo app]") }
        var repoId: Int?
        if let role = c.args.option("repo") {
            guard let r = try c.store.repos(projectId: t.projectId).first(where: { $0.role.rawValue == role }) else { throw CLIError("No repo with role '\(role)'.") }
            repoId = r.id
        }
        try c.store.record(t.id, actor: t.takenBy ?? "agent", kind: "plan", payload: ["files": .array(files.map { .string($0) })])
        let outcome = try c.store.claim(ticketId: t.id, repoId: repoId, paths: files)
        let after = try c.store.ticket(id: t.id)!
        switch outcome {
        case .granted:
            // A Bug, or more files than the project allows, waits for the owner to approve the plan (decisions I2, DC8).
            let limit = (try c.store.project(id: t.projectId))?.config?.planApprovalFileThreshold ?? 8
            let approved = (try c.store.latestPlanReview(ticketId: t.id))?.state == .approved
            if !approved && (t.type == .bug || files.count > limit) {
                let reason = t.type == .bug ? "a Bug" : "\(files.count) files, over the limit of \(limit)"
                try c.store.requestPlanReview(ticketId: t.id, files: files, reason: reason)
                c.out.emit(["claim": "granted", "plan": "pending", "files": .int(files.count)],
                           text: "Claim granted, but this plan waits for the owner (\(reason)). Do not edit yet. Run hatch plan \(t.displayNumber) --wait to wait for the answer.")
                return
            }
            c.out.emit(["claim": "granted", "files": .int(files.count)], text: "Claim granted for \(files.count) path(s). Go ahead.")
        case .queued(let behind):
            let names = try behind.compactMap { try c.store.ticket(id: $0)?.displayNumber }
            c.out.emit(["claim": "queued", "behind": .array(names.map { .string($0) }), "status": .string(after.status.rawValue)],
                       text: "Those files are claimed by \(names.joined(separator: ", ")). \(after.displayNumber) is now \(after.status.displayName) and will resume by itself when they are free. Stop working on it now.")
        }
    }

    // hatch note #151 "text" [--kind note|comment|agent] [--by name]
    static func note(_ c: Context) throws {
        let t = try c.ticket(c.args.pos(1))
        let body = c.args.rest(from: 2)
        let kind = NoteKind(rawValue: c.args.option("kind") ?? "agent") ?? .agent
        guard kind != .ask && kind != .instruction else { throw CLIError("Only the owner sends Ask and Instruction notes; use hatch ask to question the owner.") }
        let n = try c.store.addNote(t.id, kind: kind, author: c.args.option("by") ?? t.takenBy ?? "agent", body: body)
        c.out.emit(["note": .int(n.id)], text: "Note added to \(t.displayNumber).")
    }

    // hatch search "words" [--specs]
    static func search(_ c: Context) throws {
        let q = c.args.rest(from: 1)
        guard !q.isEmpty else { throw CLIError("Usage: hatch search \"words\"") }
        let p = try? c.project()
        let tickets = try c.store.tickets(TicketFilter(projectId: p?.id, text: q, limit: 15))
        let specs = try p.map { try c.store.searchSpec(projectId: $0.id, query: q, limit: 8) } ?? []
        let json: JSONValue = ["tickets": .array(tickets.map(\.asJSON)), "specs": .array(specs.map { ["code": .string($0.code), "text": .string($0.text)] })]
        var text = tickets.map(\.oneLine).joined(separator: "\n")
        if !specs.isEmpty { text += (text.isEmpty ? "" : "\n\n") + "Spec:\n" + specs.map { "  \($0.code)  \($0.text)" }.joined(separator: "\n") }
        c.out.emit(json, text: text.isEmpty ? "No matches." : text)
    }

    // hatch admin move|resume|answer|type  -- bookkeeping for people and for Hatch itself, NOT for agents
    static func admin(_ c: Context) throws {
        switch c.args.pos(1) {
        case "move":
            let t = try c.ticket(c.args.pos(2))
            guard let s = c.args.pos(3), let status = Status(rawValue: s) else { throw CLIError("Usage: hatch admin move #151 <status> --as owner|agent|hatch") }
            let after = try c.store.move(t.id, to: status, actor: try c.actor(default: .owner), reason: c.args.option("reason"))
            c.out.emit(after.asJSON, text: after.oneLine)
        case "resume":
            let after = try c.store.resume(try c.ticket(c.args.pos(2)).id, actor: try c.actor(default: .owner))
            c.out.emit(after.asJSON, text: after.oneLine)
        case "answer":
            guard let qid = c.args.pos(2).flatMap(Int.init) else { throw CLIError("Usage: hatch admin answer <question id> \"text\"") }
            let after = try c.store.answer(questionId: qid, text: c.args.rest(from: 3))
            c.out.emit(after.asJSON, text: after.oneLine)
        case "type":
            guard let t = c.args.pos(3).flatMap(TicketType.init(rawValue:)) else { throw CLIError("Usage: hatch admin type #151 <type>") }
            let after = try c.store.changeType(try c.ticket(c.args.pos(2)).id, to: t, actor: try c.actor(default: .owner), reason: c.args.option("reason"))
            c.out.emit(after.asJSON, text: after.oneLine)
        default: throw CLIError("Usage: hatch admin move|resume|answer|type ...")
        }
    }
}

/// Plain copies of the app's turn titles for the CLI (the CLI does not link SwiftUI).
enum Theme {
    static func title(_ t: Turn) -> String {
        switch t { case .you: "Your turn"; case .agent: "Agent's turn"; case .hatch: "Hatch"; case .finished: "Finished"; case .paused: "Paused" }
    }
}
