import SwiftUI
import AppKit
import CryptoKit
import UniformTypeIdentifiers
import HatchCore

/// A link with the ticket on the other end, for the Links list.
struct LinkEntry: Identifiable {
    let link: TicketLink
    let outgoing: Bool
    let other: Ticket
    var id: String { "\(link.fromId)-\(link.toId)-\(link.kind.rawValue)" }
}

/// Overview: description, screenshots, links, and the facts on the right (decision F1).
struct TicketOverviewTab: View {
    let ticket: Ticket
    /// Description and details as two separate panels (the ticket's own page); false stacks them in one scroll.
    var split = false
    @EnvironmentObject var state: AppState
    @Environment(\.ticketOpener) private var opener

    @State private var attachments: [Attachment] = []
    @State private var linkEntries: [LinkEntry] = []
    @State private var parentTheme: Ticket?
    @State private var parentProgress: (done: Int, total: Int) = (0, 0)
    @State private var children: [Ticket] = []
    @State private var childProgress: (done: Int, total: Int) = (0, 0)
    @State private var specLines: [SpecItem] = []
    @State private var specCodes: [String] = []
    @State private var tokens: (input: Int, output: Int) = (0, 0)
    @State private var pendingSync = 0

    @State private var editing = false
    @State private var editTitle = ""
    @State private var editBody = ""
    @State private var showAddLink = false
    @State private var linkRef = ""
    @State private var linkKind: LinkKind = .related

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            // In the Desk the Iris inspector already shows this review; showing it twice only adds noise.
            if split || !state.showAskPanel { IrisReviewView(ticketId: ticket.id) }
            if ticket.type == .theme { themeSection }
            if ticket.type == .sweep { SweepItemsSection(ticket: ticket) }
            descriptionSection
            attachmentSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Facts and links as one quiet property rail: no boxes, just labelled rows and hairlines.
    private var rail: some View {
        VStack(alignment: .leading, spacing: 18) {
            detailsCard
            Divider()
            linkSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        Group {
            if split {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView { mainColumn.padding(22) }
                    Divider()
                    ScrollView { rail.padding(18) }.frame(width: 310)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        mainColumn
                        Divider()
                        rail
                    }
                    .padding(20)
                }
            }
        }
        .id(ticket.id)
        .autoReload(every: 5) { load() }
    }

    // MARK: Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemeHeader(theme: ticket, done: childProgress.done, total: childProgress.total)
            if children.isEmpty {
                Text("Nothing under this Goal yet. Pick this Goal when you create a ticket.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(Phase.allCases, id: \.self) { phase in
                let inPhase: [Ticket] = children.filter { $0.status.phase == phase }
                if !inPhase.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(phase.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(inPhase) { child in
                            TicketLine(ticket: child, projectName: "")
                                .contentShape(Rectangle())
                                .onTapGesture { TicketOpener.go(opener, child, state) }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description")
                    .font(.headline)
                Spacer()
                if !editing {
                    Button("Edit") {
                        editTitle = ticket.title
                        editBody = ticket.body
                        editing = true
                    }
                    .controlSize(.small)
                }
            }
            if editing {
                editor
            } else if ticket.body.isEmpty {
                Text("No description.")
                    .foregroundStyle(.secondary)
            } else {
                DescriptionBody(text: ticket.body)
            }
            originalDisclosure
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $editTitle)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $editBody)
                .font(.body)
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Button("Save") { saveEdit() }
                    .buttonStyle(.glassProminent)
                    .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") { editing = false }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder private var originalDisclosure: some View {
        let changedTitle: Bool = (ticket.originalTitle ?? ticket.title) != ticket.title
        let changedBody: Bool = (ticket.originalBody ?? ticket.body) != ticket.body
        if changedTitle || changedBody {
            DisclosureGroup("Your original text") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ticket.originalTitle ?? ticket.title)
                        .font(.body.weight(.semibold))
                    Text(ticket.originalBody ?? ticket.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.callout)
        }
    }

    private func saveEdit() {
        let id = ticket.id
        let newTitle = editTitle
        let newBody = editBody
        let ok: Ticket? = state.perform("Could not save the text") { try state.store.update(id, title: newTitle, body: newBody, actor: .owner) }
        if ok != nil { editing = false }
    }

    // MARK: Screenshots

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(attachments.isEmpty ? "Screenshots" : "Screenshots (\(attachments.count))")
                    .font(.headline)
                if attachments.isEmpty { Text("None").font(.callout).foregroundStyle(.tertiary) }
                Spacer()
                Button { addScreenshot() } label: { Label("Add screenshot", systemImage: "plus") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Add a screenshot")
            }
            if attachments.isEmpty {
                EmptyView()
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(attachments) { attachment in
                        AttachmentThumb(attachment: attachment)
                    }
                }
            }
        }
    }

    private func addScreenshot() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let id = ticket.id
        let relative = "attachments/\(id)"
        let dir = state.paths.root.appendingPathComponent(relative, isDirectory: true)
        let urls = panel.urls
        _ = state.perform("Could not add the screenshot") {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var n = 0
            for url in urls {
                let data = try Data(contentsOf: url)
                n += 1
                let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
                let name = "shot-\(Int(Date().timeIntervalSince1970))-\(n).\(ext)"
                try data.write(to: dir.appendingPathComponent(name))
                let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                try state.store.addAttachment(id, path: "\(relative)/\(name)", sha: sha, kind: "screenshot", caption: url.lastPathComponent)
            }
        }
    }

    // MARK: Links

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Links").font(.headline)
                Spacer()
                Button { showAddLink = true } label: { Label("Add link", systemImage: "plus") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Link another ticket")
                    .popover(isPresented: $showAddLink, arrowEdge: .bottom) { addLinkPopover }
            }
            if linkEntries.isEmpty {
                Text("Nothing linked yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            ForEach(linkEntries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(LinkText.label(kind: entry.link.kind, outgoing: entry.outgoing))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button { remove(entry) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .help("Remove this link")
                    }
                    Button { TicketOpener.go(opener, entry.other, state) } label: {
                        HStack(spacing: 6) {
                            Text(entry.other.displayNumber).foregroundStyle(.secondary)
                            Text(entry.other.title).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        .font(.callout)
                    }
                    .buttonStyle(.plain)
                    StatusChip(status: entry.other.status)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var addLinkPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Link a ticket").font(.headline)
            Picker("Kind", selection: $linkKind) {
                ForEach(LinkKind.allCases.filter { $0 != .parent }, id: \.self) { kind in
                    Text(LinkText.name(kind)).tag(kind)
                }
            }
            .labelsHidden()
            TextField("#118", text: $linkRef)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addLink(); showAddLink = false }
            HStack {
                Spacer()
                Button("Add") { addLink(); showAddLink = false }
                    .buttonStyle(.borderedProminent)
                    .disabled(linkRef.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 240)
    }

    private func addLink() {
        let ref = linkRef
        let id = ticket.id
        let kind = linkKind
        let ok: Bool? = state.perform("Could not add the link") { () -> Bool in
            let other = try state.store.resolve(ref)
            try state.store.link(from: id, to: other.id, kind: kind)
            return true
        }
        if ok != nil { linkRef = "" }
    }

    private func remove(_ entry: LinkEntry) {
        let from = entry.link.fromId
        let to = entry.link.toId
        let kind = entry.link.kind
        _ = state.perform("Could not remove the link") { try state.store.unlink(from: from, to: to, kind: kind) }
    }

    // MARK: Details card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16, alignment: .topLeading)], alignment: .leading, spacing: 14) {
            MetaRow(label: "Type") { Text(ticket.type.displayName) }
            MetaRow(label: "Project") { Text(projectLine) }
            if let parentTheme {
                MetaRow(label: "Goal") {
                    Button {
                        TicketOpener.go(opener, parentTheme, state)
                    } label: {
                        Text("\(parentTheme.title) (\(parentProgress.done) of \(parentProgress.total))")
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.link)
                }
            }
            if !specCodes.isEmpty {
                MetaRow(label: "Touches") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(specCodes, id: \.self) { code in
                            Text(specLabel(code)).font(.callout)
                        }
                    }
                }
            }
            if ticket.type.isProposalLike {
                MetaRow(label: "Revision") { Text("\(ticket.revision)") }
            }
            if let who = ticket.takenBy {
                MetaRow(label: "Agent") { Text(who) }
            }
            MetaRow(label: "GitHub") { Text(githubLine) }
            MetaRow(label: "Cost so far") { Text(costLine) }
            MetaRow(label: "Created") { Text(Format.clock(ticket.createdAt)) }
            MetaRow(label: "Changed") { Text(Format.ago(ticket.updatedAt)) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var projectLine: String {
        let name: String = state.project(id: ticket.projectId)?.name ?? "?"
        if let area = ticket.area, !area.isEmpty { return "\(name) · \(area)" }
        return name
    }

    private var githubLine: String {
        guard let n = ticket.ghNumber else { return "Not on GitHub yet" }
        if pendingSync > 0 { return "Issue #\(n) · \(Format.count(pendingSync, "change")) waiting" }
        return "Issue #\(n) · synced"
    }

    private var costLine: String {
        let total = tokens.input + tokens.output
        if total == 0 { return "No tokens used" }
        return "\(Format.tokens(total)) tokens (\(Format.tokens(tokens.input)) in, \(Format.tokens(tokens.output)) out)"
    }

    private func specLabel(_ code: String) -> String {
        if let item = specLines.first(where: { $0.code == code }) { return "\(code) \(item.text)" }
        return code
    }

    // MARK: Data

    private func load() {
        let store = state.store
        let id = ticket.id
        attachments = (try? store.attachments(ticketId: id)) ?? []
        var entries: [LinkEntry] = []
        for item in (try? store.links(ticketId: id)) ?? [] {
            let otherId: Int = item.outgoing ? item.link.toId : item.link.fromId
            if item.link.kind == .parent && item.outgoing { continue }
            if let other = try? store.ticket(id: otherId) {
                entries.append(LinkEntry(link: item.link, outgoing: item.outgoing, other: other))
            }
        }
        linkEntries = entries
        if let parentId = ticket.parentId, let theme = try? store.ticket(id: parentId) {
            parentTheme = theme
            parentProgress = (try? store.themeProgress(parentId)) ?? (done: 0, total: 0)
        } else {
            parentTheme = nil
        }
        if ticket.type == .theme {
            children = (try? store.tickets(TicketFilter(parentId: id))) ?? []
            childProgress = (try? store.themeProgress(id)) ?? (done: 0, total: 0)
        }
        let info = ProposalInfo.load(store: store, ticket: ticket)
        var codes: [String] = info.specs
        if let pending = (try? store.pendingSuggestion(ticketId: id)) ?? nil {
            for code in pending.specTouches where !codes.contains(code) { codes.append(code) }
        }
        specCodes = codes
        specLines = (try? store.specItems(projectId: ticket.projectId)) ?? []
        tokens = (try? store.tokenTotals(ticketId: id)) ?? (input: 0, output: 0)
        pendingSync = ((try? store.pendingOps(ticketId: id)) ?? []).count
    }
}

