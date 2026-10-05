import SwiftUI
import HatchCore

/// A ticket in a window of its own: the ticket page and nothing else (no sidebar, no project menu). Following a
/// related ticket replaces the page here, with Back and Forward for this window only. Everything it changes goes
/// through the same store as the main window, so the two stay in step.
struct TicketWindowView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var keys = ShortcutStore.shared
    @State private var history: PageHistory<Int>

    init(ticketId: Int) {
        _history = State(initialValue: PageHistory(start: ticketId))
    }

    var body: some View {
        TicketDetailView(ticketId: history.current)
            .id(history.current)
            .environment(\.ticketOpener, TicketOpener(open: { history.visit($0) }, isTicketWindow: true))
            .frame(minWidth: 640, minHeight: 480)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ControlGroup {
                        Button { history.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                            .disabled(!history.canGoBack)
                            .help(keys.help("Go Back", "back"))
                        Button { history.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                            .disabled(!history.canGoForward)
                            .help(keys.help("Go Forward", "forward"))
                    }
                    .controlGroupStyle(.navigation)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showInHatch() } label: { Label("Show in Hatch", systemImage: "macwindow") }
                        .labelStyle(.iconOnly)
                        .help("Show this ticket in the main window")
                }
            }
            .windowNavigation(WindowNavigation(
                canGoBack: history.canGoBack, canGoForward: history.canGoForward,
                goBack: { history.goBack() }, goForward: { history.goForward() }))
            .focusedSceneValue(\.currentTicketId, history.current)
    }

    private func showInHatch() {
        let id = history.current
        HatchWindows.showMain()
        if let ticket = try? state.store.ticket(id: id) { state.open(ticket) }
    }
}
