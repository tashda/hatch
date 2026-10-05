import SwiftUI
import HatchCore

/// The inspector (decision B4, reworked): Iris's home. It lists the tickets she is checking and the ones
/// waiting for the owner's answer, with approve, reject and note on each. A question field sits at the bottom.
struct IrisPanel: View {
    @EnvironmentObject var state: AppState
    @State private var checking: [Ticket] = []
    @State private var waiting: [Ticket] = []
    /// Everything waiting for the owner: one card and the way into Decide (DC10).
    @State private var decisions: [PendingDecision] = []

    /// On a ticket page that ticket comes first, so its review is always one glance away.
    private var focusId: Int? {
        if case .ticket(let id) = state.route { return id }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.route == .newTicket {
                HatchCheckPanel(similar: state.hatchCheck?.similar ?? [], specs: state.hatchCheck?.specs ?? [],
                                hasInput: state.hatchCheck?.hasInput ?? false, onLink: { state.hatchCheck?.onLink($0, $1) })
                    .floatingCard()
                    .padding(.bottom, 8)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // First, whatever else is open: the way into Decide, whenever anything waits (DC10).
                    if !decisions.isEmpty { DecideIrisCard(items: decisions).floatingCard() }
                    if state.route == .desk, let top = state.inspectorTop {
                        top.floatingCard().transition(.move(edge: .top).combined(with: .opacity))
                    }
                    // Review cards fold into the Decide card, except the one for the ticket on screen.
                    let shown = waiting.filter { $0.id == focusId }
                    if !shown.isEmpty { section("This ticket", count: shown.count) { ForEach(shown) { reviewCard($0) } } }
                    if !checking.isEmpty { section("Checking now", count: checking.count) { ForEach(checking) { checkingCard($0) } } }
                    if state.projects.isEmpty { addProject }
                    else if decisions.isEmpty && checking.isEmpty { quiet }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 4)
                .animation(.snappy(duration: 0.25), value: state.inspectorTop == nil)
            }
            .scrollClipDisabled()
            }
        }
        .autoReload(every: 3) { load() }
    }

    // MARK: Parts

    /// With no project there is nothing for Iris to review, so the first card points at the one thing to do.
    private var addProject: some View {
        card {
            Text("Add a project")
                .font(.subheadline.weight(.semibold))
            Text("Iris reviews a project's tickets. Set one up to start.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set up a project") { state.showAddProject = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
    }

    private var quiet: some View {
        card {
            Text("Nothing to review")
                .font(.subheadline.weight(.semibold))
            Text("New tickets are checked here. Iris compares each with other tickets and the Spec, then asks before any work starts.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<C: View>(_ title: String, count: Int, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title) · \(count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .floatingCard()
    }

    private func ticketHeader(_ t: Ticket) -> some View {
        Button { state.open(t) } label: {
            HStack(spacing: 6) {
                Text(t.displayNumber).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Text(t.title).font(.callout.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .help("Open \(t.displayNumber)")
    }

    private func reviewCard(_ t: Ticket) -> some View {
        card {
            ticketHeader(t)
            // Approve, reject and apply happen inside the review: each suggestion carries its own recommendation.
            IrisReviewView(ticketId: t.id)
            NoteField(ticketId: t.id)
        }
    }

    private func checkingCard(_ t: Ticket) -> some View {
        card {
            ticketHeader(t)
            IrisReviewView(ticketId: t.id)
        }
    }

    // MARK: Data

    private func load() {
        func list(_ status: Status) -> [Ticket] {
            var all = (try? state.store.tickets(TicketFilter(projectId: state.projectFilterId, statuses: [status]))) ?? []
            if let f = focusId, let i = all.firstIndex(where: { $0.id == f }) { all.insert(all.remove(at: i), at: 0) }
            return all
        }
        checking = list(.checking)
        waiting = list(.needsAnswers)
        decisions = (try? state.store.pendingDecisions(projectId: state.projectFilterId)) ?? []
    }
}

/// A short note to Iris or the thread, saved on the ticket.
private struct NoteField: View {
    @EnvironmentObject var state: AppState
    let ticketId: Int
    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            TextField("Add a note", text: $text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .onSubmit(save)
            Button("Add", action: save)
                .controlSize(.small)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .hatchMark("NoteField")
    }

    private func save() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        state.perform("Could not save the note") {
            _ = try state.store.addNote(ticketId, kind: .note, author: "owner", body: body)
        }
        text = ""
    }
}
