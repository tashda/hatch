import SwiftUI
import AppKit
import Combine
import HatchCore
import HatchAgent

// The menu bar item as a real menu (menu bar review, style A, 2026-10-05): what waits for you and the way into Decide,
// agents only while they work, a problem only when there is one, then the actions and Quit. No item ends in an
// ellipsis (owner's call). A few parts still have looks to choose from in the Menu Bar Lab (Go › Menu Bar Lab);
// `MenuBarLook` keeps the choice. `MenuBarPanel` stays selectable there until the menu replaces it.

extension AppState {
    /// Settings › General › Menu bar counts: every project (the default), or only the one picked in the main window.
    var menuBarCountsSelectedOnly: Bool { hxSetting(Preference.menuBarScope) == "selected" }

    /// The menu bar's own count, so it can cover all projects while the Dock badge follows the main window.
    func refreshMenuBarCount() {
        let scope = menuBarCountsSelectedOnly ? projectFilterId : nil
        let n = store.pendingDecisionCount(projectId: scope) + store.toVerifyCount(projectId: scope)
        if n != menuBarDecisionCount { menuBarDecisionCount = n }
    }
}

// MARK: - What the menu shows

/// Everything the menu draws, read from the app or taken from a sample in the lab.
struct MenuBarSnapshot {
    struct Agent: Identifiable {
        var id: Int
        var number: String
        var title: String
        var task: String
        var step: String
        var symbol: String
        var startedAt: Date
    }

    struct Problem {
        var title: String
        var detail: String
    }

    var decisions: Int
    var agents: [Agent]
    var paused: Bool
    var problem: Problem?
}

extension MenuBarSnapshot {
    @MainActor init(_ state: AppState) {
        decisions = state.menuBarDecisionCount
        paused = state.agentsPaused
        var runs = state.agentRuns
        if state.menuBarCountsSelectedOnly, let projectId = state.projectFilterId {
            runs = runs.filter { (try? state.store.ticket(id: $0.ticketId))?.projectId == projectId }
        }
        agents = runs.map {
            Agent(id: $0.ticketId, number: $0.ticketNumber, title: $0.ticketTitle, task: $0.role.taskTitle, step: $0.step,
                  symbol: $0.role.symbol, startedAt: $0.startedAt)
        }
        // The same cases the footer turns red for (`saveLevel == .problem`), named for what failed.
        let sync = state.syncSummary
        if let notebook = state.notebookProblem {
            problem = Problem(title: "Notebook Not Saved", detail: notebook)
        } else if sync.failed > 0 {
            problem = Problem(title: "GitHub Sync Failed", detail: sync.message ?? Format.count(sync.failed, "change") + " did not sync")
        } else if let message = sync.message, !message.isEmpty {
            problem = Problem(title: "Sync Failed", detail: message)
        } else {
            problem = nil
        }
    }

    /// Hard and ordinary cases for the lab, so every state can be judged without waiting for it to happen.
    static func sample(_ content: MenuBarLabContent) -> MenuBarSnapshot? {
        let now = Date()
        let build = Agent(id: -21, number: "#21", title: "Stop the late \"Filed by Iris\" line from making the view jump", task: "Build",
                          step: "Running swift test", symbol: "hammer", startedAt: now.addingTimeInterval(-252))
        let review = Agent(id: -18, number: "#18", title: "Give Quick Capture a better default shortcut", task: "Review",
                           step: "Reading the diff", symbol: "eye", startedAt: now.addingTimeInterval(-63))
        switch content {
        case .live:
            return nil
        case .busy:
            return MenuBarSnapshot(decisions: 13, agents: [build, review], paused: false, problem: nil)
        case .quiet:
            return MenuBarSnapshot(decisions: 0, agents: [], paused: false, problem: nil)
        case .paused:
            return MenuBarSnapshot(decisions: 4, agents: [], paused: true, problem: nil)
        case .problem:
            return MenuBarSnapshot(decisions: 2, agents: [build], paused: false,
                                   problem: Problem(title: "GitHub Sync Failed", detail: "The token was refused (401). 3 changes wait to sync."))
        }
    }
}

// MARK: - The menu

/// Hands the menu the app's `openWindow`, which only a view can read. Lives in the main window's background; until a
/// window has appeared the menu brings Hatch forward without it.
struct MenuBarInstaller: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { MenuBarMenu.shared.openWindow = openWindow }
    }
}

/// The menu bar item and its menu, in AppKit: SwiftUI menus show a symbol or a second line on an item but not both,
/// and the picked design has symbols, second lines, count badges and section headers. The menu is built each time it
/// opens, from the app or from the lab's sample, and its running times tick while it is open.
@MainActor
final class MenuBarMenu: NSObject, NSMenuDelegate {
    static let shared = MenuBarMenu()

