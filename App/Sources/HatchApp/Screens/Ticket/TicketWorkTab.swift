import SwiftUI
import AppKit
import HatchCore
import HatchAgent

/// Work: who is working, the build steps, the workspaces and branches, and the files claimed (decisions I1, I5, K3).
struct TicketWorkTab: View {
    let ticket: Ticket
    /// Switches to the Thread tab with Instruction selected (decision I5).
    var onInstruction: () -> Void = {}
    @EnvironmentObject var state: AppState

    @State private var workspaces: [Workspace] = []
    @State private var repos: [Repo] = []
    @State private var claims: [Claim] = []
    @State private var blockers: [Ticket] = []
    @State private var gate: [GateResult] = []

    private var showsBuildSteps: Bool {
        ticket.type == .proposal || ticket.type == .tweak || ticket.type == .bug
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let run = state.agentRuns.first(where: { $0.ticketId == ticket.id }) {
                    LiveAgentSection(run: run)
                } else {
                    agentRow
                    if let problem = state.launcher?.problem(ticketId: ticket.id) {
                        Label("The agent could not start: \(problem)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.critical).font(.callout)
                    }
                }
                if !blockers.isEmpty { blockerCard }
                if !gate.isEmpty { gateSection }
                if showsBuildSteps { buildSection }
                workspaceSection
                claimSection
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .autoReload(every: 5) { load() }
    }

    // MARK: Quality gate

    /// What the quality gate said about the latest offer, and how many tries it took (decision H19).
    private var gateSection: some View {
        let latest = gate[0]
        let rejected = gate.filter { !$0.passed }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Quality gate").font(.headline)
            HStack(spacing: 8) {
                Image(systemName: latest.passed ? "checkmark.seal" : "xmark.seal")
                    .foregroundStyle(latest.passed ? Color.secondary : Theme.critical)
                Text(latest.passed
                     ? "Passed" + (latest.revision.map { " on revision \($0)" } ?? "") + (latest.findings.isEmpty ? "" : " with \(Format.count(latest.findings.count, "warning"))")
                     : "The last offer was sent back to the agent with \(Format.count(latest.findings.filter(\.isError).count, "error"))")
                Spacer()
                if rejected > 0 && latest.passed {
                    Text("after \(Format.count(rejected, "rejected offer"))").font(.callout).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(latest.findings.prefix(8).enumerated()), id: \.offset) { _, f in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(f.code).font(.caption.monospaced()).foregroundStyle(f.isError ? Theme.critical : .secondary)
                    Text(f.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Agent

    private var agentRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu").foregroundStyle(ticket.takenBy == nil ? Color.secondary : Theme.agent)
            if let who = ticket.takenBy {
                Text("\(who) is working on this")
                Spacer()
                Button { onInstruction() } label: { Label("Send instruction", systemImage: "text.bubble") }
                    .buttonStyle(.glass)
                    .help("Opens the Thread with the Instruction kind selected.")
                // A run that can be stopped: the button turns red while it runs (DESIGN, LK11).
                Button { stopAgent() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.glass)
                    .tint(Theme.critical)
                    .help("Takes the ticket back from the agent. The agent finds out the next time it asks Hatch.")
            } else {
                Text("No agent is working on this right now.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func stopAgent() {
        let id = ticket.id
        _ = state.perform("Could not stop the agent") { try state.store.release(id, reason: "stopped by the owner") }
    }

    private var blockerCard: some View {
        SectionCard("Waiting for") {
            ForEach(blockers) { other in
                Button {
                    state.open(other)
                } label: {
                    HStack(spacing: 8) {
                        Text(other.displayNumber).foregroundStyle(.secondary)
                        Text(other.title)
                        StatusChip(status: other.status)
                    }
                }
                .buttonStyle(.link)
            }
        }
    }

    // MARK: Build steps (another agent's view)

    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Build steps")
                .font(.headline)
            // The steps view belongs to the build module; it reads the ticket's events itself.
            BuildStepsView(ticketId: ticket.id)
        }
    }

    // MARK: Workspaces

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workspaces and branches")
                .font(.headline)
            if workspaces.isEmpty {
                plannedBranches
            } else {
                ForEach(workspaces) { ws in
                    workspaceRow(ws)
                }
            }
        }
    }

    private func repoLabel(_ id: Int) -> String {
        guard let repo = repos.first(where: { $0.id == id }) else { return "Repo" }
        return hxRoleName(repo.role)
    }

    private func workspaceRow(_ ws: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(repoLabel(ws.repoId))
                    .font(.callout.weight(.semibold))
                Text(ws.branch)
                    .font(.callout.monospaced())
                PlainChip(text: ws.state)
                Spacer()
                // Take over: each ticket has its own workspace, so no other agent is disturbed (decision I5).
                Button("Open in Terminal") { openTerminal(ws.path) }
                    .controlSize(.small)
                Button("Open in Xcode") { openXcode(ws.path) }
                    .controlSize(.small)
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ws.path)
                }
                .controlSize(.small)
            }
            Text(ws.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private var plannedBranches: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(repos.filter { $0.role != .tickets }) { repo in
                HStack(spacing: 8) {
                    Text(repoLabel(repo.id)).font(.callout.weight(.semibold))
                    Text(plannedBranch).font(.callout.monospaced())
                    Text("· not started").font(.callout).foregroundStyle(.secondary)
                }
            }
            if repos.isEmpty {
                Text("No repositories are set up for this project yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var plannedBranch: String {
        let number: Int = ticket.ghNumber ?? ticket.id
        let slug = String(HatchStore.slug(ticket.title).prefix(32))
        return "ticket/\(number)-\(slug)"
    }

    private func openTerminal(_ path: String) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openXcode(_ path: String) {
        let folder = URL(fileURLWithPath: path)
        if let xcode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") {
            NSWorkspace.shared.open([folder], withApplicationAt: xcode, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(folder)
        }
    }

    // MARK: Claims

    private var activeClaims: [Claim] { claims.filter { $0.state != "released" } }

    private var claimSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files claimed")
                .font(.headline)
            if activeClaims.isEmpty {
                Text("No files claimed. An agent declares them when it plans the work.")
                    .foregroundStyle(.secondary)
            }
            ForEach(activeClaims) { claim in
                HStack(spacing: 8) {
                    Text(claim.pathGlob)
                        .font(.callout.monospaced())
                    Spacer()
                    PlainChip(text: claim.state)
                }
            }
        }
    }

