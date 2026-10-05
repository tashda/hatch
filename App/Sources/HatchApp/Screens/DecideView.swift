import SwiftUI
import AppKit
import HatchCore
import HatchAgent

// Decide (decisions DC1 to DC12, concept page design-review/decide-concepts.html): a full-window session over everything
// that waits for the owner, one card at a time, quick ones first. Every answer waits ten seconds before Hatch acts, with
// Undo, and goes through the store's own calls; nothing new is stored except the session's events.

extension View {
    func decideOverlay() -> some View { modifier(DecideOverlay()) }
}

private struct DecideOverlay: ViewModifier {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if let request = state.decideSession {
                DecideSessionView(request: request, store: state.store, projectId: state.projectFilterId)
                    .id(request.id)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.snappy(duration: 0.2), value: state.decideSession)
    }
}

// MARK: - The session

/// What the owner did with a card, and whether it starts an agent.
struct DecideOutcome: Equatable {
    var kind: DecideRun.Outcome
    var startsAgent: Bool
}

/// The app's side of a session: it holds the `DecideRun` (order, Undo, the undo window, all tested in core), runs due
/// work once a second, and gives the feedback.
@MainActor
final class DecideSession: ObservableObject {
    @Published private(set) var run: DecideRun
    @Published var noteOpen = false
    @Published var note = ""
    @Published var highlight: String?
    /// True while the owner types an answer of their own, so the card's keys (1–4, N, Space) do not fire.
    @Published var typing = false
    private var timer: Timer?

    init(store: HatchStore, projectId: Int?, area: String?) {
        run = DecideRun(items: (try? store.pendingDecisions(projectId: projectId, area: area)) ?? [])
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var items: [PendingDecision] { run.items }
    var index: Int { run.index }
    var current: PendingDecision? { run.current }
    var remaining: Int { run.remaining }
    var minutesLeft: Int { run.minutesLeft }
    var toast: DecideRun.Waiting? { run.last }
    func outcome(_ id: String) -> DecideRun.Outcome? { run.records[id]?.outcome }

    /// Records the owner's decision on the current card. `work` happens after the undo window, or when the session closes.
    func decide(_ outcome: DecideOutcome, label: String, work: @escaping () -> Void) {
        run.decide(outcome.kind, startsAgent: outcome.startsAgent, label: label, run: work)
        noteOpen = false; note = ""; highlight = nil
        DecideFeedback.decided()
    }

    func undo() { run.undo() }

    /// Goes to a decision without deciding the one on screen (Back, Forward, a pill, the queue card).
    func go(to id: String) {
        guard run.open.contains(id) else { return }
        run.go(to: id)
        noteOpen = false; note = ""; highlight = nil; typing = false
    }

    /// The open decision before or after the one on screen, in the pills' order.
    func neighbour(_ by: Int) -> String? {
        let open = run.open
        guard let cur = current?.id, let i = open.firstIndex(of: cur), open.indices.contains(i + by) else { return nil }
        return open[i + by]
    }

    /// How many decisions are still open, the one on screen included.
    var openCount: Int { run.open.count }

    private func tick() {
        let due = run.due()
        due.forEach { $0() }
        run.clearLast()
        objectWillChange.send()
    }

    /// Ends the session: every decision still waiting runs now.
    func stop() {
        timer?.invalidate(); timer = nil
        run.due(all: true).forEach { $0() }
    }
}

/// The trackpad tap and the optional sound when a card is decided (DC7). Both are Settings, Decide.
enum DecideFeedback {
    static let hapticsKey = "hatch.decide.haptics"
    static let soundKey = "hatch.decide.sound"

    static func decided() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: hapticsKey) as? Bool ?? true {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if defaults.bool(forKey: soundKey) { NSSound(named: "Tink")?.play() }
    }
}

/// The days in a row the owner cleared everything (DC6), kept as a setting so it survives relaunches.
enum DecideStreak {
    static let key = "decide.streak"

    static func days(_ store: HatchStore) -> Int {
        guard let (last, n) = read(store) else { return 0 }
        let cal = Calendar.current
        return cal.isDateInToday(last) || cal.isDateInYesterday(last) ? n : 0
    }

    static func cleared(_ store: HatchStore) {
        let cal = Calendar.current
        var n = 1
        if let (last, count) = read(store) {
            if cal.isDateInToday(last) { return }
            if cal.isDateInYesterday(last) { n = count + 1 }
        }
        try? store.setSetting(key, "\(day.string(from: Date()))|\(n)")
    }

