import SwiftUI
import HatchCore

// Placeholders so the package compiles while each screen is built. Each screen replaces its stub in its own file
// (delete the stub from this file when you create the real one).
struct CommandPalette: View { var body: some View { Text("Search").padding(40) } }
struct AskPanel: View { var body: some View { Text("Ask") } }
struct TicketsView: View { var body: some View { Text("Tickets") } }
struct BoardView: View { var body: some View { Text("Board") } }
struct TicketDetailView: View { let ticketId: Int; var body: some View { Text("Ticket \(ticketId)") } }
struct ComposerView: View { var body: some View { Text("New ticket") } }
struct SettingsView: View { var body: some View { Text("Settings").padding(40) } }
