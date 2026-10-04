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
                    let iris = try AgentFactory.resolve(.iris, settings: AgentSettings.load(from: store), context: context)
                    _ = try VettingService(store: store, runner: iris.runner, label: iris.label).vet(ticketId: ticketId)
                } catch {
                    try? store.record(ticketId, actor: "Iris", kind: "vetting-failed", payload: ["reason": .string("\(error)")])
                }
            }.value
            running.remove(ticketId)
            state.refresh()
        }
    }
}
