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
                    summary
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .animation(.snappy(duration: 0.28), value: session.index)
            .overlay(alignment: .bottom) { toast.padding(.bottom, 18) }
            keyHints.padding(.bottom, 12)
        }
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
            HStack(spacing: 4) {
                ForEach(Array(session.items.enumerated()), id: \.offset) { i, item in
                    Capsule().fill(pillStyle(i, item)).frame(width: 22, height: 5)
                        .overlay(Capsule().strokeBorder(.secondary, lineWidth: session.outcome(item.id) == .later && i >= session.index ? 1 : 0))
                }
            }
            Spacer()
            Text(session.current == nil ? "All clear" : "\(session.remaining) left · about \(session.minutesLeft) min")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Button("Done") { close(to: nil) }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var title: String {
        let project = (state.selectedProject ?? (state.projects.count == 1 ? state.projects.first : nil))?.name
        let base = request.area.map { "Decide · \($0)" } ?? "Decide"
        return project.map { "\(base) · \($0)" } ?? base
    }

    private func pillStyle(_ i: Int, _ item: PendingDecision) -> Color {
        if i == session.index { return Theme.you }
        if i < session.index { return session.outcome(item.id) == .later ? .clear : .secondary }
        return Color.secondary.opacity(0.25)
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

    private var keyHints: some View {
        HStack(spacing: 16) {
            hint("↵", "accept the recommendation"); hint("1–4  ← →", "choose"); hint("N", "note"); hint("R", "refine")
            hint("Space", "later"); hint("Z", "undo"); hint("esc", "done")
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.caption.monospaced()).padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
        }
    }

    private var summary: some View {
        let clearedAll = session.run.later == 0
        let streak = DecideStreak.days(state.store)
        return VStack(spacing: 14) {
            Text(session.items.isEmpty ? "Nothing waits for you" : clearedAll ? "All decided" : "Done for now")
                .font(.largeTitle.weight(.bold))
            if !session.items.isEmpty {
                Text("\(session.run.agreed + session.run.ownCall + session.run.refined) decided\(session.run.later > 0 ? ", \(session.run.later) left for later" : ""). "
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
                .buttonStyle(.glassProminent).controlSize(.large).keyboardShortcut(.defaultAction)
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
        if noteFocused { return .ignored }
        if press.characters.lowercased() == "z" { session.undo(); return .handled }
        guard session.current != nil else { return .ignored }
        switch press.key {
        case .return: NotificationCenter.default.post(name: .hxDecideKey, object: "accept"); return .handled
        case .leftArrow: NotificationCenter.default.post(name: .hxDecideKey, object: "left"); return .handled
        case .rightArrow: NotificationCenter.default.post(name: .hxDecideKey, object: "right"); return .handled
        case .space: NotificationCenter.default.post(name: .hxDecideKey, object: "later"); return .handled
        default: break
        }
        let c = press.characters.lowercased()
        if ["1", "2", "3", "4", "n", "r"].contains(c) { NotificationCenter.default.post(name: .hxDecideKey, object: c); return .handled }
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

/// A choice on a card: what it is called, what it gains and costs, and what happens when it is picked.
private struct DecideChoice: Identifiable {
    let id: String
    let title: String
    var detail: String? = nil
    var gain: String? = nil
    var cost: String? = nil
    var swatch: Color? = nil
}

private struct DecideCard: View {
    @EnvironmentObject var state: AppState
    let item: PendingDecision
    @ObservedObject var session: DecideSession
    var noteFocused: FocusState<Bool>.Binding
    let leave: (Route) -> Void

    @State private var choices: [DecideChoice] = []
    @State private var recommended: String?
    @State private var why = ""
    @State private var body_ = ""
    @State private var info = ProposalInfo()
    @State private var openQuestions: [Question] = []
    @State private var stillWaiting = true

    var body: some View {
        // The card is as tall as its content; only a card taller than the window scrolls.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: 700)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .padding(.vertical, 12)
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .hxDecideKey)) { key($0.object as? String ?? "") }
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
            VStack(alignment: .leading, spacing: 14) {
                header
                middle
                if let recommended, !why.isEmpty {
                    (Text("★ Recommended: \(choices.first { $0.id == recommended }?.title ?? recommended). ").fontWeight(.semibold) + Text(why))
                        .font(.callout)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                if session.noteOpen {
                    TextField(refineAllowed ? "Note for the agent. Return sends it back to refine." : "Note on the ticket. Return saves it.",
                              text: $session.note, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...4)
                        .focused(noteFocused)
                        .onSubmit { refineAllowed ? refine() : saveNote() }
                        .onExitCommand { session.noteOpen = false; noteFocused.wrappedValue = false }
                }
                actions
            }
            .padding(22)
    }

    // MARK: Header and middle

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("Your turn", systemImage: "circle.fill").labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.you).imageScale(.small)
                Text("\(item.ticket.displayNumber) · \(item.ticket.type.displayName)").font(.caption).foregroundStyle(.secondary)
                Text(kindLabel).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 1).background(.quaternary, in: Capsule())
                Spacer()
                Button("Open") { leave(.ticket(item.ticket.id)) }.buttonStyle(.borderless).font(.caption)
            }
            Text(item.ticket.title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(ask).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case .pick: choices.count == 2 ? "This or that" : "Pick one"
        case .plan: "Approve a plan"
        case .iris: "Iris asks"
        case .answer: "An answer"
        case .submit: "A draft"
        case .judge: "Needs a sitting"
        case .verify: "Try it"
        }
    }

    private var ask: String {
        switch item.kind {
        case .pick: item.ticket.status == .draft ? "Hatch prepared these options. Choosing one records a decision." : "The agent offers these options. Choosing one records a decision."
        case .plan: "The agent's plan waits for you: \(item.plan?.reason ?? "")."
        case .iris: "Iris checked this ticket and needs you before an agent starts."
        case .answer: "The agent answered in words. Close the Question if the answer works for you."
        case .submit: "Submit it and Iris checks it for what is missing. A draft does nothing while it waits."
        case .judge: item.ticket.type == .proposal ? "Judge the options in the Stage, or accept the recommendation." : "Open it to choose a variant."
        case .verify: "The work is built. Try it in a Preview before it merges."
        }
    }

    @ViewBuilder private var middle: some View {
        switch item.kind {
        case .pick, .plan:
            if item.kind == .plan, let files = item.plan?.files {
                Text(files.prefix(12).joined(separator: "\n") + (files.count > 12 ? "\n+ \(files.count - 12) more" : ""))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: choices.count > 2 ? 180 : 240), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { i, c in choiceTile(c, number: i + 1) }
            }
        case .iris:
            IrisReviewView(ticketId: item.ticket.id)
        case .answer, .submit:
            if !body_.isEmpty {
                Text(body_).textSelection(.enabled).lineLimit(14)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        case .judge:
            if !info.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(info.recommendations, id: \.id) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(r.topicTitle).foregroundStyle(.secondary)
                            Text(r.choiceName).fontWeight(.medium)
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        case .verify:
            EmptyView()
        }
    }

    private func choiceTile(_ c: DecideChoice, number: Int) -> some View {
        Button { choose(c.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("\(number)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    if c.id == recommended { Text("★ Recommended").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let swatch = c.swatch { RoundedRectangle(cornerRadius: 5).fill(swatch).frame(width: 18, height: 18) }
                    Text(c.title).fontWeight(.semibold).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                if let d = c.detail { Text(d).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
                if let g = c.gain { Label(g, systemImage: "plus").font(.callout).labelStyle(DecideLineStyle()) }
                if let k = c.cost { Label(k, systemImage: "minus").font(.callout).foregroundStyle(.secondary).labelStyle(DecideLineStyle()) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: session.highlight == c.id ? 2 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private var primaryTitle: String {
        switch item.kind {
        case .pick, .plan: "Accept recommendation"
        case .iris: openQuestions.contains { !$0.suggestions.isEmpty } ? "Accept Iris's suggested answers" : (stillWaiting ? "Next" : "Done, next")
        case .answer: "Close as answered"
        case .submit: "Submit"
        case .judge: item.ticket.type == .proposal && !info.recommendations.isEmpty ? "Accept the recommendation" : "Open it"
        case .verify: "Open Previews"
        }
    }

    private var refineAllowed: Bool {
        item.kind == .plan || (item.kind == .judge && item.ticket.type != .question)
    }

    private var startsText: String {
        switch item.kind {
        case .pick: "Records a decision"
        case .plan: "Approving lets the agent go ahead"
        case .iris: "Answers go to Iris; the ticket goes on"
        case .answer: "Closes the Question"
        case .submit: "Iris checks it (a model call)"
        case .judge: item.ticket.type == .proposal ? "Accepting starts the build" : "Opens the ticket"
        case .verify: "Opens Previews"
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { accept() } label: { Label(primaryTitle, systemImage: "return") }
                .buttonStyle(.glassProminent)
            if item.kind == .judge && item.ticket.type == .proposal {
                Button { StageLauncher.shared.open(ticket: item.ticket, state: state) } label: { Label("Open the Stage", systemImage: "rectangle.on.rectangle") }
                    .buttonStyle(.glass)
            }
            Button { toggleNote() } label: { Label("Note", systemImage: "square.and.pencil") }.buttonStyle(.glass).help("Note (N)")
            if refineAllowed {
                Button { session.noteOpen ? refine() : toggleNote() } label: { Label("Refine", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.glass).help("Send back to refine (R)")
            }
            Button { later() } label: { Label("Later", systemImage: "arrow.turn.down.right") }.buttonStyle(.glass).help("Later (Space)")
            Spacer(minLength: 8)
            Text(startsText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func key(_ k: String) {
        switch k {
        case "accept": if let h = session.highlight { choose(h) } else { accept() }
        case "left", "right":
            guard !choices.isEmpty else { return }
            let ids = choices.map(\.id)
            let at = ids.firstIndex(of: session.highlight ?? recommended ?? ids[0]) ?? 0
            session.highlight = ids[(at + (k == "right" ? 1 : ids.count - 1)) % ids.count]
        case "1", "2", "3", "4":
            if let n = Int(k), n <= choices.count { choose(choices[n - 1].id) }
        case "n": toggleNote()
        case "r": if refineAllowed { session.noteOpen ? refine() : toggleNote() }
        case "later": later()
        default: break
        }
    }

    private func toggleNote() {
        session.noteOpen.toggle()
        noteFocused.wrappedValue = session.noteOpen
    }

    private func later() {
        session.decide(DecideOutcome(kind: .later, startsAgent: false), label: "\(item.ticket.displayNumber) left for later. It comes back at the end.") {}
    }

    private func accept() {
        switch item.kind {
        case .pick, .plan:
            if let r = recommended { choose(r) }
        case .iris:
            let pairs = openQuestions.compactMap { q in q.suggestions.first.map { (q.id, $0) } }
            if pairs.isEmpty {
                session.decide(DecideOutcome(kind: stillWaiting ? .later : .chose(agreed: true), startsAgent: !stillWaiting),
                               label: "\(item.ticket.displayNumber) · \(stillWaiting ? "left for later" : "done")") {}
                return
            }
            let store = state.store, id = item.ticket.id
            commit(agreed: true, startsAgent: true, label: "\(item.ticket.displayNumber) · answered with Iris's suggestions") {
                for (qid, text) in pairs { _ = try store.answer(questionId: qid, text: text) }
                try store.record(id, actor: "owner", kind: "decide", payload: ["kind": "iris", "agreed": true])
            }
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
        let agreed = key == recommended
        let store = state.store, ticket = item.ticket
        let note = session.note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.kind {
        case .pick:
            commit(agreed: agreed, startsAgent: false, label: "\(ticket.displayNumber) · \(c.title)") {
                if ticket.status == .draft { _ = try store.decidePreparedQuestion(ticketId: ticket.id, choice: key, reason: note.isEmpty ? nil : note) }
                else { _ = try store.decideQuestion(ticketId: ticket.id, choice: key, reason: note.isEmpty ? nil : note) }
            }
        case .plan:
            guard let plan = item.plan else { return }
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
            choices = options.map { DecideChoice(id: $0.key, title: $0.title, detail: $0.detail, gain: $0.gain, cost: $0.cost) }
            recommended = options.first(where: \.recommended)?.key
            why = options.first(where: \.recommended)?.why ?? ""
        case .plan:
            choices = [DecideChoice(id: "approve", title: "Approve the plan", detail: "The agent goes ahead with these files"),
                       DecideChoice(id: "back", title: "Send it back", detail: "Say what to change in a note")]
            (recommended, why) = planRecommendation()
        case .iris:
            openQuestions = (try? store.questions(ticketId: t.id, openOnly: true)) ?? []
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
        openQuestions = (try? state.store.questions(ticketId: item.ticket.id, openOnly: true)) ?? []
    }
}

/// A gain or cost line: a small plus or minus, then the text.
private struct DecideLineStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(width: 10)
            configuration.title
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
                .buttonStyle(.glassProminent)
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
