import SwiftUI
import HatchCore

/// One entry in the merged timeline of notes, questions, answers and events (decision F3).
struct ThreadItem: Identifiable {
    enum Content {
        case note(Note)
        case question(Question)
        case answer(Question)
        case event(Event)
    }
    let id: String
    let at: Date
    let content: Content
}

/// Thread: one timeline with filter toggles, and a composer with three message kinds (decisions F3, F4).
struct TicketThreadTab: View {
    let ticket: Ticket
    /// The message kind to start with, so "Send instruction" on the Work tab lands on Instruction (decision I5).
    var startKind: NoteKind = .note
    @EnvironmentObject var state: AppState

    @State private var items: [ThreadItem] = []
    @State private var showMessages = true
    @State private var showQuestions = true
    @State private var showEvents = false
    @State private var kind: NoteKind = .note
    @State private var draft = ""

    private var visible: [ThreadItem] {
        items.filter { item in
            switch item.content {
            case .note: return showMessages
            case .question, .answer: return showQuestions
            case .event: return showEvents
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterRow
            timeline
            composer
        }
        .autoReload(every: 4) { load() }
        .onAppear { kind = startKind }
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            ThreadFilterChip(title: "Messages", isOn: $showMessages)
            ThreadFilterChip(title: "Questions", isOn: $showQuestions)
            ThreadFilterChip(title: "Events", isOn: $showEvents)
            Spacer()
            Text(Format.count(visible.count, "entry").replacingOccurrences(of: "entrys", with: "entries"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if visible.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.bubble.right").font(.title2).foregroundStyle(.tertiary)
                            Text("Nothing here yet").font(.callout.weight(.semibold))
                            Text("Add a note, ask a question or give an instruction below.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                    ForEach(visible) { item in
                        ThreadRow(item: item)
                            .id(item.id)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: visible.count) { _, _ in
                proxy.scrollTo("end", anchor: .bottom)
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    // MARK: Composer

    private static let kinds: [NoteKind] = [.note, .ask, .instruction]

    private func kindTitle(_ k: NoteKind) -> String {
        switch k {
        case .ask: return "Ask"
        case .instruction: return "Instruction"
        default: return "Note"
        }
    }

    private var kindHelp: String {
        switch kind {
        case .ask: return "Expects an answer and moves the turn to the agent."
        case .instruction: return "Changes the work. On a Proposal it asks for a new revision."
        default: return "Adds context. Nobody has to act on it."
        }
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// A floating glass composer: kind chips on top, a plain growing text field, and a round send button.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Self.kinds, id: \.self) { k in
                    ThreadKindChip(title: kindTitle(k), selected: kind == k) { kind = k }
                }
                Text(kindHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Write a \(kindTitle(kind).lowercased())…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...8)
                    .padding(.vertical, 6)
                Button { send() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(canSend ? Color.white : Color.secondary)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(canSend ? .accentColor : .gray)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
                .help("Send \(kindTitle(kind)) (\u{2318}\u{21A9})")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }

    private func send() {
        let text = draft
        let id = ticket.id
        let chosen = kind
        let ok: Note? = state.perform("Could not send the message") { try state.store.addNote(id, kind: chosen, author: "owner", body: text) }
        if ok != nil { draft = "" }
    }

    // MARK: Data

    private func load() {
        let store = state.store
        let id = ticket.id
        var out: [ThreadItem] = []
        for note in (try? store.notes(ticketId: id)) ?? [] {
            out.append(ThreadItem(id: "n\(note.id)", at: note.at, content: .note(note)))
        }
        for q in (try? store.questions(ticketId: id)) ?? [] {
            out.append(ThreadItem(id: "q\(q.id)", at: q.at, content: .question(q)))
            if q.answer != nil, let answeredAt = q.answeredAt {
                out.append(ThreadItem(id: "a\(q.id)", at: answeredAt, content: .answer(q)))
            }
        }
        let skip: Set<String> = ["note", "question", "answer"]
        for e in (try? store.events(ticketId: id)) ?? [] where !skip.contains(e.kind) {
            out.append(ThreadItem(id: "e\(e.id)", at: e.at, content: .event(e)))
        }
        out.sort { $0.at < $1.at }
        if out.map({ $0.id }) != items.map({ $0.id }) { items = out }
    }
}

struct ThreadRow: View {
    let item: ThreadItem

    var body: some View {
        Group {
            switch item.content {
            case .note(let note): NoteBubble(note: note)
            case .question(let q): QuestionBubble(question: q)
            case .answer(let q): AnswerBubble(question: q)
            case .event(let e): EventLine(event: e)
            }
        }
        .hatchMark("ThreadRow")
    }
}

/// A rounded toggle for the thread filter: glass when off, tinted when on.
struct ThreadFilterChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(title).font(.callout.weight(isOn ? .semibold : .regular)).padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isOn ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: Capsule())
        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        .animation(.easeOut(duration: 0.12), value: isOn)
        .hatchMark("ThreadFilterChip")
    }
}

struct ThreadKindChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.callout.weight(selected ? .semibold : .regular)).padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(selected ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .animation(.easeOut(duration: 0.12), value: selected)
        .hatchMark("ThreadKindChip")
    }
}