    // MARK: Data

    private func load() {
        gate = (try? state.store.gateResults(ticketId: ticket.id)) ?? []
        let store = state.store
        let id = ticket.id
        workspaces = (try? store.workspaces(ticketId: id)) ?? []
        repos = (try? store.repos(projectId: ticket.projectId)) ?? []
        claims = (try? store.claims(ticketId: id)) ?? []
        blockers = (try? store.openBlockers(ticketId: id)) ?? []
    }
}


/// The agent Hatch started for this ticket, live: what it is doing, its log, and Stop or take over in Terminal.
private struct LiveAgentSection: View {
    @EnvironmentObject var state: AppState
    let run: AgentRunInfo
    @State private var lines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(run.agent) · \(run.role.taskTitle)").fontWeight(.semibold)
                    Text(run.step).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Terminal", systemImage: "terminal") { state.openInTerminal(run.workspace) }
                    .buttonStyle(.glass).help("Open Terminal in the agent's workspace to take over")
                Button("Stop", systemImage: "stop.fill") { state.stopAgent(ticketId: run.ticketId) }
                    .buttonStyle(.glass).tint(Theme.critical)
                    .help("Stop the agent; the ticket waits until you resume it")
            }
            HStack(spacing: 18) {
                Label([run.model, run.providerName].compactMap { $0 }.joined(separator: " · "), systemImage: "cpu")
                Label(run.branch ?? "–", systemImage: "arrow.triangle.branch")
                Label("\(hxTokens(run.tokensIn)) in · \(hxTokens(run.tokensOut)) out", systemImage: "gauge.with.dots.needle.33percent")
                if run.attempt > 1 { Label("Second try", systemImage: "arrow.clockwise") }
            }
            .font(.callout).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.callout.monospaced()).textSelection(.enabled).id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .frame(height: 220)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: lines.count) { _, n in if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) } }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .autoReload(every: 2) {
            let path = run.logPath
            Task {
                let text = await Task.detached { AgentLauncher.tail(of: path, lines: 60) }.value
                let next = text.split(separator: "\n").map(String.init)
                if next != lines { lines = next }
            }
        }
    }
}
