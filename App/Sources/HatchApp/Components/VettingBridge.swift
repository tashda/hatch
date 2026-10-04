import SwiftUI
import HatchCore
import HatchAgent

/// Starts Iris (HatchAgent's `VettingService`) for a ticket in Checking, off the main thread.
/// What she leaves behind: questions (`store.ask(... by: "Iris")`), a `vetting` event holding a `VettingSuggestion`
/// (rewrite, type change, duplicate), and either Needs answers or Ready. A failed run leaves the ticket in Checking with a
/// `vetting-failed` event; `IrisReviewView` shows the reason and offers "Check again".
@MainActor
enum VettingBridge {
    private static var running = Set<Int>()

    static var isAvailable: Bool { true }

    /// Starts Iris for every ticket waiting in Checking that nobody is checking: tickets made with `hatch new` or
    /// `hatch ticket new --submit`, issues pulled from GitHub, and tickets back from Needs answers (gaps G6, G7).
    /// A check that failed is not retried here until the ticket enters Checking again; "Check again" does that.
    static func sweep(state: AppState) {
        let store = state.store
        guard let waiting = try? store.tickets(TicketFilter(statuses: [.checking])) else { return }
        for t in waiting where !running.contains(t.id) {
            let events = (try? store.events(ticketId: t.id, kinds: ["status", "vetting-failed"])) ?? []
            let entered = events.last { $0.kind == "status" && $0.payload["to"]?.stringValue == Status.checking.rawValue }
            let failed = events.last { $0.kind == "vetting-failed" }
            if let failed, failed.id > (entered?.id ?? 0) { continue }
            start(ticketId: t.id, state: state)
        }
    }

    static func start(ticketId: Int, state: AppState) {
        guard !running.contains(ticketId) else { return }
        let store = state.store
        let context = state.agentContext
        running.insert(ticketId)
        Task { @MainActor in
            await Task.detached {
                do {
                    // Iris uses the provider and model chosen in Settings, Agents. A missing or switched-off
                    // provider is a failure with a reason, never a silent fallback to another model.
                    let settings = AgentSettings.load(from: store)
                    let iris = try AgentFactory.resolve(.iris, settings: settings, context: context)
                    let service = VettingService(store: store, runner: iris.runner, label: iris.label, provider: iris.provider.name, model: iris.model)
                    _ = try service.vet(ticketId: ticketId)
                } catch {
                    try? store.record(ticketId, actor: "Iris", kind: "vetting-failed", payload: ["reason": .string("\(error)")])
                }
            }.value
            running.remove(ticketId)
            state.refresh()
        }
    }
}
