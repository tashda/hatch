import Foundation
import HatchCore

/// What `hatch take` prints: everything an agent needs for one ticket, in a fixed order, as compact deterministic text.
/// The rules for the task kind are written here once, so no agent has to remember a procedure (the owner's rule).
public enum BriefBuilder {
    public static let bodyLimit = 1500
    public static let relatedCap = 6
    public static let specCap = 8
    /// Earlier decisions in a brief: few, because each one is a line the agent reads on every run.
    public static let decisionCap = 3
    public static let notesCap = 8

    /// The task the ticket is in now. A taken ticket has already moved (Ready becomes Preparing or Building).
    public static func taskKind(for t: Ticket) -> AgentTaskKind? {
        switch t.status {
        case .checking: return .vet
        case .preparing: return .prepare
        case .building: return .build
        case .revising: return .revise
        case .fixing: return .fix
        default: return HatchStore.taskKind(for: t.status, type: t.type)
        }
    }

    public static func brief(store: HatchStore, ticketId: Int, agent: String, kind: AgentTaskKind? = nil) throws -> String {
        guard let t = try store.ticket(id: ticketId) else { throw StoreError.notFound("ticket \(ticketId)") }
        let kind = kind ?? taskKind(for: t)
        let project = try store.project(id: t.projectId)
        let config = project?.config
        var out: [String] = []

        out.append("# \(t.displayNumber) \(t.type.displayName) · \(t.status.displayName) · \(t.title)")
        out.append("You are \(agent). Task: \(kind.map(taskLine) ?? "none; this ticket is \(t.status.displayName) and waits for someone else.")")
        out.append("Project: \(project?.name ?? "?")" + (t.revision > 1 ? " · revision \(t.revision)" : ""))

        out.append("\n## Ticket")
        out.append(t.body.isEmpty ? "(no description)" : Text.clip(t.body, bodyLimit))
        // With Iris's reading, the body already starts with the owner's own words.
        if (t.originalTitle != t.title || t.originalBody != t.body), !t.body.contains(IrisReading.marker) {
            out.append("\nOriginal text (the owner's own words, before the rewrite):")
            out.append(Text.indent("\(t.originalTitle ?? t.title)\n" + Text.clip(t.originalBody ?? "", 600)))
        }

        out += try screenshotLines(store, t)

        // The owner's answers to Iris's questions.
        let answered = try store.questions(ticketId: t.id).filter { !$0.isOpen }
        if !answered.isEmpty {
            out.append("\n## Owner's answers")
            for q in answered { out.append("- \(Text.oneLine(q.text, 160)) -> \(Text.oneLine(q.answer ?? "", 300))") }
        }
        let open = try store.questions(ticketId: t.id, openOnly: true)
        if !open.isEmpty {
            out.append("\n## Still unanswered")
            for q in open { out.append("- \(Text.oneLine(q.text, 160))") }
        }

        out += try proposalState(store, t, kind)
        out += try recentNotes(store, t)
        out += try linkLines(store, t)
        out += try relatedLines(store, t)
        out += try specLines(store, t)
        out += try decisionLines(store, t)
        out += areaLines(config, t)
        out += componentLines(config, t, kind)
        out += try sweepLines(store, t, kind, config)
        out += try repoLines(store, t)
        out += try notebookLines(store, t, config: config)
        if let config, !config.docs.isEmpty {
            out.append("\n## Docs to read")
            out.append(config.docs.map { "- \($0)" }.joined(separator: "\n"))
        }

        out.append("\n## Rules for this task")
        out.append(rules(kind: kind, ticket: t, config: config).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        out.append("\n## Next")
        out.append(nextCommands(kind: kind, ticket: t).joined(separator: "\n"))
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: Sections

    private static func taskLine(_ k: AgentTaskKind) -> String {
        switch k {
        case .vet: return "vet the ticket (questions, rewrite, type check)."
        case .prepare: return "prepare what the owner will judge."
        case .build: return "build the change."
        case .revise: return "revise the offer after the owner's feedback."
        case .fix: return "fix what the owner found while verifying."
        }
    }

    /// Picks, verdicts and pins: the owner's judgement of a Proposal. Only the tasks that continue from it need them.
    private static func proposalState(_ store: HatchStore, _ t: Ticket, _ kind: AgentTaskKind?) throws -> [String] {
        guard kind == .revise || kind == .build || kind == .fix else { return [] }
        var out: [String] = []
        let picks = try store.picks(ticketId: t.id)
        if !picks.isEmpty {
            out.append("\n## Owner's choices")
            for p in picks { out.append("- \(p.topic) = \(p.choice)" + (p.note.map { " (\(Text.oneLine($0, 200)))" } ?? "")) }
        }
        let verdicts = try store.verdicts(ticketId: t.id).filter { $0.verdict != "pick" }
        if !verdicts.isEmpty && kind == .revise {
            out.append("\n## Verdicts (maybe = keep refining, no = do not bring back)")
            for v in verdicts { out.append("- \(v.topic)/\(v.option): \(v.verdict)" + (v.note.map { " (\(Text.oneLine($0, 200)))" } ?? "")) }
        }
        let pins = try store.pins(ticketId: t.id)
        if !pins.isEmpty && kind == .revise {
            out.append("\n## Pinned notes")
            for p in pins.prefix(notesCap) {
                var where_: [String] = []
                if let o = p.option { where_.append(o) }
                if let s = p.scenario { where_.append(s) }
                if let a = p.appearance { where_.append(a) }
                if let c = p.corners { where_.append("corners \(c)") }
                out.append("- " + (where_.isEmpty ? "" : "[\(where_.joined(separator: ", "))] ") + Text.oneLine(p.text, 240))
            }
            if pins.count > notesCap { out.append("- ... and \(pins.count - notesCap) more (hatch show \(t.displayNumber))") }
        }
        if kind == .revise, let sendBack = try store.notes(ticketId: t.id).last(where: { $0.kind == .instruction }),
           let reason = sendBack.context?["reason"]?.stringValue {
            out.append("\nSend-back reason: \(reason)")
        }
        return out
    }

    /// Notes, asks and instructions the owner wrote since the agent last handed something back.
    private static func recentNotes(_ store: HatchStore, _ t: Ticket) throws -> [String] {
        let noteEvents = try store.events(ticketId: t.id, kinds: ["note", "offer", "ready"])
        func noteKind(_ e: Event) -> String? { e.kind == "note" ? e.payload["kind"]?.stringValue : nil }
        var cutoff = 0
        for e in noteEvents where e.kind == "offer" || e.kind == "ready" || noteKind(e) == "agent" { cutoff = max(cutoff, e.id) }
        var noteIDs = Set<Int>()
        for e in noteEvents where e.id > cutoff {
            if let k = noteKind(e), ["note", "ask", "instruction", "comment"].contains(k), let id = e.payload["note"]?.intValue { noteIDs.insert(id) }
        }
        let notes = try store.notes(ticketId: t.id).filter { noteIDs.contains($0.id) }
        guard !notes.isEmpty else { return [] }
        var out = ["\n## Since your last turn"]
        let shown = notes.suffix(notesCap)
        if notes.count > shown.count { out.append("(\(notes.count - shown.count) older not shown)") }
        for n in shown { out.append("- [\(n.kind.rawValue)] \(n.author): \(Text.oneLine(n.body, 400))") }
        return out
    }

    private static func describe(_ t: Ticket) -> String { "\(t.displayNumber) [\(t.type.rawValue), \(t.status.rawValue)] \(Text.oneLine(t.title, 90))" }

    private static func linkLines(_ store: HatchStore, _ t: Ticket) throws -> [String] {
        let links = try store.links(ticketId: t.id)
        var lines: [String] = []
        for (link, outgoing) in links.sorted(by: { ($0.link.kind.rawValue, $0.link.toId, $0.link.fromId) < ($1.link.kind.rawValue, $1.link.toId, $1.link.fromId) }) {
            guard let other = try store.ticket(id: outgoing ? link.toId : link.fromId) else { continue }
            let label = outgoing ? link.kind.rawValue : "is \(link.kind.rawValue) of"
            lines.append("- \(label) \(describe(other))")
        }
        return lines.isEmpty ? [] : ["\n## Links"] + lines
    }

    private static func relatedLines(_ store: HatchStore, _ t: Ticket) throws -> [String] {
        let linked = Set(try store.links(ticketId: t.id).map { $0.outgoing ? $0.link.toId : $0.link.fromId })
        let similar = try store.similarTickets(projectId: t.projectId, title: t.title, body: t.body, excluding: t.id, limit: relatedCap + linked.count + 2)
            .map(\.ticket).filter { !linked.contains($0.id) && $0.status != .dropped }.prefix(relatedCap)
        return similar.isEmpty ? [] : ["\n## Related tickets (search)"] + similar.map { "- " + describe($0) }
    }

    private static func specLines(_ store: HatchStore, _ t: Ticket) throws -> [String] {
        let hits = try store.searchSpec(projectId: t.projectId, query: t.title + " " + t.body, limit: specCap)
        return hits.isEmpty ? [] : ["\n## Spec items (search)"] + hits.map { "- \($0.code): \(Text.oneLine($0.text, 160))" }
    }

    /// Earlier decisions that match the ticket, from the free local search: title and one line of why, plus the file
    /// to open if the agent needs the options. Never the whole decision log.
    private static func decisionLines(_ store: HatchStore, _ t: Ticket) throws -> [String] {
        let hits = try store.searchDecisions(projectId: t.projectId, query: t.title + " " + t.body, area: t.area, limit: decisionCap)
            .filter { $0.ticketId != t.id }
        guard !hits.isEmpty else { return [] }
        return ["\n## Earlier decisions (search; do not undo one without asking)"] + hits.map { d in
            var line = "- \(d.ticketNumber) \(d.kind.rawValue): \(Text.oneLine(d.title.isEmpty ? d.summary : d.title, 90))"
            if let why = d.reason, !why.isEmpty { line += ". Why: \(Text.oneLine(why, 140))" }
            if let file = d.filePath { line += " (\(Notebook.decisionsDir)/\((file as NSString).lastPathComponent))" }
            return line
        }
    }

    /// Where the notebook is, which rules apply and where the Spec is edited. The area's rule file is named only when the
    /// ticket has an area and the file exists, so detailed rules cost tokens only for the work that needs them.
    private static func notebookLines(_ store: HatchStore, _ t: Ticket, config: ProjectConfig?) throws -> [String] {
        guard let notebook = try store.repo(projectId: t.projectId, role: .notebook), let dir = notebook.localPath else { return [] }
        let fm = FileManager.default
        var out = ["\n## Notebook (\(notebook.remote))"]
        out.append("- Spec: `\(Notebook.specDir)/` in your notebook workspace. Update the items you change on the same ticket branch and commit them, then run `hatch ready` with `--spec <IDs>`, or `--spec unchanged`.")
        if let area = t.area {
            let file = "rules/areas/\(HatchStore.slug(area)).md"
            if fm.fileExists(atPath: (dir as NSString).appendingPathComponent(file)) { out.append("- Rules for \(area): `\(file)` in the notebook. Read it.") }
        }
        // The app's own committed AGENTS.md means the notebook's rules were not placed; point at them instead.
        if let app = try store.repo(projectId: t.projectId, role: .app)?.localPath,
           let text = try? String(contentsOfFile: (app as NSString).appendingPathComponent("AGENTS.md"), encoding: .utf8),
           !text.hasPrefix(Notebook.placedMarker) {
            out.append("- Also follow `\(Notebook.rulesPath)` in the notebook; the app's own AGENTS.md is loaded already.")
        }
        return out
    }

    /// The components to use, by name (decision CO5), so an agent reuses them instead of reading views to copy their
    /// values. Only for work that draws something; names only, capped, a few hundred tokens at most.
    static func componentLines(_ config: ProjectConfig?, _ t: Ticket, _ kind: AgentTaskKind?) -> [String] {
        guard let kind, kind != .vet, t.type != .question, t.type != .theme, let config else { return [] }
        // The design system's roles (decisions DS2, DS7): which control in which place, by code name.
        if let notebook = config.repo(.notebook)?.localPath, let system = try? ComponentSystem.load(notebook: notebook) {
            var out = ["\n## Components: roles (\(ComponentSystem.readmePath) in the notebook has the rules in full)"]
            out += system.briefLines(looks: t.type == .sketch)
            out.append(t.type == .sketch
                       ? "Draw the variants with these looks."
                       : "Style every control through its role (`.buttonRole(.inRow)`), and use the named values (`Space`, `Radius`, `Palette`, `Typography`); never a style, colour, font size or spacing number in a view. "
                         + "Pick the role by element, place and importance. If none fits, or the ticket asks for a look a role does not have, do not invent one: hatch ask, suggesting use the role (first), add a variant here, or change the role everywhere. hatch ready checks the lines you add.")
            if let c = config.components, let product = c.product { out.append("Import \(product) (\(c.path)).") }
            return out
        }
        guard let label = config.componentsLabel else { return [] }
        var out = ["\n## Components (\(label)" + (config.components?.product.map { ", import \($0)" } ?? "") + ")"]
        if let folder = config.componentsFolder, FileManager.default.fileExists(atPath: folder) {
            let catalog = ComponentsScanner.catalog(at: folder, isPackage: config.components.map { $0.product != nil } ?? true)
            out += catalog.isEmpty ? ["Empty so far."] : catalog.briefLines(values: t.type == .sketch)
        } else {
            out.append("Not made yet; the \"\(ComponentsSetup.startTitle)\" ticket makes it.")
        }
        out.append(t.type == .sketch
                   ? "Draw the variants with these colors and this type."
                   : "Use these names; never type a color, font size or spacing number into a view. If one is missing, add it to the components on this ticket. `hatch components --all` lists everything.")
        return out
    }

    private static func areaLines(_ config: ProjectConfig?, _ t: Ticket) -> [String] {
        guard let name = t.area else { return [] }
        guard let a = config?.areas.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return ["\n## Area\n\(name)"] }
        var out = ["\n## Area\n\(a.name)" + (a.specPrefix.map { " (Spec \($0)-*)" } ?? "")]
        out.append("Files: " + a.paths.joined(separator: ", "))
        if let plans = a.testPlans, !plans.isEmpty { out.append("Tests: " + plans.joined(separator: ", ")) }
        return out
    }

    /// The ticket's screenshots as files on this Mac, so an agent can open them (decisions E3, M3). Marks drawn on
    /// them point at what matters.
    static func screenshotLines(_ store: HatchStore, _ t: Ticket) throws -> [String] {
        let shots = try store.attachments(ticketId: t.id).filter { $0.kind == "screenshot" }
        guard !shots.isEmpty else { return [] }
        var out = ["\n## Screenshots (open them; red marks point at what matters)"]
        for a in shots.prefix(6) {
            let file = store.attachmentFile(a)?.path ?? a.path
            out.append("- \(file)" + (a.caption.map { " (\($0))" } ?? ""))
        }
        if shots.count > 6 { out.append("- and \(shots.count - 6) more (hatch show \(t.displayNumber))") }
        return out
    }

    private static func repoLines(_ store: HatchStore, _ t: Ticket) throws -> [String] {
        let repos = try store.repos(projectId: t.projectId)
        guard !repos.isEmpty else { return [] }
        let workspaces = try store.workspaces(ticketId: t.id)
        var out = ["\n## Repos"]
        for r in repos {
            var line = "- \(r.role.rawValue): \(r.remote) (base \(r.defaultBranch))"
            if let b = r.buildCommand { line += " · build: \(b)" }
            if !r.testPlans.isEmpty { line += " · tests: \(r.testPlans.joined(separator: ", "))" }
            if let w = workspaces.first(where: { $0.repoId == r.id }) { line += "\n    workspace: \(w.path) on branch \(w.branch)" }
            out.append(line)
        }
        return out
    }

    /// A Sweep's items: the candidates to start the survey from, then the items with where each stands (decision SW5).
    private static func sweepLines(_ store: HatchStore, _ t: Ticket, _ kind: AgentTaskKind?, _ config: ProjectConfig?) throws -> [String] {
        guard t.type == .sweep, let kind else { return [] }
        let items = try store.sweepItems(ticketId: t.id)
        var out: [String] = []
        if !items.isEmpty {
            out.append("\n## Sweep items")
            for i in items {
                var line = "- \(i.key) [\(i.state.displayName)] \(i.name) in \(i.file)"
                if let k = i.kind, !k.isEmpty { line += " · kind: \(k)" }
                if let n = i.note, !n.isEmpty { line += " · note: \(Text.oneLine(n, 120))" }
                out.append(line)
            }
        }
        if kind == .prepare || kind == .revise, let folder = config?.componentsFolder, FileManager.default.fileExists(atPath: folder) {
            let catalog = ComponentsScanner.catalog(at: folder, isPackage: config?.components.map { $0.product != nil } ?? true)
            let prefix = (config?.components?.path).map { $0.hasSuffix("/") ? $0 : $0 + "/" } ?? ""
            let words = IrisReading.ownerWords(title: t.originalTitle ?? t.title, body: t.originalBody ?? IrisReading.split(t.body).words)
            let found = SweepCandidates.scan(text: words + " " + t.title, views: catalog.views, pathPrefix: prefix)
            if !found.isEmpty {
                out.append("\n## Candidates (a name scan, not the answer: confirm, remove and add)")
                out += found.map { "- \($0.name) in \($0.file)" }
            }
        }
        return out
    }

    // MARK: Rules

    static func branchName(_ t: Ticket) -> String { "ticket/\(t.ghNumber ?? t.id)-\(HatchStore.slug(t.title).prefix(40))" }

    /// The rules for each task, copied from the design (decisions G, H, I, K and S). Short on purpose.
    public static func rules(kind: AgentTaskKind?, ticket t: Ticket, config: ProjectConfig?) -> [String] {
        let common = [
            "Hatch changes the status, never you. Do not edit labels, state or the database; use the commands under Next.",
            "If something blocks you and only the owner can answer, run `hatch ask` with one `--suggest` for each answer you see, your recommendation first (the owner accepts the first one with a click). Options belong in `--suggest`, not in the question text. Do not guess.",
        ]
        switch kind {
        case nil:
            return ["Nothing to do on this ticket right now."]
        case .vet:
            return ["Compare the ticket with the other tickets and the Spec. Iris does this through `hatch`; you only read the result.",
                    "The owner decides every suggestion (rewrite, type change, duplicate)."]
        case .prepare where ComponentsSetup.changedRole(inBody: t.body) != nil, .revise where ComponentsSetup.changedRole(inBody: t.body) != nil:
            // A design system change (CP3): looks as recipes, no Stage round, no code.
            return [
                "Offer 2 to 4 looks for the role as recipes, as the ticket says. Use only the settings and values it lists; Hatch checks every recipe and draws the looks in place for the owner.",
                "Read where the role is used (`hatch components check` lists the app's controls by role) so the looks suit those places. Do not change the app's code.",
                "Recommend ONE look, the one you would ship, and say why and what the others cost. Give each look one line of gain and one of cost.",
            ] + (kind == .revise ? ["Keep the earlier looks and add new ones; the owner's notes refer to them."] : []) + common
                + ["Hand it in with `hatch offer \(t.displayNumber) --components looks.json`. Never move the status yourself."]
        case .build where ComponentsSetup.changedRole(inBody: t.body) != nil:
            let role = ComponentsSetup.changedRole(inBody: t.body) ?? ""
            return [
                "Work only in your own worktree on branch `\(branchName(t))`. Push only that branch.",
                "The owner chose a new look for `\(role)`; Hatch has made it the role's look in the design system. Run `hatch components generate --out <your app workspace>/\(config?.components?.path ?? "<components folder>")` so the role code has it, and build.",
                "Then move the controls that should use the role: `hatch components check` lists those styled by hand. Replace their style modifiers with the role. Never write the look by hand.",
                "Declare the files with `hatch plan` before you edit. Run only the tests mapped to the areas you touch.",
                "When done run `hatch ready`. Hatch checks the roles in your diff.",
            ] + common
        case .prepare:
            switch t.type {
            case .sketch:
                return [
                    "Draw 2 to 4 HTML variants of the layout or flow. They are concepts, not Swift; do not write Swift.",
                    "Each variant is one self-contained HTML file with its own id and title. Write a manifest JSON: {\"summary\": \"...\", \"variants\": [{\"id\", \"title\", \"html\"}]}.",
                    "Say in the summary what differs between the variants and which one you would pick, with the reason.",
                ] + common + ["Hand it in with `hatch offer`. Never move the status yourself."]
            case .question:
                return [
                    "Answer in words. Look up the Spec and the earlier decisions first and name the Spec IDs the answer touches.",
                    "Give one recommendation and the reason. When the answer is a choice (how to build something, which approach), offer the options with `hatch options` (2 to 4, each with a short title, one line of what it gains and one of what it costs), recommend one and say why. The owner's choice becomes a recorded decision.",
                ] + common + ["Hand the answer in with `hatch offer`. Never move the status yourself."]
            default:
                let sweep = t.type == .sweep ? [
                    "This is a Sweep: one change to several similar things. First survey the code once and list every instance in the manifest `items`: {id, title, name, file, kind, note}. `name` is the type or view as the code spells it and `file` is its path relative to the app. Hatch checks both against the code, so list only what exists. Start from Candidates below (a name scan): confirm, remove and add.",
                    "Group the items into `kind`s of look-alikes. Draw Today and the proposals on the most typical kind, and say in the summary how each other kind will look. One unified design for all of them, not one per item.",
                ] : []
                return sweep + [
                    "Look up the area in the Spec and note the Spec IDs you change; put them in the manifest `specs` and in the summary.",
                    "The first specimen is Today (`isToday: true`), drawn from what the app really does now. Read the real view in the app workspace listed under Repos, not from memory.",
                    "Then 2 to 4 proposals as Swift specimens in `specimens/<ticket>/` of the notebook workspace (a separate specimens repo only if Repos lists one), same sample data in all, each with `designWidth` and `designHeight` (340 to 700 wide, up to about 620 tall), and one line each of what it gains (`gain`) and costs (`cost`). No title inside a specimen.",
                    "Cover the standard scenarios (Rest, Hover, Pressed, Focus, Disabled, Empty, Error, Long text, Many items, Loading), or mark one `applicable: false` with a `notApplicableReason`.",
                    "Every control with a `question`, every question and the specimen topic carries ONE recommendation and its reason: the option you would ship, not a safe middle. The reason says what the others cost.",
                    "Write a question as what to do, then what to decide. Choice names are short and stable.",
                    "Mark exactly one preset `isRecommended: true` so the owner can try your whole recommendation in one click.",
                ] + common + [
                    "Hand it in with `hatch offer`. Hatch runs the quality gate and builds the Stage; errors come back to you. Never move the status yourself.",
                ]
            }
        case .revise:
            return [
                "Keep every earlier option, control, question and choice. Only add. Never rename a choice the owner already answered.",
                "Mark everything new with `addedIn: \(t.revision + 1)` and set `revision` to \(t.revision + 1).",
                "Follow the send-back reason: needs more options = add options; change an option = edit that one; different direction = a new angle, still keeping the old options.",
                "A Maybe verdict means keep refining that option. A No means do not bring it back.",
            ] + common + ["Hand it in with `hatch offer`. Never move the status yourself."]
        case .build:
            let limit = config?.planApprovalFileThreshold ?? 8
            let sweep = t.type == .sweep ? [
                "This is a Sweep: work the items under Sweep items in order, in this one worktree and branch. Build the shared component from the owner's accepted choices first (it is the example the rest adopt); then each item adopts it, with no variations unless its note says so.",
                "One commit per item. After each commit run `hatch item built \(t.displayNumber) <key>`: Hatch records the commit and refuses one that already belongs to another item. `hatch ready` is refused while an item is still To do or Building.",
            ] : []
            return sweep + [
                "Work only in your own worktree on branch `\(branchName(t))`. Never touch the main checkout. Push only that branch.",
                "Declare the files you will touch with `hatch plan` before you edit. If another ticket holds them you are queued.",
                "A Bug, or a change over \(limit) files, waits for the owner to approve the plan; Hatch tells you.",
                t.type == .proposal ? "Build the owner's accepted choices exactly (see Owner's choices). Update the Spec text for the Spec IDs you change." : "Make the smallest change that fixes it, and update the Spec text if behaviour changes.",
                "Run only the tests mapped to this area, in your worktree. Do not run the full suite or a full build; CI does that.",
                "Compile with `hatch check \(t.displayNumber) --build`, and pipe a test run through `hatch check -` (`<test command> 2>&1 | hatch check -`): they print only errors, warnings and failing tests.",
                "When done run `hatch ready`. Hatch runs the build, tests and match check and moves the ticket to To verify.",
            ] + common
        case .fix:
            return [
                "Read the owner's notes under Since your last turn and fix exactly that, on the same branch `\(branchName(t))`.",
                "Run only the tests mapped to this area. No full suite.",
                "Compile with `hatch check \(t.displayNumber) --build`, and pipe a test run through `hatch check -`: only errors, warnings and failing tests.",
                "When done run `hatch ready`. Hatch moves the ticket back to To verify.",
            ] + common
        }
    }

    static func nextCommands(kind: AgentTaskKind?, ticket t: Ticket) -> [String] {
        let n = t.displayNumber
        switch kind {
        case nil, .vet?: return ["(nothing for you to run)"]
        case .prepare?, .revise?:
            let file: String
            switch t.type { case .sketch: file = "sketch.json"; case .question: file = "--answer \"...\""; default: file = ComponentsSetup.changedRole(inBody: t.body) != nil ? "--components looks.json" : "manifest.json" }
            return ["hatch offer \(n) \(file)     # when ready; Hatch checks it and moves the ticket",
                    "hatch ask \(n) \"...\" --suggest \"your recommendation\" --suggest \"another answer\"     # only if you are blocked",
                    "hatch note \(n) \"...\"    # context for the owner"]
        case .build?, .fix?:
            return (kind == .build ? ["hatch plan \(n) --files <paths>   # before you edit"] : [])
                + (t.type == .sweep ? ["hatch item list \(n)   # the items and where each stands", "hatch item built \(n) <key>   # after committing that item"] : [])
                + ["hatch check \(n) --build   # compile; only errors and warnings",
                   "hatch ready \(n)     # when the work is done",
                   "hatch ask \(n) \"...\" --suggest \"your recommendation\" --suggest \"another answer\"     # only if you are blocked",
                   "hatch note \(n) \"...\"    # progress for the owner"]
        }
    }
}