/// One labelled fact in the details card.
struct MetaRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .hatchMark("MetaRow")
    }
}


/// A description written as "What / Why / Scope / Done when" lines is shown as labelled rows; anything else stays plain text.
struct DescriptionBody: View {
    let text: String

    private static let labels = ["What", "Why", "Scope", "Done when"]

    private var rows: [(label: String, text: String)]? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var out: [(String, String)] = []
        for line in lines {
            guard let label = Self.labels.first(where: { line.hasPrefix($0 + ":") }) else { return nil }
            out.append((label, String(line.dropFirst(label.count + 1)).trimmingCharacters(in: .whitespaces)))
        }
        return out.isEmpty ? nil : out
    }

    var body: some View {
        Group {
            if let rows {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.label.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(0.6)
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text(row.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                Text(text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .hatchMark("DescriptionBody")
    }
}


/// The several similar things a Sweep changes (decision SW5): one row each with where it stands, grouped by kind. The owner
/// leaves items out before the build, and marks them verified or sends one back once they are built (SW8).
struct SweepItemsSection: View {
    let ticket: Ticket
    /// In its own card on the ticket page; without one where a card already holds it (the Preview's verify card).
    var framed = true
    @EnvironmentObject var state: AppState
    @State private var items: [SweepItem] = []
    @State private var progress: (settled: Int, total: Int) = (0, 0)
    @State private var sendingBack: String?
    @State private var note = ""

    private var curating: Bool { [.yourCall, .revising, .accepted].contains(ticket.status) }
    private var verifying: Bool { ticket.status == .toVerify }

    var body: some View {
        Group {
            if framed { SectionCard("Items") { content } } else { content }
        }
        .autoReload(every: 4) { load() }
        .hatchMark("SweepItemsSection")
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    Text("The survey has not listed the items yet. The agent preparing this finds them first.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("\(progress.settled) of \(progress.total) done")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    ProgressView(value: Double(progress.settled), total: Double(max(progress.total, 1)))
                        .tint(Theme.finished)
                    ForEach(groups, id: \.kind) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            if groups.count > 1 || group.kind != nil {
                                Text(group.kind ?? "Other")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                            ForEach(group.items) { item in row(item) }
                        }
                    }
                }
            }
    }

    /// Kinds in the order the survey first named them; items without a kind last.
    private var groups: [(kind: String?, items: [SweepItem])] {
        var order: [String?] = []
        for i in items where !order.contains(where: { $0 == i.kind }) { order.append(i.kind) }
        order.sort { ($0 == nil ? 1 : 0) < ($1 == nil ? 1 : 0) }
        return order.map { kind in (kind, items.filter { $0.kind == kind }) }
    }

    private func row(_ item: SweepItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol(item.state))
                .foregroundStyle(item.state == .verified ? Theme.finished : Color.secondary)
                .frame(width: 18)
                .help(item.state.displayName)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout.monospaced())
                    .strikethrough(item.state == .dropped)
                    .foregroundStyle(item.state == .dropped ? Color.secondary : Color.primary)
                Text(item.file)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let n = item.note, !n.isEmpty {
                    Text(n).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            controls(item)
        }
    }

    @ViewBuilder private func controls(_ item: SweepItem) -> some View {
        if curating, item.state == .todo {
            HStack(spacing: 8) {
                Button("Own ticket") { act("Could not split the item off") { try state.store.splitOffSweepItem(ticketId: ticket.id, key: item.key) } }
                    .help("It turns out big: give it its own ticket, and the Sweep leaves it out")
                Button("Leave out") { act("Could not leave the item out") { try state.store.dropSweepItem(ticketId: ticket.id, key: item.key) } }
            }
            .buttonStyle(.borderless).controlSize(.small)
        } else if curating, item.state == .dropped {
            Button("Include") { act("Could not include the item") { try state.store.restoreSweepItem(ticketId: ticket.id, key: item.key) } }
                .buttonStyle(.borderless).controlSize(.small)
        } else if verifying, item.state == .built {
            HStack(spacing: 8) {
                Button("Verified") { act("Could not mark the item verified") { try state.store.verifySweepItem(ticketId: ticket.id, key: item.key) } }
                Button("Send back\u{2026}") { note = ""; sendingBack = item.key }
                    .popover(isPresented: Binding(get: { sendingBack == item.key }, set: { if !$0 { sendingBack = nil } }), arrowEdge: .bottom) { sendBackForm(item) }
            }
            .buttonStyle(.borderless).controlSize(.small)
        } else if verifying, item.state == .verified {
            Button("Send back\u{2026}") { note = ""; sendingBack = item.key }
                .buttonStyle(.borderless).controlSize(.small)
                .popover(isPresented: Binding(get: { sendingBack == item.key }, set: { if !$0 { sendingBack = nil } }), arrowEdge: .bottom) { sendBackForm(item) }
        }
    }

    private func sendBackForm(_ item: SweepItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What is wrong with \(item.name)?").font(.headline)
            TextField("Say what to change", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            HStack {
                Spacer()
                Button("Cancel") { sendingBack = nil }
                Button("Send back") {
                    let text = note, key = item.key
                    sendingBack = nil
                    act("Could not send the item back") { try state.store.sendBackSweepItem(ticketId: ticket.id, key: key, note: text) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }

    private func act<T>(_ message: String, _ work: () throws -> T) {
        _ = state.perform(message) { try work() }
        load()
    }

    private func symbol(_ state: SweepItemState) -> String {
        switch state {
        case .todo: "circle"
        case .building: "ellipsis.circle"
        case .built: "checkmark.circle"
        case .verified: "checkmark.circle.fill"
        case .dropped: "minus.circle"
        }
    }

    private func load() {
        items = (try? state.store.sweepItems(ticketId: ticket.id)) ?? []
        progress = (try? state.store.sweepProgress(ticketId: ticket.id)) ?? (0, 0)
    }
}
