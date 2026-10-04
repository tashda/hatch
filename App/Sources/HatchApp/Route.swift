import Foundation

/// Where the user is in the app. The sidebar sets it (decision B1); a ticket opens full width (decision C1).
enum Route: Hashable {
    case desk, tickets, board, previews, specs, decisions, components, agents, reports, health, log, projects
    case ticket(Int)
    case newTicket

    var title: String {
        switch self {
        case .desk: "Desk"
        case .tickets: "Tickets"
        case .board: "Board"
        case .previews: "Previews"
        case .specs: "Specs"
        case .decisions: "Decisions"
        case .components: "Components"
        case .agents: "Agents"
        case .reports: "Reports"
        case .health: "Health"
        case .log: "Log"
        case .projects: "Project"
        case .ticket: "Ticket"
        case .newTicket: "New ticket"
        }
    }

    var symbol: String {
        switch self {
        case .desk: "tray"
        case .tickets: "list.bullet"
        case .board: "rectangle.split.3x1"
        case .previews: "eye"
        case .specs: "doc.text"
        case .decisions: "flag"
        case .components: "paintpalette"
        case .agents: "cpu"
        case .reports: "chart.bar.xaxis"
        case .health: "stethoscope"
        case .log: "list.bullet.rectangle"
        case .projects: "gearshape"
        case .ticket: "ticket"
        case .newTicket: "plus"
        }
    }

    /// The command in `ShortcutCatalog` that opens this page. Exhaustive on purpose: a new page must say whether it has one.
    var shortcutId: String? {
        switch self {
        case .desk: "page.desk"
        case .tickets: "page.tickets"
        case .board: "page.board"
        case .previews: "page.previews"
        case .specs: "page.specs"
        case .decisions: "page.decisions"
        case .components: "page.components"
        case .agents: "page.agents"
        case .reports: "page.reports"
        case .health: "page.health"
        case .log: "page.log"
        case .projects: "page.projects"
        case .newTicket: "page.newTicket"
        case .ticket: nil
        }
    }

    /// The pages in the order the Go menu lists them.
    static let pages: [Route] = [.desk, .tickets, .board, .previews, .specs, .decisions, .agents, .log, .projects, .components, .health, .reports]
}

extension Route {
    /// The route as a short string, so the last page can be saved as a setting and opened at the next launch.
    /// New ticket is not reopened: its unsaved text is gone, so it opens the Desk.
    var storageKey: String {
        switch self {
        case .ticket(let id): "ticket:\(id)"
        case .newTicket: "desk"
        default: Route.plain.first { $0.value == self }?.key ?? "desk"
        }
    }

    init?(storageKey: String) {
        if storageKey.hasPrefix("ticket:"), let id = Int(storageKey.dropFirst("ticket:".count)) { self = .ticket(id); return }
        guard let route = Route.plain[storageKey] else { return nil }
        self = route
    }

    private static let plain: [String: Route] = [
        "desk": .desk, "tickets": .tickets, "board": .board, "previews": .previews, "specs": .specs, "decisions": .decisions,
        "components": .components, "agents": .agents, "health": .health, "log": .log, "projects": .projects,
    ]
}