    private weak var state: AppState?
    var openWindow: OpenWindowAction?
    private var item: NSStatusItem?
    private var watchers: Set<AnyCancellable> = []
    private var isOpen = false
    private var ticker: Timer?
    /// Agent items and when their agent started, so the ticker can update the time in place.
    private var timed: [(item: NSMenuItem, agent: MenuBarSnapshot.Agent)] = []

    private var look: MenuBarLook { .shared }

    /// Called once at launch, so the item is there even when no window opens.
    func start(state: AppState) {
        guard self.state == nil else { return }
        self.state = state
        let changes: [AnyPublisher<Void, Never>] = [
            state.$showMenuBarItem.map { _ in }.eraseToAnyPublisher(),
            state.$menuBarDecisionCount.map { _ in }.eraseToAnyPublisher(),
            state.$agentRuns.map { _ in }.eraseToAnyPublisher(),
            state.$agentsPaused.map { _ in }.eraseToAnyPublisher(),
            state.$syncSummary.map { _ in }.eraseToAnyPublisher(),
            look.objectWillChange.map { _ in }.eraseToAnyPublisher(),
        ]
        // @Published sends before the value is set, so the update runs on the next turn of the run loop.
        Publishers.MergeMany(changes).receive(on: RunLoop.main).sink { [weak self] in self?.update() }.store(in: &watchers)
        update()
    }

    /// Opens the same menu where the pointer is: the lab's preview.
    func popUpPreview() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        build(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: The item

    private func update() {
        guard let state else { return }
        let shown = state.showMenuBarItem && look.form == .menu
        if shown, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "app.hatch.menu"
            item.behavior = .removalAllowed
            // A new item can start hidden from an earlier removal; Settings › General is what decides, so it shows.
            item.isVisible = true
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            item.menu = menu
            // ⌘-dragging the item out of the menu bar switches the setting off, as for any menu bar extra.
            // Only the item that is showing counts: removing it here (setting off, or the lab picking the panel) clears
            // `self.item` first, so it never switches the setting off by itself.
            item.publisher(for: \.isVisible).dropFirst().sink { [weak self, weak item] visible in
                guard !visible, let self, let item, self.item === item, let state = self.state, state.showMenuBarItem else { return }
                state.setFlag(Preference.menuBar, false)
            }.store(in: &watchers)
            self.item = item
        } else if !shown, let old = item {
            item = nil
            NSStatusBar.system.removeStatusItem(old)
        }
        guard let item, let button = item.button else { return }
        let s = snapshot()
        button.image = MenuBarLabel.glyph(waiting: s.decisions > 0)
        button.setAccessibilityLabel(s.decisions > 0 ? "Hatch, \(s.decisions) decisions wait for you" : "Hatch")
        if isOpen, let menu = item.menu { build(menu) }
    }

