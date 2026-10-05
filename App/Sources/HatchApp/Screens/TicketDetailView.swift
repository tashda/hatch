import SwiftUI
import AppKit
import HatchCore
import HatchGit

enum TicketTab: String, CaseIterable, Identifiable {
    case overview, options, thread, work, history
    var id: String { rawValue }
    /// For the Ticket menu; the page itself says Variants for a Sketch.
    var menuTitle: String {
        switch self {
        case .overview: "Overview"
        case .options: "Variants or Options"
        case .thread: "Thread"
        case .work: "Work"
        case .history: "History"
        }
    }
}

/// What the banner says and which buttons it offers for a ticket in its current status (decision F2).
enum BannerAction {
    case openStage
    case tab(TicketTab)
    case submit
    case previews
    case closeAsAnswered
    case resume
    case reopen
    case decideQuestion
    case approvePlan
    case sendBackPlan
}

struct BannerSpec {
    var message: String
    var primaryTitle: String?
    var primary: BannerAction?
    var secondaryTitle: String?
    var secondary: BannerAction?
}

/// The page for one ticket, whatever its type: header, banner with the main action, then tabs (decisions F1 to F5).
struct TicketDetailView: View {
    let ticketId: Int
    /// Inside the Desk: one flat page in the Desk's card, no back link. On its own page the sections are separate panels.
    var embedded = false
    @EnvironmentObject var state: AppState
    @Environment(\.ticketOpener) private var opener
    @State private var ticket: Ticket?
    @State private var tab: TicketTab = .overview
    @State private var openQuestions = 0
    @State private var threadCount = 0
    @State private var info = ProposalInfo()
    @State private var confirmDrop = false
    @State private var confirmReset = false
    @State private var questionOptions: [QuestionOption] = []
    @State private var deciding = false
    @State private var threadKind: NoteKind = .note
    @State private var sendingBack = false
    /// An agent's plan waiting for the owner (decision DC8), and the sheet for sending it back with a note.
    @State private var pendingPlan: PlanReview?
    @State private var sendingPlanBack = false

    var body: some View {
        Group {
            if let ticket {
                page(ticket)
            } else {
                ContentUnavailableView("Ticket not found", systemImage: "questionmark.folder",
                                       description: Text("It may have been removed."))
            }
        }
        .navigationTitle(ticket?.displayNumber ?? "Ticket")
        .autoReload(every: 3) { load() }
        .onChange(of: tab) { _, newTab in
            if newTab != .thread { threadKind = .note }
        }
        .onChange(of: ticketId) { _, _ in
            tab = .overview
            load()
        }
        .onChange(of: state.snapshotTicketTab) { _, next in
            if Snapshots.folder != nil, let next { tab = next }
        }
        .onAppear {
            if Snapshots.folder != nil, let next = state.snapshotTicketTab { tab = next }
        }
        .sheet(isPresented: $deciding) {
            if let ticket { QuestionDecisionSheet(ticket: ticket, options: questionOptions) }
        }
        .focusedSceneValue(\.ticketActions, ticket.map { actions(for: $0) })
        .sheet(isPresented: $sendingBack) {
            if let ticket, let target = sendBackTarget(ticket) { SendBackSheet(ticket: ticket, target: target) }
        }
        // ⌘V with a screenshot anywhere on the ticket, also while writing in the Thread, attaches it (decision E3).
        .pastesScreenshots { images in
            let id = ticketId
            _ = state.perform("Could not add the screenshot") {
                for image in images { try TicketScreenshots.save(image.data, name: image.name, ticketId: id, state: state) }
            }
        }
        .sheet(isPresented: $sendingPlanBack) {
            if let plan = pendingPlan { PlanSendBackSheet(plan: plan) }
        }
        .confirmationDialog("Reset this ticket?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It starts again from your first prompt and Iris files it again. Her questions, notes, links, plans and any agent work on it are removed.")
        }
        .confirmationDialog("Drop this ticket?", isPresented: $confirmDrop) {
            Button("Drop", role: .destructive) { move(to: .dropped) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A dropped ticket is closed on GitHub as not planned. You can reopen it later.")
        }
    }

    // MARK: Page

    private func page(_ t: Ticket) -> some View { flatPage(t) }

