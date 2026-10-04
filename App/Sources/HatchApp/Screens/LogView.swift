import SwiftUI
import HatchCore

/// The Log (decisions N2, B5): every Hatch action with its GitHub sync result, a failed filter and Retry.
struct LogView: View {
    @EnvironmentObject var state: AppState
    @State private var failedOnly = false
    @State private var tick = 0

    /// Every action with the sync that carried it (N2), for the project in the title or all of them.
    private var entries: [LogEntry] {
        (try? state.store.activityLog(projectId: state.projectFilterId, failedOnly: failedOnly, limit: 300)) ?? []
    }

    private func ticketLabel(_ id: Int?) -> String {
        guard let id else { return "" }
        let t: Ticket? = try? state.store.ticket(id: id)
        return t?.displayNumber ?? "#\(id)"
    }

    var body: some View {
        VStack(spacing: 8) {
            toolbarRow
                .floatingCard()
            let list = entries
            Group {
                if list.isEmpty {
                    ContentUnavailableView(failedOnly ? "Nothing failed" : "Nothing logged yet", systemImage: "list.bullet.rectangle",
                                           description: Text("Every change Hatch makes is recorded here with its result on GitHub."))
                } else {
                    List {
                        ForEach(list) { entry in row(entry) }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .floatingCard()
        }
        .autoReload(every: 5) { tick += 1 }
    }

    private var toolbarRow: some View {
        HStack(spacing: 12) {
            HXHeader(title: "Log", subtitle: "\(state.syncSummary.pending) waiting, \(state.syncSummary.failed) failed")
            Spacer()
            Toggle("Failed only", isOn: $failedOnly).toggleStyle(.checkbox)
            Button {
                state.perform("Retry") { try state.store.retryFailed() }
            } label: { Label("Retry all failed", systemImage: "arrow.clockwise") }
            .buttonStyle(.glass)
            .disabled(state.syncSummary.failed == 0)
        }
        .padding(16)
    }

    private func turn(for op: SyncOp) -> Turn {
        switch op.state {
        case "done": return .finished
        case "failed": return .you
        default: return .hatch
        }
    }

    private func stateName(_ op: SyncOp) -> String {
        switch op.state {
        case "done": return "Synced"
        case "failed": return "Failed"
        default: return "Waiting"
        }
    }

    /// One action: when, which ticket, who and what; then what GitHub made of it, when it went there.
    private func row(_ entry: LogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.at.formatted(date: .omitted, time: .standard)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(ticketLabel(entry.ticketId)).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            if let e = entry.event {
                Label(EventText.describe(e), systemImage: EventText.symbol(e))
                    .labelStyle(.titleAndIcon).lineLimit(2)
                Text(e.actor).font(.caption).foregroundStyle(.tertiary)
            } else if let op = entry.sync {
                Text(op.direction == "pull" ? "Pulled from GitHub" : op.op).font(.callout.monospaced()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let op = entry.sync { syncResult(op) }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func syncResult(_ op: SyncOp) -> some View {
        if let error = op.error, !error.isEmpty {
            Text(error).font(.caption).foregroundStyle(Theme.critical).lineLimit(2).textSelection(.enabled).frame(maxWidth: 240, alignment: .trailing)
        }
        if op.attempt > 0 { Text("attempt \(op.attempt)").font(.caption).foregroundStyle(.secondary) }
        if op.state == "failed" {
            HXProblemChip(text: stateName(op))
        } else {
            HXChip(text: stateName(op), turn: turn(for: op)).help(op.op)
        }
        if op.state == "failed" || (op.state == "pending" && op.error != nil) {
            Button("Retry") { state.perform("Retry") { try state.store.retrySync(op.id) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
