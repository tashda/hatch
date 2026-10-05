import SwiftUI
import AppKit
import HatchCore

/// Where the palette searches. ⌘K opens on Tickets; each other scope has its own shortcut and a prefix you can type,
/// which becomes a token in the field. Backspace on an empty field widens to everything.
enum PaletteScope: CaseIterable {
    case all, tickets, actions, places, reference

    var prefix: Character? {
        switch self {
        case .all: nil
        case .tickets: "#"
        case .actions: ">"
        case .places: "/"
        case .reference: "@"
        }
    }

    var title: String {
        switch self {
        case .all: "Everything"
        case .tickets: "Tickets"
        case .actions: "Actions"
        case .places: "Go to"
        case .reference: "Spec and decisions"
        }
    }

    var placeholder: String {
        switch self {
        case .all: "Search tickets, Spec, actions and places"
        case .tickets: "Search tickets by title or number"
        case .actions: "Run an action"
        case .places: "Go to a page, project or setting"
        case .reference: "Search the Spec and decisions"
        }
    }

    /// The menu shortcut that opens the palette on this scope, shown in the prefix list.
    var shortcut: [String] {
        switch self {
        case .all: []
        case .tickets: ["⌘", "K"]
        case .actions: ["⇧", "⌘", "P"]
        case .places: ["⇧", "⌘", "K"]
        case .reference: ["⌥", "⌘", "K"]
        }
    }

    init?(prefix: Character) {
        guard let scope = Self.allCases.first(where: { $0.prefix == prefix }) else { return nil }
        self = scope
    }
}

/// Fuzzy matching for titles: the query's letters in order, each one either at the start of a word or right after
/// the previous match. "mc" finds Manage Connections and "conn" finds Connection, but scattered letters don't match.
enum FuzzyMatch {
    struct Result { let score: Int; let indices: [Int] }

    static func match(_ query: String, in text: String) -> Result? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        let t = Array(text.lowercased())
        guard !q.isEmpty, q.count <= t.count else { return nil }
        let original = Array(text)
        // A plain substring scores highest, more so at a word start and near the beginning.
        if let range = text.range(of: query.trimmingCharacters(in: .whitespaces), options: .caseInsensitive) {
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            let bonus = isWordStart(start, original) ? 100 : 0
            return Result(score: 300 + bonus - min(start, 50), indices: Array(start..<(start + length)))
        }
        var failed = Set<Int>()
        func search(_ qi: Int, _ previous: Int) -> [Int]? {
            if qi == q.count { return [] }
            let key = qi * 10_000 + previous + 1
            if failed.contains(key) { return nil }
            var ti = previous + 1
            while ti < t.count {
                if t[ti] == q[qi], ti == previous + 1 || isWordStart(ti, original), let rest = search(qi + 1, ti) {
                    return [ti] + rest
                }
                ti += 1
            }
            failed.insert(key)
            return nil
        }
        guard let indices = search(0, -1) else { return nil }
        let starts = indices.filter { isWordStart($0, original) }.count
        let gaps = zip(indices, indices.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0 - 1) }
        return Result(score: 100 + starts * 10 - min(gaps, 60), indices: indices)
    }

    private static func isWordStart(_ i: Int, _ text: [Character]) -> Bool {
        if i == 0 { return true }
        let previous = text[i - 1], current = text[i]
        if !(previous.isLetter || previous.isNumber) { return true }
        return previous.isLowercase && current.isUppercase
    }

    /// The title with the matched characters in bold.
    static func highlighted(_ text: String, _ indices: [Int]) -> AttributedString {
        var out = AttributedString(text)
        let chars = out.characters
        for i in indices where i < chars.count {
            let start = chars.index(chars.startIndex, offsetBy: i)
            out[start..<chars.index(after: start)].inlinePresentationIntent = .stronglyEmphasized
        }
        return out
    }

    /// For full-text hits: each query word in bold wherever it appears.
    static func highlightedWords(_ text: String, _ query: String) -> AttributedString {
        var out = AttributedString(text)
        for word in query.split(whereSeparator: \.isWhitespace) where word.count > 1 {
            var searchStart = out.startIndex
            while let range = out[searchStart...].range(of: String(word), options: .caseInsensitive) {
                out[range].inlinePresentationIntent = .stronglyEmphasized
                searchStart = range.upperBound
            }
        }
        return out
    }
}

