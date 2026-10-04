import SwiftUI
import HatchCore
import HatchAgent

/// A slot in the footer: an empty ring, a busy agent Hatch did not start (the owner's own), or one of the launcher's
/// agents. Hovering a launcher's agent shows its card; clicking keeps the card open.
struct AgentSlotCircle: View {
    @EnvironmentObject var state: AppState
    let run: AgentRunInfo?
    let busy: Bool

    @State private var hovering = false
    @State private var hoveringCard = false
    @State private var pinned = false
    @State private var showing = false

    var body: some View {
        Circle()
            .fill(busy || run != nil
                  ? AnyShapeStyle(LinearGradient(colors: [Theme.agent.opacity(0.75), Theme.agent], startPoint: .top, endPoint: .bottom))
                  : AnyShapeStyle(Color.secondary.opacity(0.08)))
            .overlay(Circle().strokeBorder(busy || run != nil ? Theme.agent.opacity(0.35) : Color.secondary.opacity(0.4), lineWidth: busy || run != nil ? 3 : 1))
            .shadow(color: busy || run != nil ? Theme.agent.opacity(0.45) : .clear, radius: 3)
            .frame(width: 11, height: 11)
            .scaleEffect(showing ? 1.25 : 1)
            .animation(.snappy(duration: 0.2), value: showing)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .onHover { inside in hovering = inside; update() }
            .onTapGesture {
                if run == nil { state.navigate(to: .agents); return }
                pinned.toggle(); update()
            }
            .popover(isPresented: Binding(get: { showing && run != nil }, set: { if !$0 { pinned = false; showing = false } }),
                     arrowEdge: .top) {
                if let run {
                    AgentCard(run: run) { pinned = false; showing = false }
                        .onHover { inside in hoveringCard = inside; update() }
                }
            }
            .help(run == nil ? (busy ? "An agent is working. Open Agents" : "A free agent slot. Open Agents") : "")
            .accessibilityLabel(run.map { "Agent on \($0.ticketNumber): \($0.step)" } ?? (busy ? "Agent working" : "Free agent slot"))
    }

    /// Shows the card while the pointer is on the circle or the card, or while it is pinned. Leaving waits a moment, so
    /// moving from the circle to the card does not close it.
    private func update() {
        if hovering || hoveringCard || pinned { showing = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if !hovering && !hoveringCard && !pinned { showing = false }
        }
    }
}

/// What one agent is doing, on glass: the task and ticket, the step it is on, where it works, and what you can do.
struct AgentCard: View {
    @EnvironmentObject var state: AppState
    let run: AgentRunInfo
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: run.role.symbol)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(LinearGradient(colors: [Theme.agent.opacity(0.85), Theme.agent], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(run.role.taskTitle).font(.headline)
                    Text(run.attempt > 1 ? "\(run.agent) · second try" : run.agent).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                TimelineView(.periodic(from: run.startedAt, by: 1)) { context in
                    Text(elapsed(context.date)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            Button { openTicket() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(run.ticketNumber).foregroundStyle(.secondary).monospacedDigit()
                    Text(run.ticketTitle).fontWeight(.semibold).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.forward").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
                .font(.title3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the ticket")

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(run.step).lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                fact("Repository", run.repo ?? "–", symbol: "shippingbox")
                fact("Branch", run.branch ?? "–", symbol: "arrow.triangle.branch")
                fact("Model", [run.model, run.providerName].compactMap { $0 }.joined(separator: " · "), symbol: "cpu")
                fact("Tokens", "\(hxTokens(run.tokensIn)) in · \(hxTokens(run.tokensOut)) out", symbol: "gauge.with.dots.needle.33percent")
            }
            .font(.callout)

            HStack(spacing: 8) {
                Button("Open Ticket", systemImage: "doc.text") { openTicket() }
                    .buttonStyle(.glassProminent)
                Button("Terminal", systemImage: "terminal") { state.openInTerminal(run.workspace) }
                    .buttonStyle(.glass)
                    .help("Open Terminal in the agent's workspace to take over")
                Spacer()
                Button("Stop", systemImage: "stop.fill", role: .destructive) { state.stopAgent(ticketId: run.ticketId); close() }
                    .buttonStyle(.glass)
                    .help("Stop the agent; the ticket waits until you resume it")
            }
            .controlSize(.regular)
        }
        .padding(18)
        .frame(width: 360)
    }

    @ViewBuilder private func fact(_ label: String, _ value: String, symbol: String) -> some View {
        GridRow {
            Label(label, systemImage: symbol).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            Text(value).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
    }

    private func elapsed(_ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(run.startedAt)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func openTicket() {
        if let t = try? state.store.ticket(id: run.ticketId) { state.open(t) }
        close()
    }
}
