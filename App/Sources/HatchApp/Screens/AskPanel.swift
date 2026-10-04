import SwiftUI
import HatchCore

/// Ask Hatch (decision B4): a right-side panel that keeps the current ticket as context.
/// The exchange is also saved to the ticket thread. The model chosen for Ask in Settings runs in a background Task, never on the main thread.
struct AskPanel: View {
    @EnvironmentObject var state: AppState
    /// Inside the Iris panel: no header, no suggested questions, no extra padding.
    var embedded = false

    struct Message: Identifiable {
        let id = UUID()
        let fromOwner: Bool
        let text: String
    }

    @State private var input = ""
    @State private var messages: [Message] = []
    @State private var running = false
    @State private var errorText: String?
    @State private var messagesTicketId: Int?

    private var currentTicket: Ticket? {
        guard let id = state.selectedTicketId else { return nil }
        if case .ticket = state.route {
            let t: Ticket? = try? state.store.ticket(id: id)
            return t
        }
        if state.route == .desk {
            let t: Ticket? = try? state.store.ticket(id: id)
            return t
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            if !embedded { header }
            conversation
            composer
        }
        .padding(embedded ? 0 : 12)
        .background(embedded ? Color.clear : Color.secondary.opacity(0.045))
        .onChange(of: currentTicket?.id) { _, newValue in
            if newValue != messagesTicketId {
                messages = []
                errorText = nil
                messagesTicketId = newValue
            }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 10) {
            Image("IrisIcon")
                .resizable().scaledToFit().frame(width: 20, height: 20)
                .foregroundStyle(Theme.agent)
                .frame(width: 34, height: 34)
                .background(Theme.agentBackground, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask Hatch").font(.headline)
                if let t = currentTicket {
                    Text("With \(t.displayNumber) · \(t.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("An agent beside your work").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { state.showAskPanel = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Close (\u{2325}\u{2318}A)")
        }
    }

    private var conversation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if messages.isEmpty && !running && errorText == nil && !embedded {
                    emptyState
                }
                ForEach(messages) { m in bubble(m) }
                if running {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Hatch is thinking…").font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let e = errorText { errorView(e) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(currentTicket == nil ? "Ready when you are" : "Ask about this ticket")
                .font(.headline)
            Text(currentTicket == nil
                 ? "Ask what to work on next, or open a ticket to give Hatch its context. Questions without a ticket are not saved."
                 : "Explore an option, clarify a decision, or ask what should happen next. This exchange is saved to the ticket thread.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().padding(.vertical, 3)
            Text("Suggested questions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(suggestedQuestions, id: \.self) { question in
                Button {
                    input = question
                } label: {
                    HStack(spacing: 8) {
                        Text(question)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.left")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.35)))
    }

    private var suggestedQuestions: [String] {
        currentTicket == nil
            ? ["What needs my attention?", "What are agents working on?"]
            : ["What should I do next?", "What decisions are still open?"]
    }

    private func bubble(_ m: Message) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(m.fromOwner ? "You" : "Hatch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(m.fromOwner ? Color.secondary : Theme.agent)
            Text(m.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(m.fromOwner ? Color.secondary.opacity(0.08) : Theme.agentBackground,
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HXChip(text: "Could not answer", turn: .you)
            Text(text).font(.callout).textSelection(.enabled)
        }
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("Ask Hatch a question", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .onSubmit { send() }
            Button { send() } label: { Label(running ? "Waiting..." : "Send", systemImage: "paperplane") }
                .buttonStyle(.glassProminent)
                .disabled(running || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.5)))
    }

    // MARK: Sending

    private func contextText(_ t: Ticket) -> String {
        var lines: [String] = []
        lines.append("Ticket \(t.displayNumber): \(t.title)")
        lines.append("Type: \(t.type.displayName). Status: \(t.status.displayName).")
        if !t.body.isEmpty { lines.append("Description:\n" + String(t.body.prefix(3000))) }
        let questions = (try? state.store.questions(ticketId: t.id, openOnly: true)) ?? []
        if !questions.isEmpty {
            lines.append("Open questions:\n" + questions.map { "- " + $0.text }.joined(separator: "\n"))
        }
        let notes = (try? state.store.notes(ticketId: t.id)) ?? []
        let recent = notes.suffix(6)
        if !recent.isEmpty {
            lines.append("Recent thread:\n" + recent.map { "\($0.author): \(String($0.body.prefix(400)))" }.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n\n")
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !running else { return }
        let ticket = currentTicket
        var prompt = "You are helping the owner of a software project use Hatch, a ticket and design-decision tool. Answer briefly and plainly.\n\n"
        if let ticket { prompt += "Context:\n" + contextText(ticket) + "\n\n" }
        prompt += "Question: " + question
        messages.append(Message(fromOwner: true, text: question))
        messagesTicketId = ticket?.id
        input = ""
        errorText = nil
        running = true
        let store = state.store, context = state.agentContext
        Task {
            do {
                let answer = try await HXAskAdapter.ask(prompt: prompt, store: store, context: context)
                messages.append(Message(fromOwner: false, text: answer.text))
                save(ticket: ticket, question: question, answer: answer)
                recordCost(ticket: ticket, answer: answer)
            } catch {
                errorText = "\(error)"
            }
            running = false
        }
    }

    private func save(ticket: Ticket?, question: String, answer: HXAskAdapter.Answer) {
        guard let ticket else { return }
        state.perform("Save to thread") {
            try state.store.addNote(ticket.id, kind: .note, author: "owner", body: "Asked \(answer.author): " + question)
            try state.store.addNote(ticket.id, kind: .agent, author: answer.author, body: answer.text)
        }
    }

    private func recordCost(ticket: Ticket?, answer: HXAskAdapter.Answer) {
        state.perform("Record cost") {
            let runId = try state.store.startRun(ticketId: ticket?.id, agent: "ask", step: "ask with \(answer.label)")
            try state.store.endRun(runId, tokensIn: answer.tokensIn, tokensOut: answer.tokensOut, outcome: "ok")
        }
    }
}