    private static func read(_ store: HatchStore) -> (Date, Int)? {
        guard let raw = (try? store.setting(key)) ?? nil else { return nil }
        let parts = raw.split(separator: "|")
        guard parts.count == 2, let d = day.date(from: String(parts[0])), let n = Int(parts[1]) else { return nil }
        return (d, n)
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Which decisions the owner has seen, so Iris can say how many are new since the last session (DC10).
enum DecideSeen {
    static let key = "hatch.decide.seen"
    static var ids: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func remember(_ ids: [String]) { UserDefaults.standard.set(ids, forKey: key) }
}

// MARK: - The window

struct DecideSessionView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var session: DecideSession
    @FocusState private var focused: Bool
    @FocusState private var noteFocused: Bool
    @State private var showShortcuts = false
    /// Which side's queue card is showing (hovering an arrow), and whether the pointer is on the arrow or the card.
    @State private var queueSide: HorizontalEdge?
    @State private var overArrow = false
    @State private var overQueue = false
    let request: AppState.DecideRequest

    init(request: AppState.DecideRequest, store: HatchStore, projectId: Int?) {
        self.request = request
        _session = StateObject(wrappedValue: DecideSession(store: store, projectId: projectId, area: request.area))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                if let item = session.current {
                    DecideCard(item: item, session: session, noteFocused: $noteFocused, leave: leave)
                        .id(item.id + "-\(session.index)")
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 16)),
                                                removal: .opacity.combined(with: .offset(x: -60))))
                } else {
                    summary.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.snappy(duration: 0.28), value: session.index)
            .overlay(alignment: .bottom) { toast.padding(.bottom, session.current == nil ? 18 : 82) }
            .overlay { if session.current != nil { sideArrows.padding(.bottom, 64) } }
            .animation(.snappy(duration: 0.22), value: queueSide)
        }
        // One grey panel with the decision on a white card in it (DR8); the window footer stays visible under it.
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.3)))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.init(top: 6, leading: 8, bottom: 0, trailing: 8))
        .background(Color(nsColor: .underPageBackgroundColor))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { press in handle(press) }
        .onDisappear { finish() }
    }

    // MARK: Parts

    private var topBar: some View {
        HStack(spacing: 14) {
            Label(title, systemImage: "checklist").font(.headline)
            Spacer()
            progressPills
            Spacer()
            Text(session.current == nil ? "All clear" : "\(session.openCount) left")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Button { showShortcuts.toggle() } label: { Image(systemName: "questionmark") }
                .buttonStyle(.glass).buttonBorderShape(.capsule)
                .help("Keyboard shortcuts (?)")
                .accessibilityLabel("Keyboard shortcuts")
                .popover(isPresented: $showShortcuts, arrowEdge: .bottom) { shortcuts }
            Button("Done") { close(to: nil) }.buttonStyle(.glass).buttonBorderShape(.capsule).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var title: String {
        let project = (state.selectedProject ?? (state.projects.count == 1 ? state.projects.first : nil))?.name
        let base = request.area.map { "Decide · \($0)" } ?? "Decide"
        return project.map { "\(base) · \($0)" } ?? base
    }

    /// One pill per decision in its first place (Later does not add one at the end), coloured by whose turn it is
    /// now (DESIGN.md rule 6): amber on screen, teal when an agent goes on, green when it is done, an outline when it
    /// was left for later, faint when not reached.
    private var progressPills: some View {
        let numbers = Dictionary(session.items.map { ($0.id, $0.ticket.displayNumber) }, uniquingKeysWith: { a, _ in a })
        let byId = Dictionary(session.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return HStack(spacing: 4) {
            ForEach(session.run.marks, id: \.id) { m in
                if let item = byId[m.id] {
                    DecidePill(mark: m.mark, item: item, canGo: session.run.open.contains(m.id) && m.mark != .current) { session.go(to: m.id) }
                        .accessibilityLabel("\(numbers[m.id] ?? ""), \(Self.words(m.mark))")
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: session.current?.id)
    }

    @ViewBuilder static func pill(_ mark: DecideRun.Mark) -> some View {
        switch mark {
        case .current: Capsule().fill(Theme.you).frame(width: 28, height: 6)
        case .waiting: Capsule().fill(Color.secondary.opacity(0.2)).frame(width: 16, height: 6)
        case .later: Capsule().strokeBorder(Theme.paused, lineWidth: 1.2).frame(width: 16, height: 6)
        case .handled(let startsAgent): Capsule().fill(startsAgent ? Theme.agent : Theme.finished).frame(width: 16, height: 6)
        case .setAside: Capsule().fill(Theme.paused).frame(width: 16, height: 6)
        }
    }

    static func words(_ mark: DecideRun.Mark) -> String {
        switch mark {
        case .current: "on screen"
        case .waiting: "not reached yet"
        case .later: "left for later"
        case .handled(let startsAgent): startsAgent ? "decided, an agent goes on" : "decided, done"
        case .setAside: "parked or dropped"
        }
    }

    @ViewBuilder private var toast: some View {
        if let t = session.toast {
            HStack(spacing: 12) {
                Text(t.label).lineLimit(1)
                if t.startsAgent, session.outcome(t.itemId) != .later {
                    let left = max(0, Int(t.fireAt.timeIntervalSinceNow.rounded(.up)))
                    if left > 0 { Text("Agent starts in \(left) s").foregroundStyle(.secondary).monospacedDigit() }
                }
                Button { session.undo() } label: { Text("Undo") }
                    .buttonStyle(.bordered).controlSize(.small).help("Undo (Z)")
            }
            .font(.callout)
            .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Back, Forward and what is left

    /// A round glass arrow at each side of the card: Back and Forward go to the previous or next open decision without
    /// deciding this one. Resting the pointer on an arrow slides in what is left as a glass card on that side.
    private var sideArrows: some View {
        HStack(alignment: .center, spacing: 0) {
            arrow(.leading)
            Spacer(minLength: 0)
            arrow(.trailing)
        }
        .padding(.horizontal, 16)
        .overlay(alignment: queueSide == .leading ? .leading : .trailing) {
            if let side = queueSide {
                DecideQueueCard(session: session) { id in session.go(to: id); queueSide = nil }
                    .padding(side == .leading ? .leading : .trailing, 72)
                    .onHover { overQueue = $0; hoverChanged(side) }
                    .transition(.move(edge: side == .leading ? .leading : .trailing).combined(with: .opacity))
            }
        }
    }

    private func arrow(_ side: HorizontalEdge) -> some View {
        let target = session.neighbour(side == .leading ? -1 : 1)
        return Button { if let target { session.go(to: target) } } label: {
            Image(systemName: side == .leading ? "chevron.left" : "chevron.right").font(.title3.weight(.semibold)).frame(width: 22, height: 22)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .opacity(target == nil ? 0.35 : 1)
        .help(side == .leading ? "Previous decision, without deciding this one (←)" : "Next decision, without deciding this one (→)")
        .accessibilityLabel(side == .leading ? "Previous decision" : "Next decision")
        .onHover { overArrow = $0; hoverChanged(side) }
    }

    /// Opens the card for the side the pointer is on; closes it a moment after the pointer leaves both the arrow and
    /// the card, so moving from one to the other keeps it open.
    private func hoverChanged(_ side: HorizontalEdge) {
        if overArrow || overQueue {
            if queueSide == nil || overArrow { queueSide = side }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { if !overArrow && !overQueue { queueSide = nil } }
    }

    /// The keys, in a popover from the ? button rather than always on screen.
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard shortcuts").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                hint("↵", "Answer, or the main action")
                hint("1–4", "Select an answer")
                hint("↑ ↓", "Move the selection")
                hint("← →", "Previous or next decision, without deciding")
                hint("N", "Write a note")
                hint("R", "Send back to refine")
                hint("Space", "Later")
                hint("P", "Park the ticket")
                hint("Z", "Undo")
                hint("?", "Show these shortcuts")
                hint("esc", "Done")
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                legend(.current); legend(.handled(startsAgent: true)); legend(.handled(startsAgent: false)); legend(.setAside); legend(.later); legend(.waiting)
            }
        }
        .padding(16)
    }

    private func legend(_ mark: DecideRun.Mark) -> some View {
        HStack(spacing: 10) {
            Self.pill(mark).frame(width: 28, alignment: .center)
            Text(Self.words(mark).capitalizedFirst).font(.callout)
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        GridRow {
            Text(key).font(.callout.monospaced()).padding(.horizontal, 6).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                .gridColumnAlignment(.trailing)
            Text(label).font(.callout)
        }
    }

    private var summary: some View {
        let clearedAll = session.run.later == 0
        let streak = DecideStreak.days(state.store)
        return VStack(spacing: 14) {
            Text(session.items.isEmpty ? "Nothing waits for you" : clearedAll ? "All decided" : "Done for now")
                .font(.largeTitle.weight(.bold))
            if !session.items.isEmpty {
                Text("\(session.run.agreed + session.run.ownCall + session.run.refined) decided\(session.run.later > 0 ? ", \(session.run.later) left for later" : "")\(session.run.setAside > 0 ? ", \(session.run.setAside) parked or dropped" : ""). "
                     + "\(session.run.agentsStarted) agent\(session.run.agentsStarted == 1 ? "" : "s") started; the rest was bookkeeping.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    stat(session.run.agreed, "agreed with the recommendation")
                    stat(session.run.ownCall, "your own call")
                    stat(session.run.refined, "sent back to refine")
                }
                .frame(maxWidth: 520)
            }
            if streak > 1 { Text("Cleared everything \(streak) days in a row.").font(.callout).foregroundStyle(.secondary) }
            Button("Back to the Desk") { close(to: .desk) }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .onAppear { if clearedAll && !session.items.isEmpty { DecideStreak.cleared(state.store) } }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.title.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    // MARK: Keys and leaving

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if noteFocused || session.typing {
            if press.key == .return && session.typing { NotificationCenter.default.post(name: .hxDecideKey, object: "accept"); return .handled }
            return .ignored
        }
        if press.characters.lowercased() == "z" { session.undo(); return .handled }
        if press.characters == "?" { showShortcuts.toggle(); return .handled }
        guard session.current != nil else { return .ignored }
        switch press.key {
        case .return: NotificationCenter.default.post(name: .hxDecideKey, object: "accept"); return .handled
        case .leftArrow: if let id = session.neighbour(-1) { session.go(to: id) }; return .handled
        case .upArrow: NotificationCenter.default.post(name: .hxDecideKey, object: "up"); return .handled
        case .downArrow: NotificationCenter.default.post(name: .hxDecideKey, object: "down"); return .handled
        case .rightArrow: if let id = session.neighbour(1) { session.go(to: id) }; return .handled
        case .space: NotificationCenter.default.post(name: .hxDecideKey, object: "later"); return .handled
        default: break
        }
        let c = press.characters.lowercased()
        if ["1", "2", "3", "4", "n", "r", "p"].contains(c) { NotificationCenter.default.post(name: .hxDecideKey, object: c); return .handled }
        return .ignored
    }

    /// The card leaves the session for a page (the ticket, Previews): what was decided runs now.
    private func leave(_ route: Route) { close(to: route) }

    private func close(to route: Route?) {
        finish()
        state.decideSession = nil
        state.refresh()
        if let route { state.navigate(to: route) }
    }

    private func finish() {
        session.stop()
        DecideSeen.remember(((try? state.store.pendingDecisions(projectId: state.projectFilterId)) ?? []).map(\.id))
    }
}

extension Notification.Name {
    /// A key pressed in the Decide window, for the card on screen.
    static let hxDecideKey = Notification.Name("hxDecideKey")
}

// MARK: - One card

/// One decision, laid out as picked in the Decide Lab (decision DR8): the white card a third of the way down the grey
/// panel, 820 wide with airy spacing; the kind as a coloured eyebrow, the title large, the token row; the asker's whole
/// message in a bubble; the answers as a list. Selecting an answer does nothing; the action bar pinned to the bottom
/// (Later and Note, then the one prominent button) does it, and ↵ is that button.
private struct DecideCard: View {
    @EnvironmentObject var state: AppState
    let item: PendingDecision
    @ObservedObject var session: DecideSession
    var noteFocused: FocusState<Bool>.Binding
    let leave: (Route) -> Void

    @State private var choices: [AnswerOption] = []
    @State private var body_ = ""
    @State private var info = ProposalInfo()
    @State private var openQuestions: [Question] = []
    /// How many questions were open when the card came up, for "2 of 2" after the first is answered.
    @State private var totalQuestions = 0
    @State private var stillWaiting = true
    @State private var selected: String?
    @State private var own = ""
    @FocusState private var ownFocused: Bool

    /// The airy spacing from the Lab: every gap 1.4 times the regular one.
    private static let air: CGFloat = 1.4
    private static let width: CGFloat = 820

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        // A third of the way down, not floating in the middle and not pressed to the top.
                        Spacer().frame(height: max(20, geo.size.height * 0.12))
                        content
                            .frame(maxWidth: Self.width, alignment: .leading)
                            .padding(24)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
                            .padding(.horizontal, 32).padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            actionBar
        }
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .hxDecideKey)) { key($0.object as? String ?? "") }
        .onChange(of: ownFocused) { session.typing = ownFocused }
        // A screenshot pasted while deciding goes on this card's ticket, for the agent to see (decision E3).
        .pastesScreenshots { images in
            let id = item.ticket.id, state = state
            state.perform("Could not add the screenshot") {
                for image in images { try TicketScreenshots.save(image.data, name: image.name, ticketId: id, state: state) }
            }
            session.noteOpen = true
            if !session.note.contains("screenshot") { session.note += (session.note.isEmpty ? "" : " ") + "See the screenshot." }
        }
        .autoReload(every: 3) { checkStillWaiting() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            middle.padding(.top, (26 * Self.air).rounded())
            if session.noteOpen {
                TextField(refineAllowed ? "Note for the agent. Return sends it back to refine." : "Note on the ticket. Return saves it.",
                          text: $session.note, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4)
                    .focused(noteFocused)
                    .onSubmit { refineAllowed ? refine() : saveNote() }
                    .onExitCommand { session.noteOpen = false; noteFocused.wrappedValue = false }
                    .padding(.top, (14 * Self.air).rounded())
            }
        }
    }

    // MARK: Header and middle

    private var header: some View {
        VStack(alignment: .leading, spacing: (6 * Self.air).rounded()) {
            HStack(alignment: .firstTextBaseline) {
                // The kind in the colour of "your turn" (DESIGN.md rule 6), in small capitals.
                Text(eyebrow.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.you)
                Spacer()
                Button { leave(.ticket(item.ticket.id)) } label: { Label("Open \(item.ticket.displayNumber)", systemImage: "arrow.up.right").labelStyle(TrailingIconLabelStyle()) }
                    .buttonStyle(.link).font(.caption)
            }
            Text(item.ticket.title).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            FiledByIrisTokens(ticketId: item.ticket.id)
        }
    }

    private var eyebrow: String {
        let kind: String
        switch item.kind {
        case .pick: kind = choices.count == 2 ? "This or that" : "Pick one"
        case .plan: kind = "Approve a plan"
        case .iris: kind = currentQuestion.map { "\($0.askedBy) asks" } ?? "Iris checked this"
        case .answer: kind = "An answer"
        case .submit: kind = "A draft"
        case .judge: kind = "Needs a sitting"
        case .verify: kind = "Try it"
        }
        guard item.kind == .iris, totalQuestions > 1, !openQuestions.isEmpty else { return kind }
        return "\(kind) · \(totalQuestions - openQuestions.count + 1) of \(totalQuestions)"
    }

    private var currentQuestion: Question? { item.kind == .iris ? openQuestions.first : nil }

    @ViewBuilder private var middle: some View {
        let answersGap = (14 * Self.air).rounded()
        switch item.kind {
        case .iris:
            if let q = currentQuestion {
                VStack(alignment: .leading, spacing: answersGap) {
                    QuestionMessage(asker: q.askedBy, at: q.at, text: q.text)
                    answerList(own: !QuestionPurpose.isActedOn(q.purpose))
                }
                .id(q.id)
            } else {
                IrisReviewView(ticketId: item.ticket.id, inDecide: true)
            }
        case .pick:
            VStack(alignment: .leading, spacing: answersGap) {
                QuestionMessage(asker: item.ticket.status == .draft ? "Hatch" : "Agent on \(item.ticket.displayNumber)",
                                text: item.ticket.type == .proposal ? "These are the looks for \(ComponentsSetup.changedRole(inBody: item.ticket.body) ?? "the role"). The Designer draws them in their places. Choosing one accepts the Proposal."
                                    : item.ticket.status == .draft ? "I prepared these options. Choosing one records a decision." : "These are the options. Choosing one records a decision.")
                answerList(own: false)
            }
        case .plan:
            VStack(alignment: .leading, spacing: answersGap) {
                QuestionMessage(asker: "Agent on \(item.ticket.displayNumber)", text: "Here is my plan. Before I start, these files would change.")
                if let files = item.plan?.files {
                    Text(files.prefix(12).joined(separator: "\n") + (files.count > 12 ? "\n+ \(files.count - 12) more" : ""))
                        .font(.callout.monospaced()).foregroundStyle(.secondary)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.leading, QuestionMessage.indent)
                }
                answerList(own: false)
            }
        case .answer:
            QuestionMessage(asker: "Agent on \(item.ticket.displayNumber)", text: body_.isEmpty ? "The agent answered in words." : body_)
        case .submit:
            VStack(alignment: .leading, spacing: answersGap) {
                Text("Submit it and Iris checks it for what is missing. A draft does nothing while it waits.").foregroundStyle(.secondary)
                if !body_.isEmpty {
                    Text(body_).textSelection(.enabled).lineLimit(14)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        case .judge:
            VStack(alignment: .leading, spacing: answersGap) {
                Text(item.ticket.type == .proposal ? "Judge the options in the Stage, or accept the recommendation." : "Open it to choose a variant.")
                    .foregroundStyle(.secondary)
                if !info.recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(info.recommendations, id: \.id) { r in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(r.topicTitle).foregroundStyle(.secondary)
                                Text(r.choiceName).fontWeight(.medium)
                            }
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        case .verify:
            Text("The work is built. Try it in a Preview before it merges.").foregroundStyle(.secondary)
        }
    }

    private func answerList(own allowsOwn: Bool) -> some View {
        AnswerList(options: choices, selection: Binding(get: { selection }, set: { selected = $0 }),
                   own: allowsOwn ? $own : nil, ownFocus: $ownFocused)
            .padding(.leading, QuestionMessage.indent)
    }

    // MARK: Choices and the action bar

    /// What is selected: the owner's pick, else the recommendation, else the first answer.
    private var selection: String {
        selected ?? choices.first(where: \.recommended)?.id ?? choices.first?.id ?? "own"
    }

    private var selectableIds: [String] {
        var ids = choices.map(\.id)
        if let q = currentQuestion, !QuestionPurpose.isActedOn(q.purpose) { ids.append("own") }
        return ids
    }

    private var mainTitle: String {
        switch item.kind {
        case .iris:
            if currentQuestion != nil { return openQuestions.count > 1 ? "Answer, next question" : "Answer" }
            return stillWaiting ? "Next" : "Done, next"
        case .pick: return "Choose"
        case .plan: return selection == "back" ? "Send back" : "Approve"
        case .answer: return "Close as answered"
        case .submit: return "Submit"
        case .judge: return item.ticket.type == .proposal && !info.recommendations.isEmpty ? "Accept the recommendation" : "Open it"
        case .verify: return "Open Previews"
        }
    }

    private var refineAllowed: Bool {
        item.kind == .plan || (item.kind == .judge && item.ticket.type != .question)
    }

    /// What the main button does, for its tooltip (the hint line is hidden, DR8).
    private var startsText: String {
        switch item.kind {
        case .pick: "Records a decision"
        case .plan: "Approving lets the agent go ahead"
        case .iris: "Answers go to \(currentQuestion?.askedBy ?? "Iris"); the ticket goes on"
        case .answer: "Closes the Question"
        case .submit: "Iris checks it (a model call)"
        case .judge: item.ticket.type == .proposal ? "Accepting starts the build" : "Opens the ticket"
        case .verify: "Opens Previews"
        }
    }

    private var mainDisabled: Bool {
        selection == "own" && own.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (item.kind == .iris)
    }

    /// Pinned to the bottom of the panel, lined up with the card: Later and Note, then the one prominent button.
    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Button("Later") { later() }.buttonStyle(.glass).help("Leave it for later; it comes back at the end (Space)")
                Button("Note") { toggleNote() }.buttonStyle(.glass).help("A note on the ticket (N)")
                // Rare or final actions in a More menu (DESIGN.md, LK10). No confirmation sheet: the undo window covers it (DC4).
                if canPark || canDrop {
                    HXMenuButton(title: "More", symbol: "ellipsis") {
                        if canPark { Button("Park", systemImage: "pause") { setAside(.parked) } }
                        if canDrop { Button("Drop", systemImage: "xmark.circle", role: .destructive) { setAside(.dropped) } }
                    }
                    .help("Park (P) or Drop")
                }
                if refineAllowed {
                    Button("Refine") { session.noteOpen ? refine() : toggleNote() }.buttonStyle(.glass).help("Send back to refine with a note (R)")
                }
                if item.kind == .judge && item.ticket.type == .proposal {
                    Button("Open the Stage") { StageLauncher.shared.open(ticket: item.ticket, state: state) }.buttonStyle(.glass)
                }
                if item.kind == .pick && item.ticket.type == .proposal, let project = state.project(id: item.ticket.projectId) {
                    Button("Open the Designer") { StageLauncher.shared.openDesigner(project: project, state: state) }.buttonStyle(.glass)
                        .help("See the looks in their places and in a live window")
                }
                Spacer(minLength: 8)
                Button(mainTitle) { accept() }
                    .buttonStyle(.glassProminent)
                    .disabled(mainDisabled)
                    .help("\(startsText) (Return)")
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.horizontal, 32 + 24)
            .frame(maxWidth: Self.width + 64 + 48)
            .frame(height: 64)
            .frame(maxWidth: .infinity)
        }
    }

    private func key(_ k: String) {
        switch k {
        case "accept": if !mainDisabled { accept() }
        case "up", "down":
            let ids = selectableIds
            guard !ids.isEmpty else { return }
            let at = ids.firstIndex(of: selection) ?? 0
            let step = k == "down" ? 1 : ids.count - 1
            selected = ids[(at + step) % ids.count]
            ownFocused = selected == "own"
        case "1", "2", "3", "4":
            if let n = Int(k), n <= choices.count { selected = choices[n - 1].id }
        case "n": toggleNote()
        case "r": if refineAllowed { session.noteOpen ? refine() : toggleNote() }
        case "later": later()
        case "p": if canPark { setAside(.parked) }
        default: break
        }
    }

    private var canPark: Bool { Workflow.isAllowed(type: item.ticket.type, from: item.ticket.status, to: .parked, actor: .owner) }
    private var canDrop: Bool { Workflow.isAllowed(type: item.ticket.type, from: item.ticket.status, to: .dropped, actor: .owner) }

    /// Parks or drops the ticket instead of deciding it, after the undo window like every decision. Parked comes back
    /// with Resume on the ticket; dropped can be reopened. Nothing is deleted.
    private func setAside(_ status: Status) {
        let state = state, id = item.ticket.id
        let word = status == .parked ? "parked" : "dropped"
        session.decide(DecideOutcome(kind: .setAside, startsAgent: false), label: "\(item.ticket.displayNumber) \(word)") {
            state.perform("Could not set the ticket aside") { _ = try state.store.move(id, to: status, actor: .owner, reason: "\(word) in Decide") }
        }
    }

    private func toggleNote() {
        session.noteOpen.toggle()
        noteFocused.wrappedValue = session.noteOpen
    }

    private func later() {
        session.decide(DecideOutcome(kind: .later, startsAgent: false), label: "\(item.ticket.displayNumber) left for later. It comes back at the end.") {}
    }

    /// Answers the question on screen. The last open one goes through the undo window and the session moves on; an
    /// earlier one is saved now, and the next question takes its place on the card.
    private func answerQuestion(_ q: Question, _ text: String, agreed: Bool) {
        let store = state.store, id = item.ticket.id
        if openQuestions.count <= 1 {
            commit(agreed: agreed, startsAgent: true, label: "\(item.ticket.displayNumber) · answered") {
                _ = try store.answer(questionId: q.id, text: text)
            }
        } else {
            _ = state.perform("Could not save the answer") { try store.answer(questionId: q.id, text: text) }
            try? store.record(id, actor: "owner", kind: "decided", payload: ["kind": "iris", "agreed": .bool(agreed), "in": "decide"])
            openQuestions = (try? store.questions(ticketId: id, openOnly: true)) ?? []
            selected = nil; own = ""
            choices = openQuestions.first.map(AnswerOption.replies(for:)) ?? []
            state.refresh()
        }
    }

    private func accept() {
        switch item.kind {
        case .iris:
            if let q = currentQuestion {
                if selection == "own" {
                    let text = own.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { ownFocused = true; return }
                    answerQuestion(q, text, agreed: false)
                } else if let o = choices.first(where: { $0.id == selection }) {
                    answerQuestion(q, o.answer, agreed: o.recommended)
                } else {
                    selected = "own"; ownFocused = true
                }
                return
            }
            session.decide(DecideOutcome(kind: stillWaiting ? .later : .chose(agreed: true), startsAgent: !stillWaiting),
                           label: "\(item.ticket.displayNumber) · \(stillWaiting ? "left for later" : "done")") {}
        case .pick, .plan:
            choose(selection)
        case .answer:
            let store = state.store, id = item.ticket.id
            commit(agreed: true, startsAgent: false, label: "\(item.ticket.displayNumber) · closed as answered") {
                try store.move(id, to: .done, actor: .owner, reason: "answered")
            }
        case .submit:
            let store = state.store, id = item.ticket.id
            let state = state
            commit(agreed: true, startsAgent: true, label: "\(item.ticket.displayNumber) · submitted to Iris") {
                try store.move(id, to: .checking, actor: .owner, reason: "submitted in Decide")
                VettingBridge.start(ticketId: id, state: state)
            }
        case .judge:
            guard item.ticket.type == .proposal, !info.recommendations.isEmpty else { leave(.ticket(item.ticket.id)); return }
            var picks: [String: String] = [:]
            for r in info.recommendations { picks[r.id] = r.choiceId }
            let store = state.store, id = item.ticket.id
            commit(agreed: true, startsAgent: true, label: "\(item.ticket.displayNumber) · accepted the recommendation") {
                _ = try store.acceptProposal(ticketId: id, choices: picks)
            }
        case .verify:
            session.decide(DecideOutcome(kind: .opened, startsAgent: false), label: "Opened Previews") {}
            leave(.previews)
        }
    }

    private func choose(_ key: String) {
        guard let c = choices.first(where: { $0.id == key }) else { return }
        let agreed = c.recommended
        let store = state.store, ticket = item.ticket
        let note = session.note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.kind {
        case .pick:
            commit(agreed: agreed, startsAgent: false, label: "\(ticket.displayNumber) · \(c.title)") {
                if ticket.type == .proposal { _ = try store.decideComponentChange(ticketId: ticket.id, choice: key, reason: note.isEmpty ? nil : note) }
                else if ticket.status == .draft { _ = try store.decidePreparedQuestion(ticketId: ticket.id, choice: key, reason: note.isEmpty ? nil : note) }
                else { _ = try store.decideQuestion(ticketId: ticket.id, choice: key, reason: note.isEmpty ? nil : note) }
                // A design system question changes the system too (DC9, DS4).
                try state.applyComponentDecision(ticket: ticket, choice: key)
            }
        case .plan:
            guard let plan = item.plan else { return }
            if key == "back" && note.isEmpty { session.noteOpen = true; noteFocused.wrappedValue = true; return }
            commit(agreed: agreed, startsAgent: key == "approve", label: "\(ticket.displayNumber) · \(key == "approve" ? "plan approved" : "plan sent back")") {
                _ = try store.decidePlanReview(id: plan.id, approve: key == "approve", note: note.isEmpty ? nil : note)
            }
        default:
            break
        }
    }

    private func refine() {
        let text = session.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { session.noteOpen = true; noteFocused.wrappedValue = true; return }
        let store = state.store, ticket = item.ticket
        if item.kind == .plan, let plan = item.plan {
            refineCommit(label: "\(ticket.displayNumber) · plan sent back") { _ = try store.decidePlanReview(id: plan.id, approve: false, note: text) }
        } else if ticket.type == .proposal || ticket.type == .sketch {
            refineCommit(label: "\(ticket.displayNumber) · sent back to refine") { _ = try store.sendBackProposal(ticketId: ticket.id, reason: .changeOption, note: text) }
        }
    }

    private func saveNote() {
        let text = session.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let id = item.ticket.id
        state.perform("Could not save the note") { _ = try state.store.addNote(id, kind: .note, author: "owner", body: text) }
        session.note = ""; session.noteOpen = false; noteFocused.wrappedValue = false
    }

    /// Hands a decision to the session: it waits out the undo window, then runs through `perform` and is logged with
    /// whether it agreed with the recommendation (DC6: overruling a kind often tells Hatch its recommendations need work).
    private func commit(agreed: Bool, startsAgent: Bool, label: String, _ work: @escaping () throws -> Void) {
        let state = state, id = item.ticket.id, kind = item.kind.rawValue
        session.decide(DecideOutcome(kind: .chose(agreed: agreed), startsAgent: startsAgent), label: label) {
            state.perform("Could not save the decision") {
                try work()
                try state.store.record(id, actor: "owner", kind: "decided", payload: ["kind": .string(kind), "agreed": .bool(agreed), "in": "decide"])
            }
        }
    }

    private func refineCommit(label: String, _ work: @escaping () throws -> Void) {
        let state = state
        session.decide(DecideOutcome(kind: .refined, startsAgent: true), label: label) {
            state.perform("Could not send it back") { try work() }
        }
    }

    // MARK: Loading

    private func load() {
        let store = state.store, t = item.ticket
        switch item.kind {
        case .pick:
            let options = (try? store.questionOptions(ticketId: t.id)) ?? []
            choices = options.map { o in
                let detail = [o.detail, o.why].compactMap { $0 }.map { ".!?".contains($0.last ?? ".") ? $0 : $0 + "." }.joined(separator: " ")
                return AnswerOption(id: o.key, title: o.title, detail: detail.isEmpty ? nil : detail, gain: o.gain, cost: o.cost, recommended: o.recommended, answer: o.key)
            }
        case .plan:
            let (rec, why) = planRecommendation()
            choices = [AnswerOption(id: "approve", title: "Approve the plan", detail: rec == "approve" ? why : "The agent goes ahead with these files.", recommended: rec == "approve", answer: "approve"),
                       AnswerOption(id: "back", title: "Send it back", detail: rec == "back" ? why : "Say what to change in a note.", recommended: rec == "back", answer: "back")]
        case .iris:
            openQuestions = (try? store.questions(ticketId: t.id, openOnly: true)) ?? []
            totalQuestions = openQuestions.count
            choices = openQuestions.first.map(AnswerOption.replies(for:)) ?? []
        case .answer:
            body_ = ((try? store.notes(ticketId: t.id)) ?? []).last { $0.kind == .agent }?.body ?? ""
        case .submit:
            body_ = t.body
        case .judge:
            info = ProposalInfo.load(store: store, ticket: t)
        case .verify:
            break
        }
    }

    /// Hatch can say one useful thing about a plan for free: whether its files stay in the ticket's area.
    private func planRecommendation() -> (String, String) {
        let files = item.plan?.files ?? []
        guard let config = state.project(id: item.ticket.projectId)?.config, let area = item.ticket.area,
              config.areas.contains(where: { $0.name.caseInsensitiveCompare(area) == .orderedSame }) else {
            return ("approve", "The ticket has no area with files set, so Hatch cannot check the plan; the claim already keeps other agents off these files.")
        }
        let outside = files.filter { config.area(containing: $0)?.name.caseInsensitiveCompare(area) != .orderedSame }
        if outside.isEmpty { return ("approve", "All \(files.count) files are in \(area), the ticket's area.") }
        return ("back", "\(outside.count) of \(files.count) files are outside \(area): \(outside.prefix(3).joined(separator: ", ")). Ask why before the agent starts.")
    }

    private func checkStillWaiting() {
        guard item.kind == .iris else { return }
        let now = (try? state.store.ticket(id: item.ticket.id))?.status
        stillWaiting = now == .needsAnswers
        let open = (try? state.store.questions(ticketId: item.ticket.id, openOnly: true)) ?? []
        if open.map(\.id) != openQuestions.map(\.id) {
            openQuestions = open
            choices = open.first.map(AnswerOption.replies(for:)) ?? []
            selected = nil
        }
    }
}

// MARK: - The queue

/// One progress pill: its ticket on hover, and a click goes there when it is still open.
private struct DecidePill: View {
    let mark: DecideRun.Mark
    let item: PendingDecision
    let canGo: Bool
    let go: () -> Void
    @State private var hovering = false

    var body: some View {
        DecideSessionView.pill(mark)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { if canGo { go() } }
            .popover(isPresented: $hovering, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        DecideSessionView.pill(mark).frame(width: 28)
                        Text("\(item.ticket.displayNumber) · \(DecideSessionView.words(mark))").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.ticket.title).font(.callout.weight(.medium)).lineLimit(2)
                    if canGo { Text("Click to go there").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(12).frame(width: 280, alignment: .leading)
            }
    }
}

/// What is left, as a glass card: the open decisions (on screen, up next, left for later) to click, and what was
/// decided, dimmed. Each row has a dot in its pill's colour.
private struct DecideQueueCard: View {
    @ObservedObject var session: DecideSession
    let go: (String) -> Void

    var body: some View {
        let byId = Dictionary(session.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let marks = session.run.marks
        let open = marks.filter { if case .handled = $0.mark { return false }; return $0.mark != .setAside }
        let done = marks.filter { if case .handled = $0.mark { return true }; return $0.mark == .setAside }
        VStack(alignment: .leading, spacing: 0) {
            Text("\(session.openCount) left").font(.headline).padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(open, id: \.id) { m in if let item = byId[m.id] { row(m.mark, item, clickable: m.mark != .current) } }
                    if !done.isEmpty {
                        Text("Decided").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
                        ForEach(done, id: \.id) { m in if let item = byId[m.id] { row(m.mark, item, clickable: false).opacity(0.6) } }
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 10)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 340)
        .frame(maxHeight: 460)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
    }

    private func row(_ mark: DecideRun.Mark, _ item: PendingDecision, clickable: Bool) -> some View {
        Button { if clickable { go(item.id) } } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                DecideSessionView.pill(mark).frame(width: 28).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                Text(item.ticket.displayNumber).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.ticket.title).lineLimit(1)
                    Text(subtitle(mark, item)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(mark == .current ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(clickable || mark == .current)
    }

    /// What kind of decision it is, and where it stands when that is not just "waiting".
    private func subtitle(_ mark: DecideRun.Mark, _ item: PendingDecision) -> String {
        let kind: String
        switch item.kind {
        case .pick: kind = "Pick one"
        case .plan: kind = "Approve a plan"
        case .iris: kind = "Iris asks"
        case .answer: kind = "An answer"
        case .submit: kind = "A draft"
        case .judge: kind = "Needs a sitting"
        case .verify: kind = "Try it"
        }
        switch mark {
        case .waiting: return kind
        case .current: return kind + " · on screen"
        default: return kind + " · " + DecideSessionView.words(mark)
        }
    }
}

// MARK: - Ways in

/// The toolbar button (DC11): its own group, a badge with how many decisions wait, hidden when none do.
struct DecideToolbarButton: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Button { state.openDecide() } label: {
            Label("Decide", systemImage: "checklist")
                .labelStyle(.iconOnly)
                .overlay(alignment: .topTrailing) {
                    // The system's red badge, as on the Dock icon (DC11, the exception in DESIGN.md rule 6).
                    Text("\(state.decisionCount)")
                        .font(.system(size: 10, weight: .bold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                        .background(Color(nsColor: .systemRed), in: Capsule())
                        .offset(x: 9, y: -8)
                        .accessibilityHidden(true)
                }
        }
        .help("Decide: \(state.decisionCount) waiting (\u{21E7}\u{2318}D)")
        .accessibilityLabel("Decide, \(state.decisionCount) waiting")
    }
}

/// Iris's card at the top of her panel (DC10): how many decisions wait, how long, what kinds, and the way in.
struct DecideIrisCard: View {
    @EnvironmentObject var state: AppState
    let items: [PendingDecision]

    var body: some View {
        let new = items.filter { !DecideSeen.ids.contains($0.id) }.count
        let minutes = max(1, Int(items.reduce(0) { $0 + $1.minutes }.rounded()))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checklist").foregroundStyle(Theme.you)
                Text("\(items.count) decision\(items.count == 1 ? "" : "s") wait for you").font(.headline)
            }
            Text(kinds + " · about \(minutes) min" + (new > 0 && new < items.count ? " · \(new) new since you last decided" : ""))
                .font(.callout).foregroundStyle(.secondary)
            Button { state.openDecide() } label: { Label("Decide", systemImage: "play.fill") }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kinds: String {
        let quick = items.filter(\.isQuick).count, sitting = items.count - quick
        var parts: [String] = []
        if quick > 0 { parts.append("\(quick) quick") }
        if sitting > 0 { parts.append("\(sitting) for the Stage or a Preview") }
        return parts.joined(separator: ", ")
    }
}
