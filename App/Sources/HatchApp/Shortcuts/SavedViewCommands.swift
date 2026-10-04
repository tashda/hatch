import Foundation
import HatchCore

extension AppState {
    /// The saved views of the sidebar's Views section, in its order. The built-in ones stand in until the owner saves their own.
    func savedViews() -> [SavedView] {
        guard let json = (try? store.setting("views")) ?? nil,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SavedView].self, from: data) else { return TicketsView.defaultViews }
        return decoded
    }

    /// Shows the Tickets list filtered by a saved view, as a click in the sidebar does.
    func openSavedView(_ view: SavedView) {
        UserDefaults.standard.set(view.query, forKey: "hatch.pendingTicketQuery")
        navigate(to: .tickets)
    }
}
