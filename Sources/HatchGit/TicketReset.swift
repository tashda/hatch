import Foundation
import HatchCore

/// "Reset this ticket" in full (decision IR16): the ticket's worktrees and branches are removed, then the database half
/// puts the ticket back to its first prompt. A running agent must be stopped by the caller first.
public enum TicketReset {
    public struct Result: Sendable {
        public var ticket: Ticket
        /// Workspaces that could not be removed (a dirty tree is removed by force; this is for the rest).
        public var leftovers: [String]
    }

    @discardableResult
    public static func run(store: HatchStore, ticketId: Int, git: GitRunner = ProcessGit()) throws -> Result {
        let manager = WorkspaceManager(store: store, git: git)
        var leftovers: [String] = []
        for ws in try manager.list(ticketId: ticketId) where ws.state == "active" {
            do { try manager.remove(ws, deleteBranch: true, force: true) }
            catch { leftovers.append("\(ws.path): \(error)") }
        }
        return Result(ticket: try store.resetTicket(ticketId), leftovers: leftovers)
    }
}
