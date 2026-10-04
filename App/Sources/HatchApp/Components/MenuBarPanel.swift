import SwiftUI
import AppKit
import HatchCore
import HatchAgent

// Hatch's menu bar item (Settings › General, "Show in the menu bar", on by default): the footer in small, for when
// Hatch is in the background. Running agents, the status line, the latest activity, what waits for you, and a few
// actions. Clicking an agent or Open Desk brings the main window forward on that page.

/// The item in the menu bar: Hatch's arch with its dot, as in the app icon, and a small badge dot when tickets wait.
struct MenuBarLabel: View {
    let waiting: Bool

    var body: some View {
        Image(nsImage: Self.glyph(waiting: waiting))
            .accessibilityLabel(waiting ? "Hatch, tickets wait for you" : "Hatch")
    }

    /// Drawn rather than an SF Symbol, so it is Hatch's own shape. A template image: the menu bar tints it.
    static func glyph(waiting: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let line: CGFloat = 2.1
            let arch = NSBezierPath()
            let left: CGFloat = 2.8, right: CGFloat = 12.0, bottom: CGFloat = 2.2
            let radius = (right - left) / 2
            let centerY: CGFloat = 9.2
            arch.move(to: NSPoint(x: left, y: bottom))
            arch.line(to: NSPoint(x: left, y: centerY))
            arch.appendArc(withCenter: NSPoint(x: left + radius, y: centerY), radius: radius, startAngle: 180, endAngle: 0, clockwise: true)
            arch.line(to: NSPoint(x: right, y: bottom))
            arch.lineWidth = line
            arch.lineCapStyle = .round
            NSColor.black.setStroke()
            arch.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: left + radius - 2.1, y: 4.9, width: 4.2, height: 4.2)).fill()
            if waiting {
                // A gap around the badge keeps it apart from the arch at menu bar size.
                let badge = NSRect(x: 12.9, y: 10.9, width: 4.8, height: 4.8)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: badge.insetBy(dx: -1.2, dy: -1.2)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: badge).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The panel that opens from the menu bar item.
