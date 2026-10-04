import Foundation

/// The project notebook (design-review/project-knowledge-concepts.html): a repository of plain files that holds what is
/// decided and how the project works, so the project can be picked up later with any agent, with or without Hatch.
/// This file only makes the text; HatchGit writes it to disk and commits it.
public enum Notebook {
    /// Where the coding rules live in the notebook. Hatch copies them into each clone and worktree of the code.
    public static let rulesPath = "rules/AGENTS.md"
    public static let specDir = "spec"
    public static let decisionsDir = "decisions"
    public static let specimensDir = "specimens"
    public static let configPath = "project.json"

    /// First line of every file Hatch places in a clone, so it can tell its own copy from a file someone wrote there.
    public static let placedMarker = "<!-- Placed by Hatch from the project notebook (rules/AGENTS.md). Edit it there; this copy is replaced. -->"

    /// The suggested repository name for a project's notebook: the app repository's name plus `-notebook`.
    public static func suggestedName(appRepo: String) -> String {
        (appRepo.split(separator: "/").last.map(String.init) ?? "project").lowercased() + "-notebook"
    }

    /// The files a new notebook starts with, by path. `rules` is the project's existing agent file when there is one.
    public static func scaffold(config: ProjectConfig, notebookRepo: String, rules: String?) -> [String: String] {
        [
            "README.md": readme(config: config, notebookRepo: notebookRepo),
            "AGENTS.md": agents(config: config),
            "WORKFLOW.md": workflow(config: config),
            "NOW.md": now(projectName: config.name, open: [], decisions: []),
            rulesPath: rules ?? starterRules(config: config),
            "rules/areas/README.md": "# Area rules\n\nOne file per area, such as `connections.md`. An agent's brief names the file only when its ticket touches that area, so these can be detailed without costing every agent tokens.\n",
            "\(specDir)/README.md": "# Spec\n\nWhat \(config.name) does, by area: one Markdown file per area, each item with an ID such as `TOAST-3`. A ticket is not Done until the items it changes are updated here, on the same ticket branch as the code.\n",
            "\(decisionsDir)/README.md": "# Decisions\n\nOne file per decision, named `<ticket>-<slug>.md`, never edited after it is written. A later decision names the one it replaces. Kinds: design, architecture, workflow.\n",
            "\(specimensDir)/README.md": "# Specimens\n\nThe Swift code of each Proposal's options, one folder per ticket, plus `Today/` (\(config.name) as it is now). Rejected options stay, so what was tried is never lost.\n",
        ]
    }

    public static func readme(config: ProjectConfig, notebookRepo: String) -> String {
        var lines = ["# \(config.name) notebook", "",
                     "What is decided about \(config.name) and how work on it is done. Plain files, so any person or agent can pick the project up from here, with or without Hatch.", "",
                     "## Start here", "",
                     "1. Clone the repositories below next to this one.",
                     "2. Copy `\(rulesPath)` into the app's clone as `AGENTS.md` (and a `CLAUDE.md` containing `@AGENTS.md`). The app does not commit them. Hatch does this for you when it runs.",
                     "3. Read `NOW.md` for where things stand, then `WORKFLOW.md` for how work flows.", "",
                     "## Repositories", ""]
        lines.append("- Notebook: `\(notebookRepo)` (this repository)")
        for repo in config.repos where repo.role != .notebook {
            lines.append("- \(roleName(repo.role)): `\(repo.remote)`, base branch `\(repo.branch)`")
        }
        if config.repo(.tickets) == nil && !config.ticketsRepo.isEmpty { lines.append("- Tickets: `\(config.ticketsRepo)` (GitHub issues)") }
        lines += ["", "## What is where", "",
                  "- `NOW.md`: open tickets by whose turn it is, and recent decisions.",
                  "- `WORKFLOW.md`: the steps every change goes through.",
                  "- `\(rulesPath)`: how code is written in \(config.name). `rules/areas/` holds detail per area.",
                  "- `\(specDir)/`: what the app does, by area.",
                  "- `\(decisionsDir)/`: every decision with its options and reason.",
                  "- `\(specimensDir)/`: the code of each Proposal's options.",
                  "- `\(configPath)`: Hatch's settings for this project and the area index.", ""]
        return lines.joined(separator: "\n")
    }

