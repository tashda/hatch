import SwiftUI
import HatchCore

/// Connects the UI to the vetting agent (Iris) without the UI depending on it, so the app works while it does not exist.
///
/// Whoever owns HatchAgent's `VettingService` wires it once at launch, for example in `AppState.live()` or `HatchApp.init`:
///
///     VettingBridge.runner = { ticketId, state in await VettingService(...).vet(ticketId: ticketId) }
///
/// Contract for what Iris leaves behind (read by `IrisReviewView`):
/// - Questions: `store.ask(ticketId, text:, suggestions:, by: "Iris")`. They show as answer cards.
/// - One summary note: `store.addNote(ticketId, kind: .agent, author: "Iris", body: <one or two sentences>, context: ["vetting": <object>])`
///   where the object may hold:
///     "rewrite":    { "title": "...", "body": "..." }                       (the suggested text for the ticket)
///     "type":       { "suggested": "question", "reason": "..." }             (a suggested type change, decision E9)
///     "duplicates": [ { "ticket": <ticket id>, "reason": "..." } ]           (likely duplicates, decision E6)
/// The review records the owner's choices as events of kind "vetting-review" with payload
/// { note: <note id>, part: "rewrite" | "type" | "duplicate-<id>", outcome: "accepted" | "edited" | "kept" | ... }.
@MainActor
enum VettingBridge {
    static var runner: ((Int, AppState) async -> Void)?

    static var isAvailable: Bool { runner != nil }

    static func start(ticketId: Int, state: AppState) {
        guard let runner else { return }
        Task { @MainActor in
            await runner(ticketId, state)
            state.refresh()
        }
    }
}
