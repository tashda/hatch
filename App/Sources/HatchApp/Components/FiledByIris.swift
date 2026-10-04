import SwiftUI
import HatchCore

/// What Iris set when she filed a ticket, each field with a way to change it (decision WF-T1). Nothing she set is final:
/// before work starts the owner changes the path, area, priority or verification here in one click, and the owner's own
/// words are one disclosure away.
struct FiledByIrisCard: View {
    @EnvironmentObject var state: AppState
    let ticketId: Int

    @State private var ticket: Ticket?
    @State private var filing: (at: Date, by: String, fields: [String: JSONValue])?
    @State private var showWords = false

    var body: some View {
        Group {
            if let ticket, let filing {
                card(ticket, filing)
            }
        }
        .autoReload(every: 4) { load() }
    }

    private var canChange: Bool {
        guard let t = ticket else { return false }
        return [.draft, .checking, .needsAnswers, .ready].contains(t.status)
    }

    private func card(_ t: Ticket, _ f: (at: Date, by: String, fields: [String: JSONValue])) -> some View {
        SectionCard("Filed by \(f.by == "owner" ? "you" : f.by)") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                row("Path") { pathMenu(t) }
                row("Type") { TypeBadge(type: t.type) }
                row("Area") { areaMenu(t) }
                row("Priority") { priorityMenu(t) }
                row("Verified") { verifyMenu(t) }
                if let moved = f.fields["project"]?["to"]?.stringValue, let p = state.projects.first(where: { $0.key == moved }) {
                    row("Project") { Text("Moved to \(p.name)").foregroundStyle(.secondary) }
                }
            }
            if let originalTitle = t.originalTitle {
                DisclosureGroup("Your words", isExpanded: $showWords) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(originalTitle).font(.callout.weight(.semibold))
                        if let body = t.originalBody, !body.isEmpty, body != originalTitle {
                            Text(body).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .font(.callout)
            }
            Text(canChange ? "Change anything Iris set before an agent starts on it." : "Work has started, so these stay as they are.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        GridRow {
            Text(label).font(.callout).foregroundStyle(.secondary)
            value().font(.callout)
        }
    }

    private func pathMenu(_ t: Ticket) -> some View {
        Menu(t.path?.displayName ?? "Not set") {
            ForEach(WorkPath.allCases.filter { $0 != .split }, id: \.self) { p in
                Button(p.displayName) { change { _ = try state.store.setPath(t.id, to: p, actor: .owner) } }
            }
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .disabled(!canChange)
    }

    private func areaMenu(_ t: Ticket) -> some View {
        let areas = state.project(id: t.projectId)?.config?.areas.map(\.name) ?? []
        return Menu(t.area ?? "None") {
            ForEach(areas, id: \.self) { a in
                Button(a) { change { _ = try state.store.update(t.id, actor: .owner, area: .some(a)) } }
            }
            Divider()
            Button("None") { change { _ = try state.store.update(t.id, actor: .owner, area: .some(nil)) } }
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .disabled(!canChange || areas.isEmpty)
    }

    private func priorityMenu(_ t: Ticket) -> some View {
        Menu(TicketPriority.name(t.priority)) {
            ForEach([TicketPriority.urgent, TicketPriority.high, TicketPriority.normal, TicketPriority.low], id: \.self) { p in
                Button(TicketPriority.name(p)) { change { _ = try state.store.update(t.id, actor: .owner, priority: p) } }
            }
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .disabled(t.status.isTerminal)
    }

    private func verifyMenu(_ t: Ticket) -> some View {
        Menu((t.verify ?? t.path?.defaultVerify ?? .preview).displayName) {
            ForEach(VerifyKind.allCases, id: \.self) { v in
                Button(v.displayName) { change { _ = try state.store.setVerify(t.id, to: v, actor: .owner) } }
            }
        }
        .menuStyle(.button)
        .controlSize(.small)
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