    private func snapshot() -> MenuBarSnapshot {
        if let sample = MenuBarSnapshot.sample(look.content) { return sample }
        guard let state else { return MenuBarSnapshot(decisions: 0, agents: [], paused: false, problem: nil) }
        return MenuBarSnapshot(state)
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) { build(menu) }

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        let now = Date()
        for (item, agent) in timed { setTime(item, agent, now: now) }
    }

    // MARK: Building

    private func build(_ menu: NSMenu) {
        menu.removeAllItems()
        timed = []
        let s = snapshot()
        if let problem = s.problem {
            switch look.problem {
            case .twoItems:
                menu.addItem(entry(problem.title, "exclamationmark.triangle", subtitle: problem.detail, status: true) { [weak self] in self?.bringForward() })
                menu.addItem(entry("Retry", "arrow.clockwise") { [weak self] in self?.state?.syncNow() })
            case .oneItem:
                menu.addItem(entry(problem.title, "exclamationmark.triangle", subtitle: problem.detail + " Choose to retry.", status: true) { [weak self] in
                    self?.state?.syncNow()
                })
            }
            menu.addItem(.separator())
        }
        addDecide(s, to: menu)
        if !s.agents.isEmpty || s.paused {
            menu.addItem(.separator())
            addAgents(s, to: menu)
        }
        menu.addItem(.separator())
        let capture = entry("New Ticket", "square.and.pencil") { QuickCapture.shared.show() }
        setKey(ShortcutStore.shared.shortcut("capture.quick"), capture)
        menu.addItem(capture)
        if s.paused {
            menu.addItem(entry("Resume Agents", "play.circle") { [weak self] in self?.state?.setAgentsPaused(false) })
        } else if !s.agents.isEmpty {
            menu.addItem(entry("Pause Agents", "pause.circle") { [weak self] in self?.state?.setAgentsPaused(true) })
        }
        menu.addItem(.separator())
        menu.addItem(entry("Open Hatch", "macwindow") { [weak self] in self?.bringForward() })
        let settings = entry("Settings", "gearshape") { [weak self] in
            NSApp.activate()
            self?.openWindow?(id: "settings")
        }
        setKey(ShortcutStore.shared.shortcut("settings"), settings)
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = entry("Quit Hatch", "power") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
    }

    private func addDecide(_ s: MenuBarSnapshot, to menu: NSMenu) {
        let waiting = s.decisions > 0
        let decide: () -> Void = { [weak self] in
            self?.state?.openDecide()
            self?.bringForward()
        }
        switch look.decide {
        case .badge:
            let item = entry("Decide", "checklist", status: true, action: decide)
            if waiting { item.badge = NSMenuItemBadge(count: s.decisions) }
            item.isEnabled = waiting
            menu.addItem(item)
        case .sentence:
            let title = !waiting ? "Nothing Waits for You" : s.decisions == 1 ? "1 Decision Waits for You" : "\(s.decisions) Decisions Wait for You"
            let item = entry(title, "checklist", status: true, action: decide)
            item.isEnabled = waiting
            menu.addItem(item)
        case .header:
            menu.addItem(.sectionHeader(title: waiting ? "\(s.decisions) Waiting" : "Nothing Waits"))
            let item = entry("Decide", "checklist", status: true, action: decide)
            item.isEnabled = waiting
            menu.addItem(item)
        }
    }

    private func addAgents(_ s: MenuBarSnapshot, to menu: NSMenu) {
        if look.agents == .submenu, !s.agents.isEmpty {
            let parent = entry(s.agents.count == 1 ? "1 Agent Working" : "\(s.agents.count) Agents Working", "person.2", status: true) {}
            let sub = NSMenu()
            sub.autoenablesItems = false
            for agent in s.agents { sub.addItem(agentItem(agent, oneLine: false)) }
            parent.submenu = sub
            menu.addItem(parent)
            return
        }
        menu.addItem(.sectionHeader(title: "Agents"))
        if s.paused {
            let paused = entry("Paused", "pause.circle", subtitle: "Agents wait until you resume them", status: true) {}
            paused.isEnabled = false
            menu.addItem(paused)
        }
        for agent in s.agents { menu.addItem(agentItem(agent, oneLine: look.agents == .oneLine)) }
    }

    private func agentItem(_ agent: MenuBarSnapshot.Agent, oneLine: Bool) -> NSMenuItem {
        let title = oneLine ? "\(agent.number)  \(agent.task) · \(agent.step)" : "\(agent.number)  \(agent.title)"
        let item = entry(title, agent.symbol, status: true) { [weak self] in self?.open(ticketId: agent.id) }
        if oneLine { item.toolTip = agent.title }
        setTime(item, agent, now: Date())
        timed.append((item, agent))
        return item
    }

    /// The running time: on the right edge in the one-line form, at the end of the second line otherwise.
    private func setTime(_ item: NSMenuItem, _ agent: MenuBarSnapshot.Agent, now: Date) {
        let time = Self.elapsed(since: agent.startedAt, now: now)
        if item.toolTip != nil {
            item.badge = NSMenuItemBadge(string: time)
        } else {
            item.subtitle = "\(agent.task) · \(agent.step) · \(time)"
        }
    }

    /// One item: title, optional second line, and a symbol as the lab says.
    private func entry(_ title: String, _ symbol: String, subtitle: String? = nil, status: Bool = false,
                       action: @escaping () -> Void) -> NSMenuItem {
        let item = ActionItem(title: title, action: #selector(ActionItem.fire), keyEquivalent: "")
        item.target = item
        item.handler = action
        item.subtitle = subtitle
        switch look.symbols {
        case .system:
            // macOS 27 decides from the system configuration and usually hides menu images (`preferredImageVisibility`
            // stays automatic); the image is there for when it shows them.
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        case .all, .status:
            guard look.symbols == .all || status else { break }
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
        case .none:
            break
        }
        return item
    }

    private func setKey(_ shortcut: KeyboardShortcut?, _ item: NSMenuItem) {
        guard let shortcut else { return }
        item.keyEquivalent = String(shortcut.key.character).lowercased()
        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) { mask.insert(.command) }
        if shortcut.modifiers.contains(.option) { mask.insert(.option) }
        if shortcut.modifiers.contains(.control) { mask.insert(.control) }
        if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
        item.keyEquivalentModifierMask = mask
    }

    // MARK: Actions

    private func open(ticketId: Int) {
        if let state, let t = try? state.store.ticket(id: ticketId) { state.open(t) }
        bringForward()
    }

    private func bringForward() {
        guard let state, let openWindow else { NSApp.activate(); return }
        state.showMainWindow(openWindow)
    }

    static func elapsed(since start: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    var handler: () -> Void = {}
    @objc func fire() { handler() }
}

