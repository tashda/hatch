import SwiftUI
import HatchCore

// Placeholders so the package compiles while each screen is built. Each screen replaces its stub in its own file
// (delete the stub from this file when you create the real one).
struct CommandPalette: View { var body: some View { Text("Search").padding(40) } }
struct AskPanel: View { var body: some View { Text("Ask") } }
struct TicketDetailView: View { let ticketId: Int; var body: some View { Text("Ticket \(ticketId)") } }
struct SettingsView: View { var body: some View { Text("Settings").padding(40) } }
