import SwiftUI
import AppKit
import HatchCore
import HatchAgent

/// `Hatch --snapshots <folder>` opens the window on made-up data, saves a PNG of each main screen in light and dark, and quits.
/// CI uses it so the screens can be looked at without a person running the app. It never touches the real database.
enum Snapshots {
    static var demoMode: Bool {
        CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--snapshots")
    }
    /// Settings › GitHub shows a made-up connected account in demo mode; `settings-github-disconnected` shows it signed out.
    @MainActor static var githubDisconnected = false
    private static let pendingQueryKey = "hatch.pendingTicketQuery"
    private static var priorPendingQuery: String??

    @MainActor private static func isolateDemoPreferences() {
        guard priorPendingQuery == nil else { return }
        priorPendingQuery = UserDefaults.standard.string(forKey: pendingQueryKey)
        UserDefaults.standard.set("", forKey: pendingQueryKey)
    }

    @MainActor static func restoreDemoPreferences() {
        guard let priorPendingQuery else { return }
        if let value = priorPendingQuery { UserDefaults.standard.set(value, forKey: pendingQueryKey) }
        else { UserDefaults.standard.removeObject(forKey: pendingQueryKey) }
        self.priorPendingQuery = nil
    }

    @MainActor private static func save(_ window: NSWindow, name: String, mode: String, into folder: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: folder.appendingPathComponent("\(name)-\(mode).png"))
        }
    }

    static var folder: URL? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--snapshots"), i + 1 < a.count else { return nil }
        return URL(fileURLWithPath: a[i + 1], isDirectory: true)
    }

    @MainActor static func demoState() -> AppState {
        isolateDemoPreferences()
        let store = try! HatchStore.inMemory()
        var config = ProjectConfig(name: "Acme", ticketsRepo: "acme/hatch-tickets", repos: [
            RepoConfig(role: .app, remote: "acme/app", branch: "main", localPath: "/tmp/hatch-demo/app",
                       buildCommand: "xcodebuild -scheme Acme build", testPlans: ["UnitTests"], testCommand: "swift test --filter AcmeTests"),
            RepoConfig(role: .tickets, remote: "acme/hatch-tickets", branch: "main"),
            RepoConfig(role: .notebook, remote: "acme/app-notebook", branch: "main", localPath: "/tmp/hatch-demo/app-notebook"),
            RepoConfig(role: .specimens, remote: "acme/specimens", branch: "main", localPath: "/tmp/hatch-demo/Specimens"),
        ], areas: [
            AreaConfig(name: "Connections", paths: ["Sources/Connections/**"], specPrefix: "CONN", testPlans: ["UnitTests"]),
            AreaConfig(name: "Editor", paths: ["Sources/Editor/**"], specPrefix: "EDIT"),
            AreaConfig(name: "Notifications", paths: ["Sources/Notifications/**"], specPrefix: "NOTIF"),
        ], docs: ["README.md", "Design/CONTRIBUTING.md"], maxAgents: 3, integrationBranch: "hatch")
        config.promotion = .pullRequest
        config.components = ComponentsConfig(path: "Packages/AcmeComponents", product: "AcmeComponents")
        let p = try! store.upsertProject(key: "acme", name: "Acme", config: config)
        // Agents settings with a model list, as after the first fetch, so Settings › Agents shows its real rows.
        var agents = AgentSettings.initial(detect: false)
        agents.providers[0].models = ModelCatalog.claudeAliases + [
            ModelInfo(id: "claude-opus-5-5", name: "Opus 5.5"), ModelInfo(id: "claude-sonnet-5-5", name: "Sonnet 5.5"),
            ModelInfo(id: "claude-haiku-4-5", name: "Haiku 4.5"), ModelInfo(id: "claude-sonnet-5", name: "Sonnet 5", featured: false)]
        agents.upgradeModels()
        agents.providers[0].modelsFetchedAt = Date()
        try? agents.save(to: store)
        try! store.setSetting(hxDefaultTicketsSetting, "acme/hatch-tickets")
        let rows: [(TicketType, Status, String, String)] = [
            (.proposal, .yourCall, "Toast spacing and corner radius", "Notifications"),
            (.proposal, .preparing, "Query tab empty state", "Editor"),
            (.sketch, .yourCall, "Sidebar density options", "Connections"),
            (.bug, .toVerify, "Results grid loses scroll position after sort", "Editor"),
            (.bug, .building, "Connection test hangs on bad host", "Connections"),
            (.tweak, .ready, "Rename Run to Execute in the toolbar", "Editor"),
            (.question, .needsAnswers, "Should tabs restore after a crash?", "Editor"),
            (.theme, .building, "Polish the Connections area", "Connections"),
            (.tweak, .merged, "Align icon sizes in the inspector", "Connections"),
            (.bug, .blocked, "Export to CSV drops the last row", "Editor"),
            (.proposal, .accepted, "Command palette layout", "Connections"),
            (.question, .draft, "Do we need a dark-only mode?", "Editor"),
            (.tweak, .toVerify, "Keep focus in the query after Run", "Editor"),
            (.bug, .done, "Crash when importing an empty file", "Connections"),
            (.proposal, .revising, "Connection timeout message", "Connections"),
            (.tweak, .parked, "Use compact labels in the inspector", "Connections"),
            (.bug, .dropped, "Restore the retired XML importer", "Editor"),
            (.sketch, .draft, "New empty results illustration", "Editor"),
            (.theme, .ready, "Keyboard navigation across result groups", "Editor"),
            (.bug, .fixing, "Reconnect action keeps a stale error", "Connections"),
            (.question, .done, "Can imported tabs preserve order?", "Editor"),
        ]
        var tickets: [Ticket] = []
        for (i, r) in rows.enumerated() {
            let body = """
            What: \(r.2.lowercased()).
            Why: A realistic example ticket with enough detail to review the reading flow.
            Scope: \(r.3), including keyboard use, reduced motion, and failure states.
            Done when: the change is clear, covered by tests, and preserves existing behavior.
            """
            tickets.append(try! store.createTicket(projectId: p.id, type: r.0, title: r.2, body: body,
                                                   area: r.3, ghNumber: 140 + i, status: r.1))
        }
        let proposal = tickets[0], verifyA = tickets[3], building = tickets[4]
        let sketch = tickets[2], verifyB = tickets[12], question = tickets[6]
        try! store.recordSuggestion(ticketId: verifyA.id, VettingSuggestion(
            rewrite: .init(title: "Keep query focus after Run", body: "After a query runs, keep keyboard focus in the query editor so the next query can be changed without reaching for the mouse.", changes: ["Names the moment focus moves", "States the expected focus target"]),
            typeSuggestion: .init(type: .tweak, reason: "This asks for a small behavior refinement rather than a failure repair."),
            related: [verifyB.id], specTouches: ["EDIT-2.1"]))
        try! store.saveProposal(ticketId: proposal.id, manifestJSON: #"{"revision":1,"specs":["NOTIF-1.2"],"summary":"Reduce toast padding while keeping the action easy to find.","asked":"Make notifications calmer without hiding their action.","controls":[{"id":"density","title":"Spacing","choices":[{"id":"compact","name":"Compact"},{"id":"balanced","name":"Balanced"}],"defaultChoice":"balanced","question":"Which spacing feels easier to scan?","recommend":"balanced","why":"It keeps the action clear without making the toast taller."}],"specimens":[{"id":"today","title":"Today","isEchoToday":true,"designWidth":360,"designHeight":480},{"id":"compact","title":"Compact","designWidth":360,"designHeight":480},{"id":"balanced","title":"Balanced","designWidth":360,"designHeight":480}],"scenarios":[{"id":"light","title":"Light"},{"id":"dark","title":"Dark"}]}"#)
        try! store.setPick(ticketId: proposal.id, topic: "density", choice: "balanced", note: "The action stays easy to spot.")
        try! store.setVerdict(ticketId: proposal.id, topic: "density", option: "compact", verdict: "maybe")
        _ = try! store.addPin(ticketId: proposal.id, option: "balanced", x: 0.72, y: 0.31, scenario: "Dark", appearance: "dark", corners: 14, zoom: 1, text: "Keep the close button aligned with the message.")
        _ = try! store.recordRevision(ticketId: proposal.id, summary: "Raised contrast and aligned the action.", added: ["Dark-mode example"])
        try! store.saveProposal(ticketId: sketch.id, manifestJSON: #"{"variants":[{"id":"compact","title":"Compact","summary":"More rows stay visible.","html":"<html><body style='font:16px -apple-system;background:#f5f5f7;padding:28px'><h2>Connections</h2><div style='padding:16px;background:white;border-radius:12px;margin:8px 0'>Database · Connected</div><div style='padding:16px;background:white;border-radius:12px;margin:8px 0'>Analytics · Needs attention</div><div style='padding:16px;background:white;border-radius:12px;margin:8px 0'>Cache · Connected</div></body></html>"},{"id":"roomy","title":"Roomy","summary":"Each connection gets more breathing room.","html":"<html><body style='font:16px -apple-system;background:#f5f5f7;padding:28px'><h2>Connections</h2><div style='padding:24px;background:white;border-radius:16px;margin:12px 0'>Database<br><small>Connected</small></div><div style='padding:24px;background:white;border-radius:16px;margin:12px 0'>Analytics<br><small>Needs attention</small></div></body></html>"}]}"#)
        try! store.addNote(proposal.id, kind: .note, author: "owner", body: "The quieter spacing is close. Keep the close action aligned.")
        try! store.addNote(proposal.id, kind: .agent, author: "Mina", body: "Revision 2 keeps the label to two lines and brings the action back to the baseline.")
        _ = try! store.ask(question.id, text: "Should restored tabs keep their previous split position?", suggestions: ["Yes, when both tabs still exist", "No, use the default split"], by: "Iris")
        try! store.upsertSpecItems(projectId: p.id, items: [
            ("NOTIF-1.2", "Notifications", "Toast actions remain visible at compact and regular text sizes.", "notifications.md"),
            ("NOTIF-1.3", "Notifications", "A toast does not cover the primary window action.", "notifications.md"),
            ("EDIT-2.1", "Editor", "A restored tab retains its selected query and cursor position.", "editor.md"),
            ("EDIT-2.2", "Editor", "The empty state names one useful next action.", "editor.md"),
            ("CONN-3.1", "Connections", "A failed connection test names the host and offers Retry.", "connections.md"),
            ("CONN-3.2", "Connections", "Secrets are never included in logs or support bundles.", "connections.md"),
        ])
        _ = try! store.recordDecision(ticketId: proposal.id, summary: "Use balanced toast spacing: it keeps the action easy to scan while avoiding extra height.", specCodes: ["NOTIF-1.2", "NOTIF-1.3"])
        try! store.setPick(ticketId: proposal.id, topic: "density", choice: "balanced")

        let appRepo = try! store.repo(projectId: p.id, role: .app)!
        _ = try! store.saveWorkspace(ticketId: verifyA.id, repoId: appRepo.id, path: "/tmp/hatch-demo/worktrees/140", branch: "ticket/140-results-scroll", baseSha: "a1b2c3d")
        _ = try! store.saveWorkspace(ticketId: verifyB.id, repoId: appRepo.id, path: "/tmp/hatch-demo/worktrees/152", branch: "ticket/152-query-focus", baseSha: "a1b2c3d")
        let preview = try! store.createPreview(name: "Preview 01", branch: "preview/01", ticketIds: [verifyA.id, verifyB.id])
        try! store.setPreview(preview.id, state: "built", log: "Build succeeded. 312 tests passed.", built: true)
        try! store.setVerdict(previewId: preview.id, ticketId: verifyA.id, verdict: "looks-right", note: "The result stays in view after sorting.")
        try! store.setVerdict(previewId: preview.id, ticketId: verifyB.id, verdict: "needs-work", note: "Focus still moves to the toolbar after Run.")

        try! store.setTakenBy(building.id, "Mina")
        _ = try! store.startRun(ticketId: building.id, agent: "Mina", step: "Running connection tests")
        _ = try! store.claim(ticketId: building.id, repoId: appRepo.id, paths: ["Sources/Connections/ConnectionTest.swift"])
        _ = try! store.take(tickets[5].id, agent: "Jon")
        let completedRun = try! store.startRun(ticketId: tickets[8].id, agent: "Jon", step: "Preview passed")
        try! store.endRun(completedRun, tokensIn: 18400, tokensOut: 2300, outcome: "ok")
        // Two weeks of runs for Usage and Reports: Claude Code builds and prepares, Codex sometimes, Iris every day.
        let kinds: [(provider: String, model: String, role: String, tokens: Int)] = [
            ("Claude Code", "claude-sonnet-5-5", "build", 180_000), ("Claude Code", "claude-opus-5-5", "prepare", 90_000),
            ("Claude Code", "claude-haiku-4-5", "iris", 6_000), ("Claude Code", "claude-sonnet-5-5", "ask", 4_000),
            ("Codex", "gpt-5.5-codex", "fix", 60_000)]
        for day in 0..<14 {
            for (i, k) in kinds.enumerated() where (day + i) % 3 != 0 || k.role == "iris" {
                let start = Calendar.current.date(byAdding: .hour, value: -(day * 24 + i * 2 + 1), to: Date())!
                let tokens = k.tokens * (1 + (day * 7 + i * 3) % 5) / 3
                try! store.recordRun(ticketId: tickets[(day + i) % tickets.count].id, agent: k.role == "iris" ? "Iris" : "Agent", step: nil,
                                     provider: k.provider, model: k.model, role: k.role, tokensIn: tokens * 4 / 5, tokensOut: tokens / 5,
                                     cacheTokens: tokens * 3, outcome: k.role == "build" && day % 4 == 1 ? "stopped early (exit 1)" : "ok",
                                     startedAt: start, endedAt: start.addingTimeInterval(600))
            }
        }
        // Finished tickets, for Reports' tokens per finished ticket.
        for t in tickets.prefix(4) { try! store.record(t.id, actor: "hatch", kind: "status", payload: ["from": "toVerify", "to": "done"]) }
        try! store.logPull(summary: "17 issues updated", ok: true)
        try! store.logPull(summary: "Preview status unavailable", ok: false, error: "Checks are still running.")
        // Decide: a Question Hatch prepared about the components, and a plan over the limit (decisions CO11, DC8).
        let clash = try! store.createTicket(projectId: p.id, type: .question, title: "Two values for Color.accent", body: "", area: "Components", ghNumber: 170)
        try! store.setQuestionOptions(ticketId: clash.id, [
            QuestionOption(key: "A", title: "Keep AcmeComponents' values", detail: "The other values change to match", recommended: true,
                           why: "AcmeComponents is the set the project uses and Proposals import.", gain: "One value per name, matching the package", cost: "12 views change slightly"),
            QuestionOption(key: "B", title: "Keep the other set's values", detail: "AcmeComponents changes to match", gain: "Views that use the folder do not change", cost: "40 views change slightly"),
            QuestionOption(key: "C", title: "Keep both, rename the other set's", gain: "Nothing changes now", cost: "Two names that look alike")])
        try! store.requestPlanReview(ticketId: building.id, files: ["Sources/Connections/ConnectionTest.swift", "Sources/Connections/HostCheck.swift",
                                                                  "Sources/Editor/Toolbar.swift"], reason: "a Bug")
        try! store.setCIRecord(projectId: p.id, CIRecord(state: .failed, failed: ["Build & Test"], ref: "hatch", checkedAt: Date()))
        let paths = AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("hatch-snapshots-\(getpid())"))
        // Two screenshots on the first Proposal: one already in the tickets repo, one waiting for the next sync (M3).
        let shotDir = paths.root.appendingPathComponent("attachments/\(proposal.id)")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        let shot = sampleScreenshot()
        for (i, uploaded) in [true, false].enumerated() {
            try? shot.write(to: shotDir.appendingPathComponent("shot-\(i + 1).png"))
            let a = try! store.addAttachment(proposal.id, path: "attachments/\(proposal.id)/shot-\(i + 1).png", sha: "s\(i)", caption: "toast-\(i + 1).png")
            if uploaded { try! store.markAttachmentUploaded(a.id, remotePath: "attachments/140/shot-1.png", sha: "s\(i)") }
        }
        return AppState(store: store, paths: paths)
    }

    /// A made-up screenshot for the mark-up snapshot: a window with a toolbar and a few rows.
    @MainActor static func sampleScreenshot() -> Data {
        let view = VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Query 1").font(.headline); Spacer(); Text("Run").padding(.horizontal, 10).padding(.vertical, 4).background(.blue.opacity(0.2), in: Capsule()) }
            RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.15)).frame(height: 90).overlay(Text("SELECT * FROM servers").font(.body.monospaced()))
            ForEach(0..<4) { i in HStack { Text("row \(i + 1)"); Spacer(); Text("ok").foregroundStyle(.secondary) }.padding(.horizontal, 6) }
        }
        .padding(18).frame(width: 640, height: 400).background(.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage.flatMap(ScreenshotClipboard.pngData) ?? Data()
    }

    /// A snapshot run shares preferences with the real app, so its window must not save its frame: otherwise the app
    /// the owner runs next opens where the snapshot window was. Saved window state is ignored in `HatchApp.init`.
    @MainActor private static func keepWindowStateOut() {
        for w in NSApp.windows { w.setFrameAutosaveName("") }
    }

    /// `--only <name>`: draw one screen in light and dark and quit, for a quick look at a single page.
    static var only: String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--only"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    @MainActor static func run(state: AppState, into folder: URL) async {
        keepWindowStateOut()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let only {
            await runOne(only, state: state, into: folder)
            NSApp.terminate(nil)
            return
        }
        let first = (try? state.store.tickets(TicketFilter()))?.first(where: { $0.title == "Toast spacing and corner radius" })?.id
        var routes: [(String, Route, TicketTab?)] = [("desk", .desk, nil), ("tickets", .tickets, nil), ("board", .board, nil),
                                                      ("previews", .previews, nil), ("specs", .specs, nil), ("decisions", .decisions, nil), ("components", .components, nil),
                                                      ("agents", .agents, nil), ("tests", .tests, nil), ("health", .health, nil), ("log", .log, nil), ("project", .projects, nil),
                                                      ("new-ticket", .newTicket, nil)]
        if let first {
            routes.insert(("ticket-overview", .ticket(first), .overview), at: 3)
            routes.insert(("ticket-options", .ticket(first), .options), at: 4)
            routes.insert(("ticket-thread", .ticket(first), .thread), at: 5)
            routes.insert(("ticket-work", .ticket(first), .work), at: 6)
            routes.insert(("ticket-history", .ticket(first), .history), at: 7)
        }
        let sketchID = (try? state.store.tickets(TicketFilter()))?.first(where: { $0.title == "Sidebar density options" })?.id
        let questionID = (try? state.store.tickets(TicketFilter()))?.first(where: { $0.title == "Should tabs restore after a crash?" })?.id
        if let sketchID { routes.append(("sketch-options", .ticket(sketchID), .options)) }
        if let questionID { routes.append(("question-overview", .ticket(questionID), .overview)) }
        if let ticket = (try? state.store.tickets(TicketFilter()))?.first(where: { $0.title == "Connection test hangs on bad host" }) {
            routes.append(("building-work", .ticket(ticket.id), .work))
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        keepWindowStateOut()
        if let w = NSApp.windows.first(where: { $0.isVisible }) { w.setContentSize(NSSize(width: 1360, height: 860)); w.center() }
        try? await Task.sleep(nanoseconds: 800_000_000)
        let irisTicket = (try? state.store.tickets(TicketFilter()))?.first(where: { $0.title == "Results grid loses scroll position after sort" })
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for (name, route, tab) in routes {
                state.snapshotTicketTab = tab
                state.showAskPanel = false
                state.showPalette = false
                state.route = route
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let window = NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: folder.appendingPathComponent("\(name)-\(mode).png"))
                }
            }
            state.snapshotTicketTab = .overview
            state.route = first.map(Route.ticket) ?? .desk
            state.selectedTicketId = first
            state.snapshotPresentation = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
            state.showAskPanel = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if let window = NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView?.superview ?? window.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: folder.appendingPathComponent("ask-panel-\(mode).png")) }
            }
            state.showAskPanel = false
            state.route = .tickets
            state.showPalette = false
            state.snapshotPresentation = .palette
            try? await Task.sleep(nanoseconds: 700_000_000)
            if let window = NSApp.windows.first(where: { $0.isVisible }) {
                save(window, name: "command-palette", mode: mode, into: folder)
            }
            state.snapshotPresentation = .settings
            try? await Task.sleep(nanoseconds: 800_000_000)
            if let window = NSApp.windows.first(where: { $0.isVisible }) {
                save(window, name: "settings", mode: mode, into: folder)
            }
            state.settingsPage = .agents
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if let window = NSApp.windows.first(where: { $0.isVisible }) {
                save(window, name: "settings-agents", mode: mode, into: folder)
            }
            state.settingsPage = .general
            state.snapshotPresentation = nil
            try? await Task.sleep(nanoseconds: 250_000_000)

            if let irisTicket {
                state.selectedTicketId = irisTicket.id
                state.route = .ticket(irisTicket.id)
                state.snapshotPresentation = nil
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let window = NSApp.windows.first(where: { $0.isVisible }) {
                    save(window, name: "iris-review", mode: mode, into: folder)
                }
            }

            state.snapshotPresentation = .addProject
            for step in ProjectSetupModel.Step.allCases {
                state.snapshotSetupStep = step.rawValue
                try? await Task.sleep(nanoseconds: 700_000_000)
                if let window = NSApp.windows.first(where: { $0.isVisible }) {
                    save(window, name: "add-project-\(step.rawValue + 1)-\(step.title.lowercased().replacingOccurrences(of: " ", with: "-"))", mode: mode, into: folder)
                }
            }

            state.snapshotPresentation = .repositorySelector
            try? await Task.sleep(nanoseconds: 700_000_000)
            if let window = NSApp.windows.first(where: { $0.isVisible }) {
                save(window, name: "repository-selector", mode: mode, into: folder)
            }
            state.snapshotPresentation = nil
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        restoreDemoPreferences()
        NSApp.terminate(nil)
    }

    /// One screen in both appearances. Names match the full run's files: a route (desk, health, project…), "settings"
    /// or "settings-agents".
    @MainActor private static func runOne(_ name: String, state: AppState, into folder: URL) async {
        let routes: [String: Route] = ["desk": .desk, "tickets": .tickets, "board": .board, "previews": .previews, "specs": .specs,
                                       "decisions": .decisions, "components": .components, "agents": .agents, "tests": .tests, "reports": .reports, "health": .health, "log": .log, "project": .projects,
                                       "new-ticket": .newTicket]
        if let w = NSApp.windows.first(where: { $0.isVisible }) { w.setContentSize(NSSize(width: 1360, height: 860)); w.center() }
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            if let route = routes[name] {
                state.route = route
            } else if name.hasPrefix("ticket-"), let tab = TicketTab.allCases.first(where: { "ticket-\($0)" == name }),
                      let first = (try? state.store.tickets(TicketFilter()))?.first(where: { $0.title == "Toast spacing and corner radius" }) {
                // ticket-overview, ticket-thread…: the first Proposal on that tab, as in the full run.
                state.route = .ticket(first.id)
                state.snapshotTicketTab = tab
            } else if name == "markup" {
                state.snapshotPresentation = .markup
                // The saved image too, to check that the marks land in the file at full size.
                let marks = [ShotMark(kind: .box, from: CGPoint(x: 0.08, y: 0.30), to: CGPoint(x: 0.55, y: 0.52)),
                             ShotMark(kind: .note("Focus jumps here"), from: CGPoint(x: 0.78, y: 0.86), to: CGPoint(x: 0.78, y: 0.86))]
                if let png = ScreenshotMarkupSheet.flatten(sampleScreenshot(), marks: marks) {
                    try? png.write(to: folder.appendingPathComponent("markup-export.png"))
                }
            } else if name == "decide" || name == "decide-components" {
                state.decideSession = AppState.DecideRequest(area: name == "decide" ? nil : "Components")
            } else if name.hasPrefix("add-project-"), let n = Int(name.dropFirst("add-project-".count)) {
                state.snapshotSetupStep = n - 1
                state.snapshotPresentation = .addProject
            } else if name == "agent-card" {
                state.snapshotPresentation = .agentCard
            } else if name == "menu-bar" {                // The menu bar item's panel with two sample agents and the demo's waiting tickets.
                state.agentRuns = [sampleRun, sampleRun2]
                state.updateWaitingCount()
                state.snapshotPresentation = .menuBar
            } else if name.hasPrefix("settings") {
                state.snapshotPresentation = .settings
                // settings-<page>, by the page's title: settings-github, settings-general, settings-storage…
                var page = String(name.dropFirst("settings-".count))
                githubDisconnected = page == "github-disconnected"
                if githubDisconnected { page = "github" }
                state.settingsPage = SettingsPage.allCases.first { $0.title.lowercased() == page } ?? .general
            } else if name.hasPrefix("add-project-"), let n = Int(name.dropFirst("add-project-".count).prefix { $0.isNumber }) {
                // add-project-5: one step of the setup assistant, numbered as in the full run.
                state.snapshotPresentation = .addProject
                state.snapshotSetupStep = n - 1
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            if let window = NSApp.windows.first(where: { $0.isVisible }) { save(window, name: name, mode: mode, into: folder) }
        }
    }

    /// A running agent for the agent-card snapshot.
    static var sampleRun: AgentRunInfo {
        AgentRunInfo(ticketId: 1, ticketNumber: "#151", ticketTitle: "Toast spacing and corner radius", runId: 1, agent: "Agent on #151",
                     role: .build, providerName: "Claude Code", model: "Sonnet 5.5", repo: "tashda/echo", branch: "ticket/151-toast-spacing",
                     workspace: "/tmp", startedAt: Date().addingTimeInterval(-754), attempt: 1, step: "Editing ToastView.swift",
                     tokensIn: 184_200, tokensOut: 12_900, logPath: "/tmp/none")
    }

    /// A second running agent for the menu-bar snapshot.
    static var sampleRun2: AgentRunInfo {
        AgentRunInfo(ticketId: 5, ticketNumber: "#144", ticketTitle: "Connection test hangs on bad host", runId: 2, agent: "Agent on #144",
                     role: .build, providerName: "Claude Code", model: "Sonnet 5.5", repo: "acme/app", branch: "ticket/144-connection-test",
                     workspace: "/tmp", startedAt: Date().addingTimeInterval(-2_312), attempt: 1, step: "Running connection tests",
                     tokensIn: 96_400, tokensOut: 8_100, logPath: "/tmp/none")
    }
}