    public static func agents(config: ProjectConfig) -> String {
        """
        # For agents working from this notebook

        This repository describes \(config.name); the code is in `\(config.repo(.app)?.remote ?? "the app repository")`.

        Read in this order: `NOW.md` (where things stand), `WORKFLOW.md` (how work flows), `\(rulesPath)` (how code is written), then the Spec and decisions for the area you work on.

        When Hatch is running, use the `hatch` command for every step (`hatch next`, `hatch take`, `hatch ready`); it does the bookkeeping. When it is not, follow `WORKFLOW.md` by hand and keep `NOW.md` and `\(decisionsDir)/` current yourself.

        """
    }

    /// The process Hatch enforces, in words, made from the same workflow rules the app runs.
    public static func workflow(config: ProjectConfig) -> String {
        let app = config.repo(.app)
        let base = app?.branch ?? "dev"
        var lines = ["# How work flows in \(config.name)", "",
                     "Every change is a ticket, a GitHub issue in `\(config.ticketsRepo)`. Its type, status and project are labels (`type:bug`, `status:building`, `project:…`).", "",
                     "## A change, step by step", "",
                     "1. Take the ticket. Work on a branch `ticket/<number>-<slug>` in each repository it touches, never on `\(base)`.",
                     "2. Plan first when it is a Bug or touches more than \(config.planApprovalFileThreshold) files; the owner approves the plan.",
                     "3. Build before review: \(app?.buildCommand.map { "`\($0)`" } ?? "the project's build") must pass. Only the tests of the area you changed belong here; CI runs the full suite.",
                     "4. Update the Spec (`\(specDir)/`) for what changed, on the notebook's ticket branch, or say it is unchanged.",
                     "5. The owner verifies it in a Preview. Approved work merges into `\(config.integrationBranch)`.",
                     "6. When CI passes on `\(config.integrationBranch)`, \(promotionSentence(config.promotionMode, base: base)).", "",
                     "## Statuses by ticket type", ""]
        for type in TicketType.allCases {
            lines.append("- \(type.displayName): " + Workflow.path(for: type).map(\.displayName).joined(separator: " → "))
        }
        lines += ["", "Any ticket can also be Blocked, Parked or Dropped.", "",
                  "## Decisions", "",
                  "When a Proposal, Sketch or Question is decided, its decision is written to `\(decisionsDir)/` with the options, the choice and why. Decisions are not edited later; a new decision names the one it replaces.", ""]
        return lines.joined(separator: "\n")
    }