    private func flatPage(_ t: Ticket) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header(t)
                banner(t)
                tabBar(t)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            Divider()
            tabContent(t)
        }
    }

    private func header(_ t: Ticket) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(t.displayNumber)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(t.title)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                headerButtons(t)
            }
            HStack(spacing: 8) {
                StatusChip(status: t.status)
                TypeBadge(type: t.type)
                if let name = state.project(id: t.projectId)?.name { PlainChip(text: name) }
                if let area = t.area, !area.isEmpty { PlainChip(text: area) }
            }
        }
    }

    /// Open (in the Desk only) and one round "…" glass menu: everything else about the ticket lives in the menu,
    /// with Drop last, set apart and confirmed (LK11).
    @ViewBuilder private func headerButtons(_ t: Ticket) -> some View {
        HStack(spacing: 8) {
            if embedded {
                // In the Desk the ticket opens to its own page from here; Park lives in the inspector.
                Button { state.open(t) } label: { Label("Open", systemImage: "arrow.up.forward") }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
            Menu {
                if t.status == .blocked {
                    Button { resume() } label: { Label("Resume", systemImage: "play") }
                } else if !embedded && canMove(t, to: .parked) {
                    Button { move(to: .parked) } label: { Label("Park", systemImage: "pause") }
                }
                if t.status == .done {
                    Button { move(to: .draft) } label: { Label("Reopen", systemImage: "arrow.uturn.backward") }
                }
                // The answer to a broad Question can be done everywhere it found (decision SW9).
                if t.type == .question, t.status == .yourCall || t.status == .done {
                    Button { turnIntoSweep() } label: { Label("Turn into a Sweep", systemImage: "square.grid.2x2") }
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(t.displayNumber) \(t.title)", forType: .string)
                } label: { Label("Copy Number and Title", systemImage: "doc.on.doc") }
                Divider()
                // For debugging: start the ticket again from the first prompt.
                Button(role: .destructive) { confirmReset = true } label: { Label("Reset Ticket…", systemImage: "arrow.counterclockwise") }
                if canMove(t, to: .dropped) {
                    // Settings › General › Ask before dropping a ticket (on by default).
                    let ask = state.flag(Preference.confirmDrop)
                    Button(role: .destructive) { if ask { confirmDrop = true } else { move(to: .dropped) } } label: {
                        Label(ask ? "Drop Ticket…" : "Drop Ticket", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help("More actions")
        }
    }

    private func canMove(_ t: Ticket, to target: Status) -> Bool {
        Workflow.isAllowed(type: t.type, from: t.status, to: target, actor: .owner)
    }

    // MARK: Banner

    private func banner(_ t: Ticket) -> some View {
        let spec = bannerSpec(t)
        return TurnBanner(turn: t.turn,
                          message: spec.message,
                          actionTitle: spec.primaryTitle,
                          action: handler(spec.primary, t),
                          secondaryTitle: spec.secondaryTitle,
                          secondaryAction: handler(spec.secondary, t))
    }

    private func handler(_ action: BannerAction?, _ t: Ticket) -> (() -> Void)? {
        guard let action else { return nil }
        return { perform(action, t) }
    }

    private func bannerSpec(_ t: Ticket) -> BannerSpec {
        if let plan = pendingPlan {
            return BannerSpec(message: "The agent's plan waits for you: \(plan.reason), \(Format.count(plan.files.count, "file")). It does not start until you decide.",
                              primaryTitle: "Approve the plan", primary: .approvePlan,
                              secondaryTitle: "Send back…", secondary: .sendBackPlan)
        }
        if t.status == .draft && t.type == .question && !questionOptions.isEmpty {
            let rec = questionOptions.first(where: \.recommended)
            return BannerSpec(message: "Hatch prepared \(questionOptions.count) options" + (rec.map { "; it recommends \($0.key)." } ?? "."),
                              primaryTitle: "Choose an option", primary: .decideQuestion)
        }
        switch t.status {
        case .draft:
            return BannerSpec(message: "This is a draft. Submit it and Iris checks it before any work starts.",
                              primaryTitle: "Submit for check", primary: .submit)
        case .checking:
            return BannerSpec(message: "Iris is checking this ticket against other tickets and the Spec.")
        case .needsAnswers:
            let n = max(openQuestions, 0)
            let text: String = n > 0 ? "Answer \(Format.count(n, "question")) so work can start." : "Look at Iris's suggestion below so work can start."
            return BannerSpec(message: text, primaryTitle: "Answer below", primary: .tab(.overview))
        case .ready:
            return BannerSpec(message: "Ready. Hatch hands it to an agent as soon as a slot is free.")
        case .preparing:
            let what: String = t.type == .question ? "an answer" : (t.type == .sketch ? "variants" : "options")
            return BannerSpec(message: "An agent is preparing \(what). You will see it here when it is ready.")
        case .yourCall:
            return yourCallSpec(t)
        case .revising:
            return BannerSpec(message: "An agent is revising. Revision \(t.revision + 1) will appear here.")
        case .accepted:
            return BannerSpec(message: "Accepted. Hatch starts the build when a slot is free.")
        case .building:
            return BannerSpec(message: "An agent is building this in its own workspace.",
                              primaryTitle: "See progress", primary: .tab(.work))
        case .toVerify:
            return BannerSpec(message: "Verify the change in a Preview and say whether it looks right.",
                              primaryTitle: "Open in Previews", primary: .previews)
        case .fixing:
            return BannerSpec(message: "An agent is fixing what you reported.",
                              primaryTitle: "See progress", primary: .tab(.work))
        case .merged:
            let branch = state.project(id: t.projectId)?.config?.integrationBranch ?? "hatch"
            guard let ci = state.store.ciRecord(projectId: t.projectId) else {
                return BannerSpec(message: "Merged into \(branch). Hatch waits for its checks.")
            }
            return BannerSpec(message: "Merged into \(branch). CI is \(ci.summary), checked \(Format.ago(ci.checkedAt)).")
        case .done:
            return BannerSpec(message: "Done.", primaryTitle: nil, primary: nil)
        case .blocked:
            return BannerSpec(message: "Blocked. It waits for another ticket or for files another ticket is changing.",
                              primaryTitle: "See why", primary: .tab(.work))
        case .parked:
            return BannerSpec(message: "Parked. Nothing happens until you resume it.", primaryTitle: "Resume", primary: .resume)
        case .dropped:
            return BannerSpec(message: "Dropped. It is closed on GitHub as not planned.", primaryTitle: "Reopen", primary: .reopen)
        }
    }

    private func yourCallSpec(_ t: Ticket) -> BannerSpec {
        switch t.type {
        case .proposal where ComponentsSetup.changedRole(inBody: t.body) != nil && !questionOptions.isEmpty:
            // A design system change (CP3): its looks are options; the Designer draws them in place.
            return BannerSpec(message: "Choose one of \(questionOptions.count - 1) looks for \(ComponentsSetup.changedRole(inBody: t.body) ?? "the role"), or keep today's.",
                              primaryTitle: "Choose a Look", primary: .decideQuestion)
        case .proposal:
            let n = max(info.optionCount, 1)
            return BannerSpec(message: "Judge \(Format.count(n, "option")) against Today. Revision \(t.revision).",
                              primaryTitle: "Open the Proposal", primary: .openStage)
        case .sketch:
            return BannerSpec(message: "Choose a direction from the variants, or ask for more.",
                              primaryTitle: "Choose direction", primary: .tab(.options))
        case .question where !questionOptions.isEmpty:
            let rec = questionOptions.first(where: \.recommended)
            return BannerSpec(message: "Choose one of \(questionOptions.count) options" + (rec.map { "; the agent recommends \($0.key)." } ?? "."),
                              primaryTitle: "Choose an option", primary: .decideQuestion,
                              secondaryTitle: "Reply", secondary: .tab(.thread))
        default:
            return BannerSpec(message: "The agent replied. Answer in the thread, or close the question.",
                              primaryTitle: "Reply", primary: .tab(.thread),
                              secondaryTitle: "Close as answered", secondary: .closeAsAnswered)
        }
    }

    private func perform(_ action: BannerAction, _ t: Ticket) {
        switch action {
        case .openStage:
            StageLauncher.shared.open(ticket: t, state: state)
        case .tab(let target):
            tab = target
        case .submit:
            let id = t.id
            let moved: Ticket? = state.perform("Could not submit the ticket") { try state.store.move(id, to: .checking, actor: .owner, reason: "submitted for check") }
            if moved != nil { VettingBridge.start(ticketId: id, state: state) }
        case .previews:
            if opener?.isTicketWindow == true { HatchWindows.showMain() }
            state.navigate(to: .previews)
        case .closeAsAnswered:
            move(to: .done)
        case .resume:
            resume()
        case .reopen:
            move(to: .draft)
        case .decideQuestion:
            deciding = true
        case .approvePlan:
            if let plan = pendingPlan {
                _ = state.perform("Could not approve the plan") { try state.store.decidePlanReview(id: plan.id, approve: true, note: nil) }
            }
        case .sendBackPlan:
            sendingPlanBack = true
        }
    }

    private func move(to target: Status) {
        let id = ticketId
        _ = state.perform("Could not change the status") { try state.store.move(id, to: target, actor: .owner) }
    }

    /// Stops the agent working on the ticket, waits for it to end (its exit would otherwise block the reset ticket), then
    /// puts the ticket back to the owner's first prompt (decision IR16).
    private func reset() {
        let id = ticketId
        state.stopAgent(ticketId: id)
        Task { @MainActor in
            var waited = 0
            while state.agentRuns.contains(where: { $0.ticketId == id }) && waited < 50 { try? await Task.sleep(nanoseconds: 100_000_000); waited += 1 }
            _ = state.perform("Could not reset the ticket") { try TicketReset.run(store: state.store, ticketId: id) }
        }
    }

    private func turnIntoSweep() {
        let id = ticketId
        if let sweep = state.perform("Could not start the Sweep", { try state.store.promoteToSweep(from: id) }) { state.open(sweep) }
    }

    private func resume() {
        let id = ticketId
        _ = state.perform("Could not resume the ticket") { try state.store.resume(id, actor: .owner) }
    }

    // MARK: Keyboard (the Ticket menu)

    /// Where "send back with notes" goes from here: more variants or options, or fixes after verifying.
    private func sendBackTarget(_ t: Ticket) -> Status? {
        let target: Status
        switch t.status {
        case .yourCall: target = .revising
        case .toVerify: target = .fixing
        default: return nil
        }
        return canMove(t, to: target) ? target : nil
    }

    private func actions(for t: Ticket) -> TicketActions {
        let spec = bannerSpec(t)
        var resumeTitle: String?
        var resumeAction: (() -> Void)?
        switch t.status {
        case .blocked, .parked: resumeTitle = "Resume"; resumeAction = { resume() }
        case .done, .dropped:
            if canMove(t, to: .draft) { resumeTitle = "Reopen"; resumeAction = { move(to: .draft) } }
        default: break
        }
        return TicketActions(
            tabs: visibleTabs(t),
            selectTab: { tab = $0 },
            primaryTitle: spec.primaryTitle, primary: handler(spec.primary, t),
            secondaryTitle: spec.secondaryTitle, secondary: handler(spec.secondary, t),
            sendBack: sendBackTarget(t) == nil ? nil : { sendingBack = true },
            park: canMove(t, to: .parked) ? { move(to: .parked) } : nil,
            resumeTitle: resumeTitle, resume: resumeAction,
            drop: canMove(t, to: .dropped) ? { confirmDrop = true } : nil)
    }

    // MARK: Tabs

    private func visibleTabs(_ t: Ticket) -> [TicketTab] {
        var tabs: [TicketTab] = [.overview]
        if t.type == .sketch || t.type.isProposalLike { tabs.append(.options) }
        tabs.append(.thread)
        if t.type != .theme { tabs.append(.work) }
        tabs.append(.history)
        return tabs
    }

    private func tabTitle(_ tab: TicketTab, _ t: Ticket) -> String {
        switch tab {
        case .overview: return "Overview"
        case .options: return t.type == .sketch ? "Variants" : "Options"
        case .thread: return threadCount > 0 ? "Thread (\(threadCount))" : "Thread"
        case .work: return "Work"
        case .history: return "History"
        }
    }

    /// Plain underlined tabs that sit on the divider under the header.
    private func tabBar(_ t: Ticket) -> some View {
        HStack(spacing: 24) {
            ForEach(visibleTabs(t)) { id in
                let selected = id == tab
                Button { tab = id } label: {
                    VStack(spacing: 7) {
                        Text(tabTitle(id, t))
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                        Capsule().fill(selected ? Color.accentColor : Color.clear).frame(height: 2.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func tabContent(_ t: Ticket) -> some View {
        let current: TicketTab = visibleTabs(t).contains(tab) ? tab : .overview
        switch current {
        case .overview: TicketOverviewTab(ticket: t, split: !embedded)
        case .options: TicketOptionsTab(ticket: t, info: info)
        case .thread: TicketThreadTab(ticket: t, startKind: threadKind)
        case .work:
            TicketWorkTab(ticket: t, onInstruction: {
                threadKind = .instruction
                tab = .thread
            })
        case .history: TicketHistoryTab(ticket: t)
        }
    }

    // MARK: Data

    private func load() {
        guard let t = try? state.store.ticket(id: ticketId) else {
            ticket = nil
            return
        }
        if ticket != t { ticket = t }
        let options = (try? state.store.questionOptions(ticketId: ticketId)) ?? []
        if options != questionOptions { questionOptions = options }
        let openCount = ((try? state.store.questions(ticketId: ticketId, openOnly: true)) ?? []).count
        if openCount != openQuestions { openQuestions = openCount }
        let notes = ((try? state.store.notes(ticketId: ticketId)) ?? []).count
        let questions = ((try? state.store.questions(ticketId: ticketId)) ?? []).count
        if notes + questions != threadCount { threadCount = notes + questions }
        info = ProposalInfo.load(store: state.store, ticket: t)
        let plan = try? state.store.latestPlanReview(ticketId: ticketId)
        let waiting = plan?.state == .pending ? plan : nil
        if waiting != pendingPlan { pendingPlan = waiting }
        // A ticket window is not the main window's selection.
        if opener == nil, state.selectedTicketId != ticketId { state.selectedTicketId = ticketId }
    }
}


/// The owner answers a Question by choosing one of the options the agent offered (decision PS16). The choice, the
/// reason and the options become a decision, recorded in the database and written to the notebook.
struct QuestionDecisionSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let ticket: Ticket
    let options: [QuestionOption]
    @State private var choice: String?
    @State private var reason = ""
    @State private var kind = DecisionKind.architecture

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ticket.title).font(.title3.weight(.semibold))
                Text("Your choice is recorded as a decision that agents and Iris check later work against.")
                    .foregroundStyle(.secondary)
            }
            HXSetupGroup {
                ForEach(options, id: \.key) { o in
                    HXRadioRow(selected: choice == o.key, title: "\(o.key). \(o.title)",
                               detail: [o.detail, o.recommended ? o.why.map { "Recommended: \($0)" } : nil].compactMap { $0 }.joined(separator: "\n"),
                               recommended: o.recommended) { choice = o.key }
                }
            }
            HXSetupGroup {
                HXSetupRow("Why") {
                    TextField("Why", text: $reason, prompt: Text(recommendedChosen ? "The recommendation's reason" : "Optional"))
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing).labelsHidden()
                }
                HXSetupRow("Kind") {
                    Picker("Kind", selection: $kind) {
                        ForEach(DecisionKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Decide") { decide() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(choice == nil)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { choice = options.first(where: \.recommended)?.key }
    }

    private var recommendedChosen: Bool { options.first(where: \.recommended)?.key == choice }

    private func decide() {
        guard let choice else { return }
        let id = ticket.id, projectId = ticket.projectId, why = reason, kind = kind, prepared = ticket.status == .draft
        let done: Bool? = state.perform("Could not record the decision") {
            // A design system question changes the system first, so a refused change leaves the ticket open.
            try state.applyComponentDecision(ticket: ticket, choice: choice)
            // A Question Hatch prepared is still a draft; it takes its path on the way (decision CO11).
            if ticket.type == .proposal { _ = try state.store.decideComponentChange(ticketId: id, choice: choice, reason: why) }
            else if prepared { _ = try state.store.decidePreparedQuestion(ticketId: id, choice: choice, reason: why, kind: kind) }
            else { _ = try state.store.decideQuestion(ticketId: id, choice: choice, reason: why, kind: kind) }
            return true
        }
        if done == true {
            state.notebookChanged(projectId: projectId)
            dismiss()
        }
    }
}


/// Send a ticket back with notes: the note goes to the agent as an instruction and the ticket moves to the status
/// that makes it work again (Revising for a Sketch or Proposal, Fixing after verifying). The same two writes the
/// Sketch board and Previews make, so the history reads the same.
struct SendBackSheet: View {
    let ticket: Ticket
    let target: Status
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""

    private var trimmed: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send \(ticket.displayNumber) back").font(.headline)
            Text("The agent reads your notes and the ticket moves to \(target.displayName).")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send Back") { send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func send() {
        let id = ticket.id, body = trimmed, status = target
        let done: Ticket? = state.perform("Send back") {
            try state.store.addNote(id, kind: .instruction, author: "owner", body: body)
            return try state.store.move(id, to: status, actor: .owner, reason: body)
        }
        if done != nil { dismiss() }
    }
}

/// Sends an agent's plan back with a note saying what to change (decision DC8).
struct PlanSendBackSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let plan: PlanReview
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send the plan back").font(.title3.weight(.semibold))
            Text(plan.files.prefix(10).joined(separator: "\n") + (plan.files.count > 10 ? "\n+ \(plan.files.count - 10) more" : ""))
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            TextField("What should change?", text: $note, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3...6)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send Back") {
                    let id = plan.id, text = note
                    if state.perform("Could not send the plan back", { try state.store.decidePlanReview(id: id, approve: false, note: text) }) != nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 460)
    }
}