/// A small round avatar for the author of a thread entry.
struct ThreadAvatar: View {
    let fromOwner: Bool
    var symbol: String? = nil
    /// Iris gets her own mark; other agents keep the generic one.
    var isIris = false

    var body: some View {
        Group {
            if isIris && symbol == nil {
                Image("IrisIcon").resizable().scaledToFit().frame(width: 17, height: 17)
            } else {
                Image(systemName: symbol ?? (fromOwner ? "person.fill" : "sparkles"))
                    .font(.system(size: 12, weight: .semibold))
            }
        }
            // Iris is drawn in the label colour: teal means an agent is working, and she is not one (DESIGN.md).
            .foregroundStyle(fromOwner ? Theme.you : (isIris ? Color.primary : Theme.agent))
            .frame(width: 28, height: 28)
            .background((fromOwner ? Theme.youBackground : (isIris ? Color.secondary.opacity(0.12) : Theme.agentBackground)), in: Circle())
            .hatchMark("ThreadAvatar")
    }
}

/// One message: an avatar and a soft bubble. Yours sit on the right, the agents' on the left.
private struct ThreadBubble<Body: View>: View {
    let fromOwner: Bool
    let name: String
    let detail: String?
    let at: Date?
    var symbol: String? = nil
    var tinted = false
    @ViewBuilder let content: () -> Body

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if fromOwner { Spacer(minLength: 60) } else { ThreadAvatar(fromOwner: false, symbol: symbol, isIris: name.lowercased().hasPrefix("iris")) }
            VStack(alignment: fromOwner ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.tertiary) }
                    if let at { Text(Format.ago(at)).font(.caption).foregroundStyle(.tertiary) }
                }
                content()
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(bubbleFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        if tinted { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.agent.opacity(0.25)) }
                    }
            }
            .frame(maxWidth: 560, alignment: fromOwner ? .trailing : .leading)
            if fromOwner { ThreadAvatar(fromOwner: true) } else { Spacer(minLength: 60) }
        }
        .hatchMark("ThreadBubble")
    }

    private var bubbleFill: AnyShapeStyle {
        if fromOwner { return AnyShapeStyle(Color.accentColor.opacity(0.14)) }
        if tinted { return AnyShapeStyle(Theme.agentBackground.opacity(0.7)) }
        return AnyShapeStyle(Color.secondary.opacity(0.09))
    }
}

struct NoteBubble: View {
    let note: Note

    private var fromOwner: Bool { note.author == "owner" }

    private var kindLabel: String? {
        switch note.kind {
        case .ask: return "Ask"
        case .instruction: return "Instruction"
        case .agent: return nil
        case .system: return "System"
        case .comment: return "Comment"
        case .note: return nil
        }
    }

    var body: some View {
        ThreadBubble(fromOwner: fromOwner, name: fromOwner ? "You" : note.author, detail: kindLabel, at: note.at) {
            Text(note.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .hatchMark("NoteBubble")
    }
}

struct QuestionBubble: View {
    let question: Question

    var body: some View {
        ThreadBubble(fromOwner: false, name: "\(question.askedBy) asks", detail: question.isOpen ? "Open" : nil,
                     at: question.at, symbol: "questionmark", tinted: true) {
            Text(question.text).fixedSize(horizontal: false, vertical: true)
        }
        .hatchMark("QuestionBubble")
    }
}

struct AnswerBubble: View {
    let question: Question

    var body: some View {
        ThreadBubble(fromOwner: true, name: "You answered", detail: nil, at: question.answeredAt) {
            Text(question.answer ?? "").textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .hatchMark("AnswerBubble")
    }
}

/// An event is a quiet centred line, not a message.
struct EventLine: View {
    let event: Event

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: EventText.symbol(event)).font(.caption2)
            Text(event.actor).font(.caption.weight(.semibold))
            Text(EventText.describe(event)).font(.caption).lineLimit(1)
            Text(Format.ago(event.at)).font(.caption).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.07), in: Capsule())
        .frame(maxWidth: .infinity)
        .hatchMark("EventLine")
    }
}
