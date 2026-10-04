import SwiftUI
import HatchCore

/// One group on the Desk: the tickets that wait for the owner in one status (decision C2).
struct DeskGroup: Identifiable {
    let status: Status
    let tickets: [Ticket]
    var id: String { status.rawValue }
}

/// What pressing A would do, shown in a confirmation sheet first (decision C5, H16). Never acts silently.
struct AcceptPlan: Identifiable {
    enum Kind {
        case proposal(choices: [String: String])
        case answers(pairs: [AnswerPair])
    }
    struct AnswerPair {
        let questionId: Int
        let text: String
    }
    let id: Int                 // ticket id
    let ticket: Ticket
    let lines: [String]
    let kind: Kind
}

struct DeskView: View {
    @EnvironmentObject var state: AppState
    @State private var groups: [DeskGroup] = []
    @State private var waiting: [Ticket] = []
    @State private var infos: [Int: ProposalInfo] = [:]
    @State private var questions: [Int: [Question]] = [:]
    @State private var selection: Int?
    @State private var collapsed: Set<String> = []
    @AppStorage("hatch.deskListWidth") private var listWidth = 380.0
    @State private var plan: AcceptPlan?
    @State private var notice: String?
    @State private var loaded = false
    @State private var projectNames: [Int: String] = [:]
    /// Everything waiting for the owner, for the Decide card at the top (DC1).
    @State private var decisions: [PendingDecision] = []

    private var allQueued: [Ticket] { groups.flatMap { $0.tickets } }
    private var selectedTicket: Ticket? {
        guard let selection else { return nil }
        return (allQueued + waiting).first { $0.id == selection }
    }

    var body: some View {
        Group {
            if loaded && groups.isEmpty && decisions.isEmpty {
                allClear.floatingCard()
            } else {
                splitContent
            }
        }
        .navigationTitle("Desk")
        .onChange(of: selection) { _, selected in state.selectedTicketId = selected; publishBrief() }
        .onChange(of: notice) { _, _ in publishBrief() }
        .onChange(of: groups.count) { _, _ in publishBrief() }
        .onAppear {
            if selection == nil { selection = state.selectedTicketId }
            publishBrief()
        }
        .onDisappear { state.inspectorTop = nil }
        .autoReload(every: 4) { load() }
        .sheet(item: $plan) { item in
            AcceptPlanSheet(plan: item) { confirmed in
                if confirmed { execute(item) }
                plan = nil
            }
        }
        .background(shortcutButtons)
    }

    // MARK: Layout

    private var splitContent: some View {
        HStack(spacing: 8) {
            listPane
                .frame(width: listWidth)
                .overlay(alignment: .trailing) {
                    PanelResizer(width: $listWidth, range: 300...560).offset(x: 11)
                }
            ticketPane
                .floatingCard()
        }
    }

