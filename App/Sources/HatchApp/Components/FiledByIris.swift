import SwiftUI
import HatchCore

/// What Iris set when she filed a ticket, as one row of tokens under the title, each a pop-up to change it (decision
/// WF-T1, the token row picked on the Decide redesign canvas). Nothing she set is final: before work starts the owner
/// changes the path, area, priority or verification in one click, and the owner's own words are one click away.
struct FiledByIrisTokens: View {
    @EnvironmentObject var state: AppState
    let ticketId: Int

    @State private var ticket: Ticket?
    @State private var filing: (at: Date, by: String, fields: [String: JSONValue])?
    @State private var showWords = false

    var body: some View {
        // A stack, not a Group: an empty Group never appears, so it would never load.
        VStack(alignment: .leading, spacing: 0) {
            if let ticket, let filing {
                row(ticket, filing)
            }
        }
        .autoReload(every: 4) { load() }
    }

    private var canChange: Bool {
        guard let t = ticket else { return false }
        return [.draft, .checking, .needsAnswers, .ready].contains(t.status)
    }

    private func row(_ t: Ticket, _ f: (at: Date, by: String, fields: [String: JSONValue])) -> some View {
        FlowLayout(spacing: 6) {
            Label(t.type.displayName, systemImage: Theme.symbol(for: t.type))
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9).frame(height: 22)
                .background(.quaternary, in: Capsule())
            pathMenu(t)
            priorityMenu(t)
            areaMenu(t)
            verifyMenu(t)
            if let moved = f.fields["project"]?["to"]?.stringValue, let p = state.projects.first(where: { $0.key == moved }) {
                Text("Moved to \(p.name)").font(.caption).foregroundStyle(.secondary).frame(height: 22)
            }
            if let originalTitle = t.originalTitle {
                Button("Your words") { showWords.toggle() }
                    .buttonStyle(.link).font(.caption).frame(height: 22)
                    .popover(isPresented: $showWords, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(originalTitle).font(.callout.weight(.semibold))
                            if let body = t.originalBody, !body.isEmpty, body != originalTitle {
                                Text(body).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .textSelection(.enabled)
                        .frame(width: 340, alignment: .leading)
                        .padding(14)
                    }
            }
            Text("Filed by \(f.by == "owner" ? "you" : f.by)\(canChange ? "" : " · work has started")")
                .font(.caption).foregroundStyle(.secondary).frame(height: 22)
        }
    }

    /// One token: a quiet label, the value, and the system pop-up arrow.
    private func token(_ label: String?, _ value: String) -> some View {
        HStack(spacing: 4) {
            if let label { Text(label).foregroundStyle(.secondary) }
            Text(value)
        }
    }

    private func pathMenu(_ t: Ticket) -> some View {
        Menu {
            ForEach(WorkPath.allCases.filter { $0 != .split }, id: \.self) { p in
                Button(p.displayName) { change { _ = try state.store.setPath(t.id, to: p, actor: .owner) } }
            }
        } label: { token(nil, t.path?.displayName ?? "No path") }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .font(.caption.weight(.medium))
        .fixedSize()
        .disabled(!canChange)
    }

    private func areaMenu(_ t: Ticket) -> some View {
        let areas = state.project(id: t.projectId)?.config?.areas.map(\.name) ?? []
        return Menu {
            ForEach(areas, id: \.self) { a in
                Button(a) { change { _ = try state.store.update(t.id, actor: .owner, area: .some(a)) } }
            }
            Divider()
            Button("None") { change { _ = try state.store.update(t.id, actor: .owner, area: .some(nil)) } }
        } label: { token("Area", t.area ?? "None") }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .font(.caption.weight(.medium))
        .fixedSize()
        .disabled(!canChange || areas.isEmpty)
    }

    private func priorityMenu(_ t: Ticket) -> some View {
        Menu {
            ForEach([TicketPriority.urgent, TicketPriority.high, TicketPriority.normal, TicketPriority.low], id: \.self) { p in
                Button(TicketPriority.name(p)) { change { _ = try state.store.update(t.id, actor: .owner, priority: p) } }
            }
        } label: { token("Priority", TicketPriority.name(t.priority)) }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .font(.caption.weight(.medium))
        .fixedSize()
        .disabled(t.status.isTerminal)
    }

    private func verifyMenu(_ t: Ticket) -> some View {
        Menu {
            ForEach(VerifyKind.allCases, id: \.self) { v in
                Button(v.displayName) { change { _ = try state.store.setVerify(t.id, to: v, actor: .owner) } }
            }
        } label: { token("Verify", (t.verify ?? t.path?.defaultVerify ?? .preview).displayName) }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .font(.caption.weight(.medium))
        .fixedSize()
        .disabled(t.status.isTerminal)
    }

    private func change(_ action: () throws -> Void) {
        _ = state.perform("Could not change it") { try action() }
        load()
        state.refresh()
    }

    private func load() {
        ticket = try? state.store.ticket(id: ticketId)
        filing = (try? state.store.lastFiling(ticketId: ticketId)) ?? nil
    }
}
