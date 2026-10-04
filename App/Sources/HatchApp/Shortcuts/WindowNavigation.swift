import SwiftUI
import HatchCore

/// What the Back and Forward menu items and ⌘[ ⌘] act on. Each window publishes its own as a focused value, so the
/// shortcut always moves the window in front: the main window, Settings or a ticket window.
struct WindowNavigation {
    var canGoBack: Bool
    var canGoForward: Bool
    var goBack: () -> Void
    var goForward: () -> Void
}

extension FocusedValues {
    @Entry var windowNavigation: WindowNavigation?
    /// The ticket the window in front is about: the open page, or the selected row of a list. Nil elsewhere.
    @Entry var currentTicketId: Int?
    /// What the ticket page in front can do now; the Ticket menu enables only what is here.
    @Entry var ticketActions: TicketActions?
}

/// How a ticket page opens another ticket. In the main window that is the usual `state.open`; in a ticket window the
/// page is replaced in place, so Back and Forward stay inside that window.
struct TicketOpener {
    var open: (Int) -> Void
    /// A ticket window is not the main window: pages that live there (Previews) must bring it forward first.
    var isTicketWindow: Bool

    @MainActor static func go(_ opener: TicketOpener?, _ ticket: Ticket, _ state: AppState) {
        if let opener { opener.open(ticket.id) } else { state.open(ticket) }
    }
}

extension EnvironmentValues {
    @Entry var ticketOpener: TicketOpener?
}

extension AppState {
    /// The ticket the main window is about: the open page, or the Desk's selection. The other pages have none.
    var currentTicketId: Int? {
        switch route {
        case .ticket(let id): id
        case .desk, .tickets: selectedTicketId
        default: nil
        }
    }
}

/// The commands of the ticket page in front, as closures it fills in for the ticket's current status.
struct TicketActions {
    var tabs: [TicketTab]
    var selectTab: (TicketTab) -> Void
    var primaryTitle: String?
    var primary: (() -> Void)?
    var secondaryTitle: String?
    var secondary: (() -> Void)?
    var sendBack: (() -> Void)?
    var park: (() -> Void)?
    var resumeTitle: String?
    var resume: (() -> Void)?
    var drop: (() -> Void)?
}