    private var listPane: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if !decisions.isEmpty {
                    // The way into a Decide session over this same queue (DC1).
                    DecideIrisCard(items: decisions).floatingCard()
                }
                ForEach(groups) { group in
                    statusCard(title: group.status.displayName, count: group.tickets.count, color: Theme.you) {
                        ForEach(Array(group.tickets.enumerated()), id: \.element.id) { index, ticket in
                            if index > 0 { Divider().padding(.horizontal, 14) }
                            DeskSelectable(selected: selection == ticket.id, select: { selection = ticket.id }) {
                                DeskRow(ticket: ticket,
                                        copy: copy(for: ticket),
                                        recommendation: recommendationText(for: ticket),
                                        showProject: state.selectedProjectKey == nil && projectNames.count > 1,
                                        projectName: projectNames[ticket.projectId] ?? "",
                                        onAccept: selection == ticket.id && canAccept(ticket) ? { prepareAccept(ticket) } : nil)
                            }
                            .contextMenu { rowMenu(ticket) }
                        }
                    }
                }
                if !waiting.isEmpty {
                    statusCard(title: "Waiting on agents", count: waiting.count, color: Theme.agent, startsCollapsed: true) {
                        ForEach(Array(waiting.enumerated()), id: \.element.id) { index, ticket in
                            if index > 0 { Divider().padding(.horizontal, 14) }
                            DeskSelectable(selected: selection == ticket.id, select: { selection = ticket.id }) {
                                DeskWaitingRow(ticket: ticket)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 3)
        }
        .scrollClipDisabled()
        .onChange(of: allQueued.map { $0.id }) { _, _ in fixSelection() }
    }

    /// One card per status, so the groups read apart at a glance. Every card folds away from its header.
    private func statusCard<C: View>(title: String, count: Int, color: Color, startsCollapsed: Bool = false,
                                     @ViewBuilder _ content: () -> C) -> some View {
        let key = title
        let isCollapsed = startsCollapsed ? !collapsed.contains("open:" + key) : collapsed.contains(key)
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    if startsCollapsed {
                        if collapsed.contains("open:" + key) { collapsed.remove("open:" + key) } else { collapsed.insert("open:" + key) }
                    } else {
                        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(title).font(.subheadline.weight(.semibold))
                    Text("\(count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isCollapsed {
                content()
                    .transition(.opacity)
            }
        }
        .padding(.bottom, isCollapsed ? 0 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingCard()
        .clipped()
    }

    /// The selected ticket itself; the decision brief (accept, park, ask) lives at the top of the Iris inspector.
    private var ticketPane: some View {
        Group {
            if let ticket = selectedTicket {
                TicketDetailView(ticketId: ticket.id, embedded: true)
            } else {
                ContentUnavailableView("Select a ticket", systemImage: "tray", description: Text("Move with J and K. Return opens it."))
            }
        }
    }

    private func publishBrief() {
        guard let ticket = selectedTicket else { state.inspectorTop = nil; return }
        state.inspectorTop = AnyView(
            DeskBriefPane(ticket: ticket,
                          info: infos[ticket.id] ?? ProposalInfo(),
                          questions: questions[ticket.id] ?? [],
                          notice: notice,
                          onOpen: { open(ticket) },
                          onPark: { park(ticket) },
                          onAsk: { ask(ticket) },
                          onAccept: { prepareAccept(ticket) })
                .frame(maxHeight: 460)
        )
    }

    private var briefPane: some View {
        Group {
            if let ticket = selectedTicket {
                DeskBriefPane(ticket: ticket,
                              info: infos[ticket.id] ?? ProposalInfo(),
                              questions: questions[ticket.id] ?? [],
                              notice: notice,
                              onOpen: { open(ticket) },
                              onPark: { park(ticket) },
                              onAsk: { ask(ticket) },
                              onAccept: { prepareAccept(ticket) })
            } else {
                ContentUnavailableView("Select a ticket", systemImage: "tray", description: Text("Move with J and K. Return opens it."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func groupHeader(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func rowMenu(_ ticket: Ticket) -> some View {
        Button("Open") { open(ticket) }
        if canAccept(ticket) { Button("Accept recommendation") { prepareAccept(ticket) } }
        Button("Park") { park(ticket) }
        Button("Ask") { ask(ticket) }
    }

    /// Full triage from the list (decision C5): only where Hatch has a recommendation or suggested answers.
    private func canAccept(_ ticket: Ticket) -> Bool {
        if ticket.status == .yourCall && ticket.type == .proposal { return !(infos[ticket.id]?.recommendations.isEmpty ?? true) }
        return ticket.status == .needsAnswers && !(questions[ticket.id] ?? []).isEmpty
    }

    // MARK: Empty state (C6)

    private var allClear: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text("All clear")
                .font(.title2.weight(.semibold))
            Text("Nothing waits for you.")
                .foregroundStyle(.secondary)
            agentSummary
                .frame(maxWidth: 460)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var agentSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if waiting.isEmpty {
                Text("No agents are working right now.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text("Agents are working on")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(waiting.prefix(6)) { ticket in
                    Button { open(ticket) } label: { DeskWaitingRow(ticket: ticket) }
                        .buttonStyle(.plain)
                }
                if waiting.count > 6 {
                    Text("and \(waiting.count - 6) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Keyboard (J, K, Return, P, A)

    private var shortcutButtons: some View {
        ZStack {
            Button("Next") { moveSelection(by: 1) }.keyboardShortcut("j", modifiers: [])
            Button("Previous") { moveSelection(by: -1) }.keyboardShortcut("k", modifiers: [])
            Button("Open") { if let t = selectedTicket { open(t) } }.keyboardShortcut(.return, modifiers: [])
            Button("Park") { if let t = selectedTicket { park(t) } }.keyboardShortcut("p", modifiers: [])
            Button("Accept") { if let t = selectedTicket { prepareAccept(t) } }.keyboardShortcut("a", modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func moveSelection(by delta: Int) {
        let ids: [Int] = groups.filter { !collapsed.contains($0.status.displayName) }.flatMap { $0.tickets.map { $0.id } }
            + (collapsed.contains("open:Waiting on agents") ? waiting.map { $0.id } : [])
        guard !ids.isEmpty else { return }
        guard let current = selection, let index = ids.firstIndex(of: current) else {
            selection = ids.first
            return
        }
        let next = min(max(index + delta, 0), ids.count - 1)
        selection = ids[next]
    }

    // MARK: Data

    private func load() {
        let pid = state.projectFilterId
        var names: [Int: String] = [:]
        for project in state.projects { names[project.id] = project.name }
        projectNames = names
        let queue = (try? state.store.deskQueue(projectId: pid)) ?? []
        var newGroups: [DeskGroup] = []
        for item in queue {
            let tickets: [Ticket] = item.tickets.filter { $0.type != .theme }
            if !tickets.isEmpty { newGroups.append(DeskGroup(status: item.status, tickets: tickets)) }
        }
        let agentTickets: [Ticket] = (try? state.store.tickets(TicketFilter(projectId: pid, turn: .agent))) ?? []
        let hatchTickets: [Ticket] = (try? state.store.tickets(TicketFilter(projectId: pid, turn: .hatch))) ?? []
        let newWaiting: [Ticket] = (agentTickets + hatchTickets).filter { $0.type != .theme && $0.status != .merged }
        var newInfos: [Int: ProposalInfo] = [:]
        var newQuestions: [Int: [Question]] = [:]
        for group in newGroups {
            for ticket in group.tickets {
                newInfos[ticket.id] = ProposalInfo.load(store: state.store, ticket: ticket)
                if ticket.status == .needsAnswers {
                    newQuestions[ticket.id] = (try? state.store.questions(ticketId: ticket.id, openOnly: true)) ?? []
                }
            }
        }
        groups = newGroups
        waiting = newWaiting
        decisions = (try? state.store.pendingDecisions(projectId: pid)) ?? []
        infos = newInfos
        questions = newQuestions
        loaded = true
        fixSelection()
    }

    private func fixSelection() {
        let ids: [Int] = allQueued.map { $0.id } + waiting.map { $0.id }
        if let current = selection, ids.contains(current) { return }
        selection = allQueued.first?.id
    }

    private func copy(for ticket: Ticket) -> DeskCopy {
        DeskCopy.make(ticket: ticket, info: infos[ticket.id] ?? ProposalInfo(), openQuestions: questions[ticket.id]?.count ?? 0)
    }

    private func recommendationText(for ticket: Ticket) -> String? {
        guard ticket.status == .yourCall, let first = infos[ticket.id]?.recommendations.first else { return nil }
        return "Hatch recommends \(first.choiceName)"
    }

    // MARK: Actions

    private func open(_ ticket: Ticket) {
        state.open(ticket)
    }

    private func park(_ ticket: Ticket) {
        let id = ticket.id
        _ = state.perform("Could not park the ticket") { try state.store.move(id, to: .parked, actor: .owner, reason: "parked from the Desk") }
    }

    private func ask(_ ticket: Ticket) {
        state.selectedTicketId = ticket.id
        state.showAskPanel = true
    }

    private func prepareAccept(_ ticket: Ticket) {
        notice = nil
        if ticket.status == .yourCall && ticket.type == .proposal {
            let info = infos[ticket.id] ?? ProposalInfo()
            if info.recommendations.isEmpty {
                notice = "This Proposal has no recommendation. Open it to choose."
                return
            }
            var choices: [String: String] = [:]
            var lines: [String] = []
            for rec in info.recommendations {
                choices[rec.id] = rec.choiceId
                lines.append("\(rec.topicTitle): \(rec.choiceName)")
            }
            plan = AcceptPlan(id: ticket.id, ticket: ticket, lines: lines, kind: .proposal(choices: choices))
            return
        }
        if ticket.status == .needsAnswers {
            var pairs: [AcceptPlan.AnswerPair] = []
            var lines: [String] = []
            for question in questions[ticket.id] ?? [] {
                if let first = question.suggestions.first {
                    pairs.append(AcceptPlan.AnswerPair(questionId: question.id, text: first))
                    lines.append("\(question.text) \u{2192} \(first)")
                }
            }
            if pairs.isEmpty {
                notice = "These questions have no suggested answers. Open the ticket to answer them."
                return
            }
            plan = AcceptPlan(id: ticket.id, ticket: ticket, lines: lines, kind: .answers(pairs: pairs))
            return
        }
        notice = "There is nothing to accept from the list here. Press Return to open the ticket."
    }

    private func execute(_ plan: AcceptPlan) {
        switch plan.kind {
        case .proposal(let choices):
            let id = plan.id
            _ = state.perform("Could not accept the Proposal") { try state.store.acceptProposal(ticketId: id, choices: choices) }
        case .answers(let pairs):
            _ = state.perform("Could not save the answers") {
                for pair in pairs { _ = try state.store.answer(questionId: pair.questionId, text: pair.text) }
            }
        }
    }
}

/// A row's selected and hover looks. The row's size never depends on either, so nothing shifts when you click.
struct DeskSelectable<Content: View>: View {
    let selected: Bool
    let select: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : (hovering ? Color.primary.opacity(0.045) : Color.clear))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(selected ? 0.38 : 0), lineWidth: 1)
                    }
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: select)
            .animation(.easeOut(duration: 0.12), value: selected)
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

struct DeskRow: View {
    let ticket: Ticket
    let copy: DeskCopy
    let recommendation: String?
    let showProject: Bool
    let projectName: String
    /// Set only on the selected row when Hatch has a recommendation to accept from the list.
    var onAccept: (() -> Void)? = nil

    private var subtitle: String {
        var parts = [copy.line]
        if showProject { parts.append(projectName) }
        if let recommendation { parts.append(recommendation) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 11) {
            TypeBadge(type: ticket.type, showName: false)
                .frame(width: 30, height: 30)
                .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(ticket.displayNumber)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(ticket.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.you)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One fixed slot: the time, or the Accept button on the selected row. Same size either way.
            ZStack(alignment: .trailing) {
                if let onAccept {
                    // The system's round glass button, as in a toolbar: black icon, native hover and press.
                    Button(action: onAccept) {
                        Image(systemName: "checkmark").foregroundStyle(.primary)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .help("Accept Hatch's recommendation (A)")
                    .accessibilityLabel("Accept")
                } else {
                    Text(Format.relative(ticket.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 86, alignment: .trailing)
        }
        .frame(height: 54)
    }
}

struct DeskWaitingRow: View {
    let ticket: Ticket

    var body: some View {
        HStack(spacing: 11) {
            TypeBadge(type: ticket.type, showName: false)
                .frame(width: 30, height: 30)
                .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            HStack(spacing: 6) {
                Text(ticket.displayNumber)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(ticket.title).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let who = ticket.takenBy {
                Text(who).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(height: 46)
    }
}

/// The confirmation shown before Hatch's recommendation is applied from the list.
struct AcceptPlanSheet: View {
    let plan: AcceptPlan
    let finish: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Accept the recommendation for \(plan.ticket.displayNumber)?")
                .font(.title3.weight(.semibold))
            Text(plan.ticket.title)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
                        Text(line).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            Text(footnote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { finish(false) }
                    .keyboardShortcut(.cancelAction)
                Button { finish(true) } label: { Label("Accept", systemImage: "checkmark") }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var footnote: String {
        switch plan.kind {
        case .proposal:
            return "This picks these answers and moves the ticket to Accepted. An agent then builds it, which costs time and tokens. You have not opened the options yet; open the ticket first if you want to look."
        case .answers:
            return "These suggested answers are sent as your answers. Questions without a suggestion stay open."
        }
    }
}