// MARK: - Looks still being chosen

enum MenuBarForm: String, LabChoice {
    case menu, panel
    var title: String { ["menu": "Menu", "panel": "Panel (before)"][rawValue]! }
    var about: String {
        switch self {
        case .menu: "A real menu: the style picked in the menu bar review."
        case .panel: "The window panel it replaces, to compare in the menu bar."
        }
    }
}

enum MenuBarSymbols: String, LabChoice {
    case system, all, status, none
    var title: String { ["system": "As macOS decides", "all": "On every item", "status": "Only on status items", "none": "None"][rawValue]! }
    var about: String {
        switch self {
        case .system: "Follow macOS: on macOS 27 menus usually hide item symbols, as the system's own menus do."
        case .all: "A symbol beside each item, shown even where macOS would hide it."
        case .status: "Symbols on Decide, agents and problems; the actions are plain text."
        case .none: "Text only."
        }
    }
}

enum MenuBarDecideRow: String, LabChoice {
    case badge, sentence, header
    var title: String { ["badge": "Decide with a count", "sentence": "Count in the title", "header": "Count as a heading"][rawValue]! }
    var about: String {
        switch self {
        case .badge: "\"Decide\" with the count at the right edge."
        case .sentence: "\"13 Decisions Wait for You\" as the item."
        case .header: "A small \"13 Waiting\" heading over a Decide item."
        }
    }
}

enum MenuBarAgentRows: String, LabChoice {
    case twoLines, oneLine, submenu
    var title: String { ["twoLines": "Two lines", "oneLine": "One line", "submenu": "In a submenu"][rawValue]! }
    var about: String {
        switch self {
        case .twoLines: "The ticket on the first line; task, step and time under it."
        case .oneLine: "Ticket number, task and step, with the time at the right edge. The title shows on hover."
        case .submenu: "One \"2 Agents Working\" item that opens the list."
        }
    }
}

enum MenuBarProblemRow: String, LabChoice {
    case twoItems, oneItem
    var title: String { ["twoItems": "Problem, then Retry", "oneItem": "One item"][rawValue]! }
    var about: String {
        switch self {
        case .twoItems: "The problem and its detail, with a Retry item under it."
        case .oneItem: "The problem is the item; choosing it retries."
        }
    }
}

enum MenuBarLabContent: String, LabChoice {
    case live, busy, quiet, paused, problem
    var title: String { ["live": "Your data", "busy": "Busy", "quiet": "Quiet", "paused": "Paused", "problem": "Sync problem"][rawValue]! }
    var about: String {
        switch self {
        case .live: "What Hatch has now."
        case .busy: "13 decisions and two agents with a long ticket title (sample)."
        case .quiet: "Nothing waits and nothing runs (sample)."
        case .paused: "Agents paused, 4 decisions (sample)."
        case .problem: "GitHub refused the token, one agent working (sample)."
        }
    }
}

/// The looks picked in the Menu Bar Lab, kept between launches. The content sample is not kept: the menu bar shows
/// your own data again when the lab closes.
final class MenuBarLook: ObservableObject {
    static let shared = MenuBarLook()

    @Published var form: MenuBarForm { didSet { save(form, "form") } }
    @Published var symbols: MenuBarSymbols { didSet { save(symbols, "symbols") } }
    @Published var decide: MenuBarDecideRow { didSet { save(decide, "decide") } }
    @Published var agents: MenuBarAgentRows { didSet { save(agents, "agents") } }
    @Published var problem: MenuBarProblemRow { didSet { save(problem, "problem") } }
    @Published var content: MenuBarLabContent

    private init() {
        form = Self.load("form") ?? .menu
        symbols = Self.load("symbols") ?? .system
        decide = Self.load("decide") ?? .badge
        agents = Self.load("agents") ?? .twoLines
        problem = Self.load("problem") ?? .twoItems
        // Never saved; only a launch argument (`-hatch.menuBarLook.content busy`) starts on a sample, for screenshots.
        content = Self.load("content") ?? .live
    }

    func reset() {
        form = .menu; symbols = .system; decide = .badge; agents = .twoLines; problem = .twoItems
    }

    var summary: String {
        "Menu bar item: \(form.title); Symbols: \(symbols.title); Decide: \(decide.title); Agents: \(agents.title); Problem: \(problem.title)"
    }

    private static func load<E: LabChoice>(_ name: String) -> E? {
        UserDefaults.standard.string(forKey: "hatch.menuBarLook.\(name)").flatMap(E.init(rawValue:))
    }

    private func save<E: LabChoice>(_ value: E, _ name: String) {
        UserDefaults.standard.set(value.rawValue, forKey: "hatch.menuBarLook.\(name)")
    }
}