struct MenuBarPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var latest: (event: Event, ticket: Ticket)?
    @State private var maxAgents = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
            Divider().padding(.horizontal, 10)
            agents
                .padding(.horizontal, 6).padding(.vertical, 8)
            Divider().padding(.horizontal, 10)
            waiting
                .padding(.horizontal, 14).padding(.vertical, 10)
            activity
                .padding(.horizontal, 14).padding(.bottom, 10)
            Divider().padding(.horizontal, 10)
            actions
                .padding(6)
        }
        .frame(width: 320)
        .onAppear(perform: load)
        .onChange(of: state.revision) { load() }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenuBarLabel.glyph(waiting: false))
                .renderingMode(.template)
                .foregroundStyle(.secondary)
            Text("Hatch").font(.headline)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                SaveLevelGlyph(level: state.saveLevel)
                Text(state.saveLevel.title)
            }
            .font(.caption)
            .foregroundStyle(state.saveLevel == .problem ? Theme.critical : .secondary)
            .help(statusHelp)
        }
    }

    private var agents: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Agents").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(state.agentsPaused ? "Paused" : "\(state.agentRuns.count) of \(maxAgents)")
                    .font(.caption).foregroundStyle(state.agentsPaused ? Theme.you : Color.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8).padding(.bottom, 4)
            if state.agentRuns.isEmpty {
                Text(state.agentsPaused ? "Agents wait until you resume them." : "No agent is working right now.")
                    .font(.callout).foregroundStyle(.tertiary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            } else {
                ForEach(state.agentRuns, id: \.ticketId) { run in
                    Button { open(ticketId: run.ticketId) } label: { MenuBarAgentRow(run: run) }
                        .buttonStyle(MenuBarRowStyle())
                        .help("Open \(run.ticketNumber) in Hatch")
                }
            }
        }
    }

    private var waiting: some View {
        HStack(spacing: 10) {
            Text("\(state.waitingCount)")
                .font(.callout.weight(.semibold)).monospacedDigit()
                .foregroundStyle(state.waitingCount > 0 ? Theme.you : Color.secondary)
                .frame(minWidth: 26, minHeight: 26)
                .background(state.waitingCount > 0 ? Theme.youBackground : Color.secondary.opacity(0.1), in: Circle())
            Text(waitingText)
                .font(.callout)
                .foregroundStyle(state.waitingCount > 0 ? Color.primary : Color.secondary)
            Spacer(minLength: 8)
            Button("Open Desk") { state.navigate(to: .desk); bringForward() }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }

    @ViewBuilder private var activity: some View {
        if let latest {
            Button { open(ticketId: latest.ticket.id) } label: {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack(spacing: 6) {
                        Image(systemName: "clock").foregroundStyle(.tertiary)
                        Text(FooterActivityLine.line(latest)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(Format.relative(latest.event.at, now: context.date)).foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .help("Open the ticket")
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            Button { state.setAgentsPaused(!state.agentsPaused) } label: {
                MenuBarActionLabel(title: state.agentsPaused ? "Resume Agents" : "Pause Agents",
                                   symbol: state.agentsPaused ? "play.circle" : "pause.circle")
            }
            Button { bringForward() } label: { MenuBarActionLabel(title: "Open Hatch", symbol: "macwindow") }
            Button {
                NSApp.activate()
                openWindow(id: "settings")
            } label: { MenuBarActionLabel(title: "Settings…", symbol: "gearshape", shortcut: "⌘,") }
        }
        .buttonStyle(MenuBarRowStyle())
    }

    // MARK: Helpers

    private var waitingText: String {
        switch state.waitingCount {
        case 0: "Nothing waits for you"
        case 1: "1 ticket waits for you"
        case let n: "\(n) tickets wait for you"
        }
    }

    private var statusHelp: String {
        let s = state.syncSummary
        if let m = s.message, !m.isEmpty { return m }
        if let n = state.notebookProblem { return n }
        if s.pending > 0 { return "\(s.pending) waiting to sync" }
        return s.lastOK.map { "Synced \(Format.relative($0))" } ?? "Not synced yet"
    }

    private func load() {
        latest = (try? state.store.recentEvents(projectId: state.projectFilterId, limit: 1))?.first
        maxAgents = (try? state.store.maxAgents(projectId: state.projectFilterId)) ?? 3
    }

    private func open(ticketId: Int) {
        if let t = try? state.store.ticket(id: ticketId) { state.open(t) }
        bringForward()
    }

    private func bringForward() {
        state.showMainWindow(openWindow)
    }
}

/// One running agent: its task, the ticket, the step it is on and how long it has run.
private struct MenuBarAgentRow: View {
    let run: AgentRunInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: run.role.symbol)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(LinearGradient(colors: [Theme.agent.opacity(0.85), Theme.agent], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(run.ticketNumber).foregroundStyle(.secondary).monospacedDigit()
                    Text(run.ticketTitle).fontWeight(.medium).lineLimit(1).truncationMode(.tail)
                }
                .font(.callout)
                Text("\(run.role.taskTitle) · \(run.step)")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 6)
            TimelineView(.periodic(from: run.startedAt, by: 1)) { context in
                Text(Self.elapsed(since: run.startedAt, now: context.date))
                    .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
    }

    static func elapsed(since start: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// An action row, as a menu item looks: symbol, title, and the shortcut on the right.
private struct MenuBarActionLabel: View {
    let title: String
    let symbol: String
    var shortcut: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(title)
            Spacer()
            if let shortcut { Text(shortcut).foregroundStyle(.tertiary) }
        }
        .font(.callout)
    }
}

/// Rows highlight under the pointer like menu items, so the panel reads as one menu.
private struct MenuBarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0))
                )
                .onHover { hovering = $0 }
        }
    }
}