    /// Where things stand: open tickets grouped by whose turn it is, and the latest decisions.
    public static func now(projectName: String, open: [Ticket], decisions: [(number: String, title: String)]) -> String {
        var lines = ["# Now in \(projectName)", ""]
        let groups: [(String, Turn)] = [("Waiting for the owner", .you), ("Agents working", .agent), ("Queued or automatic", .hatch), ("Paused", .paused)]
        if open.isEmpty { lines.append("Nothing in flight.") }
        for (title, turn) in groups {
            let tickets = open.filter { $0.turn == turn }
            guard !tickets.isEmpty else { continue }
            lines.append("## \(title)")
            lines.append("")
            for t in tickets { lines.append("- \(t.displayNumber) \(t.type.displayName): \(t.title) (\(t.status.displayName))") }
            lines.append("")
        }
        if !decisions.isEmpty {
            lines += ["## Recent decisions", ""]
            for d in decisions { lines.append("- \(d.number) \(d.title)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Decision files

    /// `decisions/0151-toast-spacing.md`. Unique among `taken`: a second decision on a ticket gets `-2`.
    public static func decisionPath(_ d: DecisionRecord, taken: Set<String>) -> String {
        let number = d.ticketNumber.hasPrefix("#") ? String(repeating: "0", count: max(0, 4 - (d.ticketNumber.count - 1))) + d.ticketNumber.dropFirst()
                                                  : d.ticketNumber
        let slug = HatchStore.slug(d.title.isEmpty ? d.summary : d.title).prefix(48)
        var path = "\(decisionsDir)/\(number)-\(slug).md", n = 2
        while taken.contains(path) { path = "\(decisionsDir)/\(number)-\(slug)-\(n).md"; n += 1 }
        return path
    }

    /// A decision in the common ADR shape, with the facts a later reader or importer needs at the top.
    public static func decisionFile(_ d: DecisionRecord, replacesPath: String?) -> String {
        var front = ["---", "ticket: \(d.ticketNumber)", "type: \(d.ticketType.rawValue)", "kind: \(d.kind.rawValue)"]
        if let area = d.area { front.append("area: \(area)") }
        if !d.specCodes.isEmpty { front.append("spec: [\(d.specCodes.joined(separator: ", "))]") }
        front.append("decided: \(dayFormatter.string(from: d.at))")
        if let replacesPath { front.append("replaces: \(replacesPath)") }
        front.append("---")
        var lines = front + ["", "# \(d.title.isEmpty ? d.summary : d.title)", "", "**Decision:** \(d.summary)"]
        if let why = d.reason, !why.isEmpty { lines += ["", "**Why:** \(why)"] }
        if !d.options.isEmpty {
            lines += ["", "## Options", ""]
            for o in d.options {
                var line = "- \(o.key): \(o.title)"
                if let detail = o.detail, !detail.isEmpty { line += ". \(detail)" }
                var marks: [String] = []
                if o.key == d.recommended { marks.append("recommended") }
                if let c = d.choice, c == o.key || c.contains("\(o.key) = ") { marks.append("chosen") }
                if !marks.isEmpty { line += " (\(marks.joined(separator: ", ")))" }
                lines.append(line)
            }
        }
        lines += ["", "Ticket \(d.ticketNumber) holds the discussion.", ""]
        return lines.joined(separator: "\n")
    }

    /// What an import needs from a decision file. Nil when the file is not a decision.
    public struct ParsedDecision: Equatable, Sendable {
        public var ticketNumber: Int
        public var kind: DecisionKind
        public var area: String?
        public var specCodes: [String]
        public var decided: Date?
        public var title: String
        public var summary: String
        public var reason: String?
    }

    public static func parseDecision(_ text: String) -> ParsedDecision? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            fields[String(line[..<colon]).trimmingCharacters(in: .whitespaces)] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard let number = fields["ticket"].flatMap({ Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "#"))) }) else { return nil }
        let body = lines[(end + 1)...]
        let title = body.first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) } ?? ""
        func after(_ prefix: String) -> String? { body.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) } }
        let spec = fields["spec"].map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } ?? []
        return ParsedDecision(ticketNumber: number, kind: fields["kind"].flatMap(DecisionKind.init(rawValue:)) ?? .design, area: fields["area"],
                              specCodes: spec, decided: fields["decided"].flatMap { dayFormatter.date(from: $0) }, title: title,
                              summary: after("**Decision:**") ?? title, reason: after("**Why:**"))
    }

    /// `decisions/README.md`: every decision by kind, newest first, so a reader finds one without opening them all.
    public static func decisionIndex(_ decisions: [DecisionRecord]) -> String {
        var lines = ["# Decisions", "", "One file per decision, never edited after it is written. A later decision names the one it replaces.", ""]
        for kind in DecisionKind.allCases {
            let list = decisions.filter { $0.kind == kind && $0.filePath != nil }
            guard !list.isEmpty else { continue }
            lines += ["## \(kind.displayName)", ""]
            for d in list {
                let file = (d.filePath! as NSString).lastPathComponent
                lines.append("- [\(d.ticketNumber) \(d.title.isEmpty ? d.summary : d.title)](\(file))" + (d.area.map { " · \($0)" } ?? ""))
            }
            lines.append("")
        }
        if decisions.isEmpty { lines.append("None yet.") }
        return lines.joined(separator: "\n")
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func starterRules(config: ProjectConfig) -> String {
        """
        # How code is written in \(config.name)

        Keep this file short: every agent reads all of it. Put detail for one area in `rules/areas/<area>.md`.

        """
    }

    static func promotionSentence(_ p: Promotion, base: String) -> String {
        switch p {
        case .pullRequest: "Hatch opens a pull request into `\(base)` and the owner merges it"
        case .automatic: "Hatch merges it into `\(base)`"
        case .manual: "the owner merges it into `\(base)` when they choose"
        }
    }

    static func roleName(_ role: RepoRole) -> String {
        switch role {
        case .app: "App"
        case .designSystem: "Components"
        case .specimens: "Specimens"
        case .tickets: "Tickets"
        case .notebook: "Notebook"
        }
    }
}