extension View {
    /// Shows the command palette as a floating glass panel over the window (the design review's option 1A).
    func commandPaletteOverlay() -> some View { modifier(CommandPaletteOverlay()) }
}

private struct CommandPaletteOverlay: ViewModifier {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if state.showPalette {
                ZStack(alignment: .top) {
                    // Clicking anywhere outside the panel closes it, as Spotlight does.
                    Color.black.opacity(0.0001)
                        .contentShape(Rectangle())
                        .onTapGesture { state.showPalette = false }
                    CommandPalette()
                        .padding(.top, 72)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.snappy(duration: 0.18), value: state.showPalette)
        // A page change from anywhere (a menu shortcut, Back) closes it.
        .onChange(of: state.route) { _, _ in state.showPalette = false }
    }
}

/// ⌘K: tickets first, then actions, places, the Spec and decisions. Results come in groups of one-line rows;
/// Return runs the selected row and Tab lists what else can be done with a ticket.
struct CommandPalette: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var query = ""
    @State private var scope: PaletteScope = .tickets
    @State private var groups: [Group] = []
    @State private var selection = 0
    @State private var actionsFor: Ticket?
    @State private var actionSelection = 0
    @State private var allTickets: [Ticket] = []
    @State private var specItems: [SpecItem] = []
    /// Read once when the palette opens; the Keychain is not read on every keystroke.
    @State private var githubConnected = HXKeychain.read() != nil
    /// The text field takes Backspace before onKeyPress sees it, so Backspace on an empty field is caught here.
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool

    struct Hit: Identifiable {
        enum Trailing { case none, status(Status, Turn), keys([String]), text(String) }
        let id: String
        let symbol: String
        var number: String? = nil
        let title: AttributedString
        var trailing: Trailing = .none
        /// Shown for context only, never selected (GitHub connected).
        var inert = false
        var ticket: Ticket? = nil
        let run: () -> Void
    }

    struct Group: Identifiable {
        let title: String
        var hits: [Hit]
        var id: String { title }
    }

    private static let rowHeight: CGFloat = 32
    private static let headerHeight: CGFloat = 24
    private static let maxResultsHeight: CGFloat = 8 * rowHeight + 3 * headerHeight + 12

    private var hasProjects: Bool { !state.projects.isEmpty }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var selectable: [Hit] { groups.flatMap(\.hits).filter { !$0.inert } }
    private var selectedHit: Hit? { selectable.indices.contains(selection) ? selectable[selection] : nil }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            field
            if !groups.isEmpty || !trimmed.isEmpty {
                Divider().opacity(0.6)
                results
            }
            Divider().opacity(0.6)
            footer
        }
        .frame(width: 640)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay(alignment: .bottomTrailing) {
            if let ticket = actionsFor { actionPanel(ticket).padding(.trailing, 12).padding(.bottom, 42) }
        }
        .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
        .onAppear {
            scope = hasProjects ? state.paletteScope : .all
            allTickets = (try? state.store.tickets(TicketFilter(projectId: state.projectFilterId, limit: 2000))) ?? []
            if let pid = referenceProjectId { specItems = (try? state.store.specItems(projectId: pid)) ?? [] }
            rebuild()
            DispatchQueue.main.async { focused = true }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let plain = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function]).isEmpty
                if event.keyCode == 51, plain, widenScope() { return nil }
                return event
            }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onChange(of: state.paletteScope) { _, new in
            if hasProjects { scope = new; query = ""; rebuild() }
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
            if scope != .all && hasProjects {
                Text(scope.title)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .help("Backspace searches everything")
            }
            TextField(scope.placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($focused)
                .onChange(of: query) { _, _ in queryChanged() }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.tab) { toggleActions(); return .handled }
                .onKeyPress(.escape) { escape(); return .handled }
                .onKeyPress(keys: [.return]) { press in
                    activate(command: press.modifiers.contains(.command), window: press.modifiers.contains(.option))
                    return .handled
                }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let selectedId = selectedHit?.id
                    ForEach(groups) { group in
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: Self.headerHeight, alignment: .bottomLeading)
                        ForEach(group.hits) { hit in
                            row(hit, selected: hit.id == selectedId)
                                .id(hit.id)
                                .contentShape(Rectangle())
                                .onTapGesture { if !hit.inert { run(hit) } }
                                .onHover { inside in
                                    if inside, actionsFor == nil, let i = selectable.firstIndex(where: { $0.id == hit.id }) { selection = i }
                                }
                        }
                    }
                    if groups.isEmpty {
                        Text("Nothing found").foregroundStyle(.secondary).padding(12)
                    }
                }
                .padding(6)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: resultsHeight)
            .onChange(of: selection) { _, _ in
                if let id = selectedHit?.id { proxy.scrollTo(id) }
            }
        }
    }

    private var resultsHeight: CGFloat {
        let rows = CGFloat(groups.reduce(0) { $0 + $1.hits.count })
        let content = rows * Self.rowHeight + CGFloat(groups.count) * Self.headerHeight + 12
        return min(max(content, 44), Self.maxResultsHeight)
    }

    private func row(_ hit: Hit, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: hit.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            if let number = hit.number {
                Text(number)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 38, alignment: .leading)
            }
            Text(hit.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 12)
            trailing(hit.trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background {
            // No glass on glass (DESIGN rule 3): the selection is a plain fill.
            if selected { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.opacity(0.2)) }
        }
        .opacity(hit.inert ? 0.55 : 1)
    }

    @ViewBuilder private func trailing(_ trailing: Hit.Trailing) -> some View {
        switch trailing {
        case .none:
            EmptyView()
        case .status(let status, let turn):
            HStack(spacing: 5) {
                Image(systemName: status.phaseSymbol).foregroundStyle(Theme.color(for: turn))
                Text(status.displayName).foregroundStyle(.secondary)
            }
            .font(.caption)
        case .keys(let keys):
            KeyCaps(keys: keys)
        case .text(let text):
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if !hasProjects {
                Text("No project yet")
            } else if let project = state.selectedProject ?? (state.projects.count == 1 ? state.projects.first : nil) {
                HStack(spacing: 6) {
                    ProjectTile(name: project.name, key: project.key, size: 14)
                    Text(project.name)
                }
            } else {
                Text("All projects")
            }
            Spacer()
            if actionsFor != nil {
                hint(["↵"], "Run")
                hint(["esc"], "Back")
            } else {
                hint(["↵"], selectedHit?.id == "capture" ? "Capture" : "Open")
                if selectedHit?.ticket != nil {
                    hint(ShortcutStore.shared.chord("palette.openWindow")?.symbols ?? [], "New window")
                    hint(["⇥"], "Actions")
                }
                if scope != .all && hasProjects && trimmed.isEmpty { hint(["⌫"], "Everything") }
                hint(["esc"], "Close")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    private func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 5) { KeyCaps(keys: keys); Text(label) }
    }

    private func actionPanel(_ ticket: Ticket) -> some View {
        let actions = ticketActions(ticket)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(ticket.displayNumber)  \(ticket.title)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, hit in
                row(hit, selected: index == actionSelection)
                    .contentShape(Rectangle())
                    .onTapGesture { run(hit) }
                    .onHover { if $0 { actionSelection = index } }
            }
        }
        .padding(5)
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
    }

    // MARK: Keys

    private func queryChanged() {
        // A prefix typed into an empty field switches the scope. In Tickets, "#" stays text: "#142" finds ticket 142.
        if hasProjects, query.count == 1, let c = query.first, let target = PaletteScope(prefix: c), target != scope {
            scope = target
            query = ""
            return
        }
        actionsFor = nil
        selection = 0
        rebuild()
    }

    private func widenScope() -> Bool {
        guard query.isEmpty, scope != .all else { return false }
        scope = .all
        selection = 0
        rebuild()
        return true
    }

    private func move(_ delta: Int) {
        if let ticket = actionsFor {
            let count = ticketActions(ticket).count
            actionSelection = min(max(actionSelection + delta, 0), count - 1)
            return
        }
        guard !selectable.isEmpty else { return }
        selection = min(max(selection + delta, 0), selectable.count - 1)
    }

    private func toggleActions() {
        if actionsFor != nil { actionsFor = nil; return }
        if let ticket = selectedHit?.ticket { actionsFor = ticket; actionSelection = 0 }
    }

    private func escape() {
        if actionsFor != nil { actionsFor = nil } else { close() }
    }

    private func activate(command: Bool, window: Bool = false) {
        // ⌥Return opens the ticket in a window of its own.
        if window, let ticket = actionsFor ?? selectedHit?.ticket {
            close()
            openWindow(id: "ticket", value: ticket.id)
            return
        }
        if let ticket = actionsFor {
            let actions = ticketActions(ticket)
            if actions.indices.contains(actionSelection) { run(actions[actionSelection]) }
            return
        }
        // ⌘Return: write a full ticket with this title.
        if command, hasProjects, !trimmed.isEmpty { newTicket(title: trimmed); return }
        if let hit = selectedHit { run(hit) }
    }

    private func run(_ hit: Hit) {
        close()
        hit.run()
    }

    private func close() {
        actionsFor = nil
        state.showPalette = false
    }

    // MARK: Results

    private func rebuild() {
        groups = hasProjects ? projectGroups() : setupGroups()
        if selection >= selectable.count { selection = 0 }
    }

    /// Until there is a project nothing but setup works, so only setup is offered.
    private func setupGroups() -> [Group] {
        var start: [Hit] = []
        if githubConnected {
            start.append(Hit(id: "github-ok", symbol: "checkmark.circle.fill", title: "GitHub connected", inert: true, run: {}))
        } else {
            start.append(Hit(id: "github", symbol: "link", title: "Connect GitHub", trailing: .text("Opens Set up a project"),
                             run: { state.showAddProject = true }))
        }
        start.append(Hit(id: "add-project", symbol: "square.stack.3d.up", title: "Set up a project",
                         trailing: .text("Repositories, folder, agents"), run: { state.showAddProject = true }))
        let hatch = [settingsHit(nil)]
        let groups = [Group(title: "Get started", hits: start), Group(title: "Hatch", hits: hatch)]
        return filtered(groups)
    }

    private func projectGroups() -> [Group] {
        let q = trimmed
        switch scope {
        case .tickets:
            if q.isEmpty { return yourWork(limit: 5) }
            return nonEmpty([Group(title: "Tickets", hits: ticketHits(q, limit: 8))]) + fallback(q)
        case .actions:
            return filtered(actionGroups())
        case .places:
            return filtered(placeGroups())
        case .reference:
            return referenceGroups(q)
        case .all:
            if q.isEmpty {
                return yourWork(limit: 3) + [Group(title: "Actions", hits: Array(actionGroups().flatMap(\.hits).prefix(3)))]
            }
            var out = nonEmpty([Group(title: "Tickets", hits: ticketHits(q, limit: 4))])
            out += nonEmpty(filtered(actionGroups()).map { Group(title: $0.title, hits: Array($0.hits.prefix(3))) })
            out += nonEmpty([Group(title: "Go to", hits: Array(filtered(placeGroups()).flatMap(\.hits).prefix(3)))])
            out += referenceGroups(q, specLimit: 3, decisionLimit: 2)
            return out + fallback(q)
        }
    }

    private func nonEmpty(_ groups: [Group]) -> [Group] { groups.filter { !$0.hits.isEmpty } }

    /// Fuzzy-filters fixed lists (actions, places, setup) and bolds what matched.
    private func filtered(_ groups: [Group]) -> [Group] {
        let q = trimmed
        guard !q.isEmpty else { return groups }
        return nonEmpty(groups.map { group in
            let scored: [(Int, Hit)] = group.hits.compactMap { hit in
                let plain = String(hit.title.characters)
                guard let m = FuzzyMatch.match(q, in: plain) else { return nil }
                var h = hit
                h = Hit(id: hit.id, symbol: hit.symbol, number: hit.number, title: FuzzyMatch.highlighted(plain, m.indices),
                        trailing: hit.trailing, inert: hit.inert, ticket: hit.ticket, run: hit.run)
                return (m.score, h)
            }
            return Group(title: group.title, hits: scored.sorted { $0.0 > $1.0 }.map(\.1))
        })
    }

    // MARK: Tickets

    /// Before you type: what waits for you, then what you had open recently.
    private func yourWork(limit: Int) -> [Group] {
        let waiting = allTickets.filter { $0.turn == .you }.prefix(limit)
        let shown = Set(waiting.map(\.id))
        let byId = Dictionary(allTickets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let recent = state.recentTicketIds.compactMap { byId[$0] }.filter { !shown.contains($0.id) }.prefix(limit)
        return nonEmpty([
            Group(title: "Waiting for you", hits: waiting.map { ticketHit($0, title: AttributedString($0.title)) }),
            Group(title: "Recent", hits: recent.map { ticketHit($0, title: AttributedString($0.title)) }),
        ])
    }

    /// The exact number first, then fuzzy title matches (your turn and recent ones lifted, finished ones lowered),
    /// then full-text hits from the ticket body.
    private func ticketHits(_ q: String, limit: Int) -> [Hit] {
        var out: [Hit] = []
        var seen = Set<Int>()
        let looksLikeNumber = q.hasPrefix("#") || q.allSatisfy(\.isNumber)
        if looksLikeNumber, let t = try? state.store.resolve(q), state.projectFilterId == nil || t.projectId == state.projectFilterId {
            out.append(ticketHit(t, title: AttributedString(t.title)))
            seen.insert(t.id)
        }
        let recent = Set(state.recentTicketIds)
        let fuzzy: [(Int, Ticket, [Int])] = allTickets.compactMap { t in
            guard !seen.contains(t.id), let m = FuzzyMatch.match(q, in: t.title) else { return nil }
            var score = m.score
            if t.turn == .you { score += 40 }
            if recent.contains(t.id) { score += 25 }
            if t.status.isTerminal { score -= 60 }
            return (score, t, m.indices)
        }
        for (_, t, indices) in fuzzy.sorted(by: { $0.0 > $1.0 }) {
            out.append(ticketHit(t, title: FuzzyMatch.highlighted(t.title, indices)))
            seen.insert(t.id)
        }
        if out.count < limit {
            let text = (try? state.store.tickets(TicketFilter(projectId: state.projectFilterId, text: q, limit: limit))) ?? []
            for t in text where !seen.contains(t.id) {
                out.append(ticketHit(t, title: FuzzyMatch.highlightedWords(t.title, q)))
                seen.insert(t.id)
            }
        }
        return Array(out.prefix(limit))
    }

    private func ticketHit(_ t: Ticket, title: AttributedString) -> Hit {
        Hit(id: "t\(t.id)", symbol: Theme.symbol(for: t.type), number: t.displayNumber, title: title,
            trailing: .status(t.status, t.turn), ticket: t, run: { state.open(t) })
    }

    /// When you type something new: capture it, or write the full ticket. Capture comes first when nothing matched.
    private func fallback(_ q: String) -> [Group] {
        let project = state.selectedProject ?? state.projects.first
        let capture = Hit(id: "capture", symbol: "plus.circle", title: AttributedString("Capture \u{201C}\(q)\u{201D} as a draft"),
                          trailing: .text("Title only · \(project?.name ?? "")"), run: { captureDraft(title: q) })
        let write = Hit(id: "write", symbol: "square.and.pencil", title: "New ticket with this title…",
                        trailing: .keys(["⌘", "↵"]), run: { newTicket(title: q) })
        return [Group(title: "Create", hits: [capture, write])]
    }

    /// Quick capture (decision E1): a Draft with only a title, no check, in the current or first project.
    /// The type is Question, the lightest one; it can be changed on the ticket.
    private func captureDraft(title: String) {
        guard let pid = state.projectFilterId ?? state.projects.first?.id else { return }
        let created: Ticket? = state.perform("Could not capture the draft") {
            try state.store.createTicket(projectId: pid, type: .question, title: title, body: "",
                                         area: nil, parentId: nil, status: .draft, actor: .owner)
        }
        if let created { state.open(created) }
    }

    private func newTicket(title: String) {
        close()
        state.composerTitle = title
        state.navigate(to: .newTicket)
    }

    /// What can be done with a ticket without opening it. Moves go through HatchStore.move and only where the
    /// workflow lets the owner make them without more input; sending back and accepting stay on the ticket.
    private func ticketActions(_ t: Ticket) -> [Hit] {
        let id = t.id
        func allowed(_ s: Status) -> Bool { Workflow.isAllowed(type: t.type, from: t.status, to: s, actor: .owner) }
        func move(_ title: String, _ symbol: String, to status: Status, after: @escaping () -> Void = {}) -> Hit {
            Hit(id: "move-\(status.rawValue)", symbol: symbol, title: AttributedString(title)) {
                let moved: Ticket? = state.perform("Could not change the status") {
                    try state.store.move(id, to: status, actor: .owner, reason: "from the command palette")
                }
                if moved != nil { after() }
            }
        }
        var out = [Hit(id: "open", symbol: "arrow.up.forward.square", title: "Open", trailing: .keys(["↵"]), run: { state.open(t) })]
        out.append(Hit(id: "window", symbol: "macwindow", title: "Open in New Window",
                       trailing: .keys(ShortcutStore.shared.chord("palette.openWindow")?.symbols ?? []), run: { openWindow(id: "ticket", value: id) }))
        if t.status == .draft, allowed(.checking) {
            out.append(move("Submit for check", "paperplane", to: .checking) { VettingBridge.start(ticketId: id, state: state) })
        }
        if t.status == .yourCall, t.type.isProposalLike {
            out.append(Hit(id: "stage", symbol: "rectangle.on.rectangle", title: "Open the Proposal") {
                StageLauncher.shared.open(ticket: t, state: state)
            })
        }
        if t.status == .yourCall, t.type == .question, allowed(.done) { out.append(move("Close as answered", "checkmark.circle", to: .done)) }
        if t.status == .toVerify {
            out.append(Hit(id: "previews", symbol: "eye", title: "Verify in Previews", run: { state.navigate(to: .previews) }))
        }
        if t.status == .parked {
            out.append(Hit(id: "resume", symbol: "play.circle", title: "Resume") {
                _ = state.perform("Could not resume the ticket") { try state.store.resume(id, actor: .owner) }
            })
        }
        if t.status == .done || t.status == .dropped, allowed(.draft) { out.append(move("Reopen", "arrow.uturn.backward.circle", to: .draft)) }
        if allowed(.parked) { out.append(move("Park", "pause.circle", to: .parked)) }
        if let url = gitHubURL(t) {
            out.append(Hit(id: "github", symbol: "safari", title: "Open on GitHub", run: { NSWorkspace.shared.open(url) }))
            out.append(Hit(id: "copy", symbol: "link", title: "Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            })
        }
        out.append(Hit(id: "iris", symbol: "sparkles", title: "Show in Iris") {
            state.open(t)
            state.showAskPanel = true
        })
        return out
    }

    private func gitHubURL(_ t: Ticket) -> URL? {
        guard let number = t.ghNumber, let repo = state.project(id: t.projectId)?.config?.ticketsRepo, !repo.isEmpty else { return nil }
        return URL(string: "https://github.com/\(repo)/issues/\(number)")
    }

    // MARK: Actions and places

    private func actionGroups() -> [Group] {
        var out: [Group] = []
        if case .ticket(let id) = state.route, let t = allTickets.first(where: { $0.id == id }) ?? (try? state.store.ticket(id: id) ?? nil) {
            let actions = ticketActions(t).filter { $0.id != "open" }
            if !actions.isEmpty { out.append(Group(title: "This ticket · \(t.displayNumber)", hits: actions)) }
        }
        var hits: [Hit] = [
            Hit(id: "new", symbol: "plus", title: "New ticket", trailing: .keys(["⌘", "N"]), run: { state.navigate(to: .newTicket) }),
            Hit(id: "decide", symbol: "checklist", title: AttributedString(state.decisionCount > 0 ? "Decide · \(state.decisionCount) waiting" : "Decide"),
                trailing: .keys(["⇧", "⌘", "D"]), run: { state.openDecide() }),
            Hit(id: "iris-toggle", symbol: "sparkles", title: state.showAskPanel ? "Hide Iris" : "Show Iris",
                trailing: .keys(["⌥", "⌘", "A"]), run: { state.showAskPanel.toggle() }),
            Hit(id: "sync", symbol: "arrow.triangle.2.circlepath", title: "Sync with GitHub", trailing: .keys(["⇧", "⌘", "R"]),
                run: { state.syncNow() }),
        ]
        if !githubConnected {
            hits.append(Hit(id: "connect", symbol: "link", title: "Connect GitHub", run: { openSettings(.github) }))
        }
        hits += [
            Hit(id: "add-project", symbol: "square.stack.3d.up", title: "Add project", run: { state.showAddProject = true }),
            Hit(id: "sidebar", symbol: "sidebar.leading", title: state.showSidebar ? "Hide sidebar" : "Show sidebar",
                trailing: .keys(["⌃", "⌘", "S"]), run: { state.showSidebar.toggle() }),
            settingsHit(nil),
        ]
        out.append(Group(title: "Actions", hits: hits))
        return out
    }

    private func placeGroups() -> [Group] {
        let routes: [(Route, String?)] = [
            (.desk, "1"), (.tickets, "2"), (.board, "3"), (.previews, "4"), (.specs, "5"),
            (.decisions, "6"), (.components, nil), (.agents, "7"), (.log, "8"), (.projects, "9"),
        ]
        let pages = routes.map { route, key in
            Hit(id: "go-\(route.title)", symbol: route.symbol, title: AttributedString(route == .projects ? "Project settings" : route.title),
                trailing: key.map { .keys(["⌘", $0]) } ?? .none, run: { state.navigate(to: route) })
        }
        let projects = state.projects
        var projectHits = projects.map { p in
            Hit(id: "project-\(p.key)", symbol: "square.stack.3d.up", title: AttributedString(p.name),
                trailing: .text(state.selectedProjectKey == p.key ? "Current" : ""), run: { state.selectedProjectKey = p.key })
        }
        if projects.count > 1 {
            projectHits.insert(Hit(id: "project-all", symbol: "square.stack.3d.up", title: "All projects",
                                   trailing: .text(state.selectedProjectKey == nil ? "Current" : ""),
                                   run: { state.selectedProjectKey = nil }), at: 0)
        }
        let settings: [Hit] = SettingsPage.allCases.map { page in
            Hit(id: "settings-\(page.title)", symbol: page.symbol, title: AttributedString("Settings: \(page.title)"),
                run: { openSettings(page) })
        }
        return nonEmpty([Group(title: "Pages", hits: pages), Group(title: "Projects", hits: projects.count > 1 ? projectHits : []),
                         Group(title: "Settings", hits: settings)])
    }

    private func settingsHit(_ page: SettingsPage?) -> Hit {
        Hit(id: "settings", symbol: "gearshape", title: "Settings", trailing: .keys(["⌘", ","]), run: { openSettings(page) })
    }

    private func openSettings(_ page: SettingsPage?) {
        state.settingsPage = page
        openWindow(id: "settings")
    }

    // MARK: Spec and decisions

    /// The Spec belongs to one project: the selected one, else the first.
    private var referenceProjectId: Int? { state.hxProject?.id ?? state.projectFilterId ?? state.projects.first?.id }

    private func referenceGroups(_ q: String, specLimit: Int = 6, decisionLimit: Int = 4) -> [Group] {
        guard let pid = referenceProjectId else { return [] }
        let decisions = (try? state.store.decisions(projectId: pid)) ?? []
        if q.isEmpty {
            let recent = decisions.prefix(decisionLimit).map { decisionHit($0.ticket, summary: AttributedString($0.summary)) }
            return nonEmpty([Group(title: "Recent decisions", hits: Array(recent))])
        }
        // Fuzzy over the code and text first (a partial word finds it), then full-text hits for whole words.
        func specHit(_ s: SpecItem, _ title: AttributedString) -> Hit {
            Hit(id: "s\(s.id)", symbol: "doc.text", number: s.code, title: title, trailing: .text(s.area ?? ""),
                run: { state.navigate(to: .specs) })
        }
        let fuzzy: [(Int, Hit)] = specItems.compactMap { s in
            if s.code.localizedCaseInsensitiveContains(q) { return (400, specHit(s, AttributedString(s.text))) }
            guard let m = FuzzyMatch.match(q, in: s.text) else { return nil }
            return (m.score, specHit(s, FuzzyMatch.highlighted(s.text, m.indices)))
        }
        var specHits = fuzzy.sorted { $0.0 > $1.0 }.map(\.1)
        let text = (try? state.store.searchSpec(projectId: pid, query: q, limit: specLimit)) ?? []
        for s in text where !specHits.contains(where: { $0.id == "s\(s.id)" }) {
            specHits.append(specHit(s, FuzzyMatch.highlightedWords(s.text, q)))
        }
        specHits = Array(specHits.prefix(specLimit))
        let matched: [(Int, Hit)] = decisions.compactMap { d in
            if let m = FuzzyMatch.match(q, in: d.summary) {
                return (m.score, decisionHit(d.ticket, summary: FuzzyMatch.highlighted(d.summary, m.indices)))
            }
            if d.specCodes.contains(where: { $0.localizedCaseInsensitiveContains(q) }) {
                return (50, decisionHit(d.ticket, summary: AttributedString(d.summary)))
            }
            return nil
        }
        let decisionHits = matched.sorted { $0.0 > $1.0 }.prefix(decisionLimit).map(\.1)
        return nonEmpty([Group(title: "Spec", hits: specHits), Group(title: "Decisions", hits: Array(decisionHits))])
    }

    /// A decision opens the ticket it was made on, where the options and the reason are.
    private func decisionHit(_ t: Ticket, summary: AttributedString) -> Hit {
        Hit(id: "d\(t.id)", symbol: "flag", title: summary, trailing: .text("from \(t.displayNumber)"), run: { state.open(t) })
    }
}

/// Keyboard keys drawn as small caps, as in menus.
private struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .hatchMark("KeyCaps")
    }
}
