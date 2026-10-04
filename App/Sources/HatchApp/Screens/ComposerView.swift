import SwiftUI
import AppKit
import CryptoKit
import UniformTypeIdentifiers
import HatchCore

/// A screenshot held in memory until the ticket exists (it is then saved under attachments/<ticket>/).
struct PendingShot: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
}

struct PendingLink: Identifiable {
    let id = UUID()
    let ticket: Ticket
    var kind: LinkKind
}

struct SimilarHit: Identifiable {
    let ticket: Ticket
    let score: Double
    var id: Int { ticket.id }
}

/// New ticket: one form with a Hatch check panel on the right (decisions E1, E2, E3, E5, E7).
struct ComposerView: View {
    @EnvironmentObject var state: AppState

    /// Starts as Settings › General › New ticket type; nil (Ask me) until you choose.
    @State private var type: TicketType?
    @State private var typeLoaded = false
    @State private var title = ""
    @State private var bodyText = ""
    @State private var projectId: Int?
    @State private var area = ""
    @State private var themeId: Int?
    @State private var shots: [PendingShot] = []
    /// The screenshot open in the mark-up sheet.
    @State private var markingUp: PendingShot?
    @State private var links: [PendingLink] = []
    @State private var linkRef = ""
    @State private var linkKind: LinkKind = .related
    @State private var similar: [SimilarHit] = []
    @State private var specs: [SpecItem] = []
    @State private var themes: [Ticket] = []
    @State private var hintTask: Task<Void, Never>?
    @State private var dropTargeted = false
    @State private var submitted: Ticket?

    private var project: Project? {
        guard let projectId else { return nil }
        return state.project(id: projectId)
    }

    private var areaNames: [String] { project?.config?.areas.map { $0.name } ?? [] }

    private var canSubmit: Bool {
        projectId != nil && type != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if let submitted {
                submittedView(submitted)
            } else {
                HStack(spacing: 0) {
                    form
                        .frame(minWidth: 400, maxWidth: .infinity)
                    if !state.showAskPanel {
                        Divider()
                        HatchCheckPanel(similar: similar, specs: specs, hasInput: hasInput, onLink: addLink)
                            .frame(width: 320)
                    }
                }
                actionBar
            }
        }
        .navigationTitle("New ticket")
        .onAppear {
            setUp()
            if Snapshots.folder != nil {
                type = .bug
                title = "Keep focus in the query after Run"
                bodyText = "After running a query, focus moves to the toolbar. Keep the keyboard focus in the query editor so the next query can be changed without reaching for the mouse."
                area = "Editor"
            }
        }
        .onChange(of: similar.map(\.ticket.id)) { _, _ in publishCheck() }
        .onChange(of: specs.map(\.code)) { _, _ in publishCheck() }
        .onChange(of: hasInput) { _, _ in publishCheck() }
        .onDisappear { state.hatchCheck = nil }
        // ⌘V with a screenshot on the clipboard, wherever the cursor is in the form (decision E3).
        .pastesScreenshots { images in shots += images.map { PendingShot(name: $0.name, data: $0.data) } }
        .sheet(item: $markingUp) { shot in
            ScreenshotMarkupSheet(data: shot.data) { png in
                if let i = shots.firstIndex(where: { $0.id == shot.id }) { shots[i] = PendingShot(name: shot.name, data: png) }
            }
        }
        .onChange(of: title) { _, _ in scheduleHints() }
        .onChange(of: bodyText) { _, _ in scheduleHints() }
        .onChange(of: projectId) { _, _ in projectChanged() }
        .onChange(of: state.composerTitle) { _, _ in takeTitle() }
    }

    private func publishCheck() {
        state.hatchCheck = HatchCheckState(similar: similar, specs: specs, hasInput: hasInput, onLink: addLink)
    }

    private var hasInput: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 10) {
            // Never silently disabled: when the type is all that is missing, say so.
            Text(type == nil && hasInput ? "Choose a type to save the ticket." : "A new ticket starts as a draft.")
                .font(.callout)
                .foregroundStyle(type == nil && hasInput ? Theme.you : Color.secondary)
            Spacer()
            Button { state.navigate(to: .desk) } label: { Label("Cancel", systemImage: "xmark") }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button { create(submit: false) } label: { Label("Save as draft", systemImage: "square.and.arrow.down") }
                .buttonStyle(.glass)
                .disabled(!canSubmit)
            Button { create(submit: true) } label: {
                Label(type == .theme ? "Create Theme" : "Submit for check", systemImage: type == .theme ? "plus" : "paperplane")
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSubmit)
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Form

    private var form: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                narrativeForm
                    .frame(minWidth: 500, maxWidth: .infinity)
                detailsForm
                    .frame(width: 280)
            }
            compactForm
        }
    }

    private var narrativeForm: some View {
        Form {
            Section("Ticket") { titleField }
            Section("Description") { bodyEditor }
            Section("Screenshots") { screenshotArea }
            Section("Links") { linkArea }
            if !branchText().isEmpty {
                Section("Branches") { branchLine }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var detailsForm: some View {
        Form {
            Section {
                typePicker
                pickers
            } header: {
                Text("Details")
            } footer: {
                Text(Self.typeHelp(type))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var compactForm: some View {
        Form {
            Section {
                typePicker
                titleField
                pickers
            } header: {
                Text("Ticket")
            } footer: {
                Text(Self.typeHelp(type))
            }
            Section("Description") {
                bodyEditor
            }
            Section("Screenshots") {
                screenshotArea
            }
            Section("Links") {
                linkArea
            }
            if !branchText().isEmpty {
                Section("Branches") { branchLine }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title").font(.callout.weight(.medium))
            TextField("Title", text: $title, prompt: Text("What needs to change?"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .font(.title3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typePicker: some View {
        Picker("Type", selection: $type) {
            if type == nil { Text("Choose…").tag(TicketType?.none) }
            ForEach(TicketType.allCases, id: \.self) { kind in
                Text(kind.displayName).tag(Optional(kind))
            }
        }
        .pickerStyle(.menu)
    }

    static func typeHelp(_ type: TicketType?) -> String {
        switch type {
        case nil: return "Choose what kind of ticket this is. Iris will suggest another type if it fits better."
        case .question: return "An idea or UX issue that is still words. You get a reply that has read the Spec and related tickets."
        case .sketch: return "Exploring a layout or flow before any Swift. You get 2 to 4 variants as HTML."
        case .proposal: return "Several options to compare in Swift. Hatch will suggest another type if it fits better."
        case .tweak: return "A small change with one obvious fix. No judging step."
        case .bug: return "Something that behaves wrongly. Say the steps, what you expected and what happened."
        case .theme: return "A group of related tickets, like \"Connection management\". It shows progress."
        }
    }

    private var pickers: some View {
        Group {
            Picker("Project", selection: $projectId) {
                ForEach(state.projects) { p in
                    Text(p.name).tag(Optional(p.id))
                }
            }
            Picker("Area", selection: $area) {
                Text("No area").tag("")
                ForEach(areaNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            Picker("Theme", selection: $themeId) {
                Text("No theme").tag(Int?.none)
                ForEach(themes) { theme in
                    Text(theme.title).tag(Optional(theme.id))
                }
            }
            .disabled(type == .theme)
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $bodyText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                if bodyText.isEmpty {
                    Text("What should change, and why. Write what you like; Iris will help structure it.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 220)
            if type == .proposal {
                Text("Useful for a Proposal: what, why, scope, constraints.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if type == .bug {
                Text("Useful for a Bug: steps, expected, actual.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Screenshots

    private var screenshotArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                    .foregroundStyle(.secondary)
                Text("Drop, paste (⌘V) or capture screenshots; click one to mark it up")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose…") { chooseFiles() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Paste") { pasteFromClipboard() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Capture window") { captureWindow() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Pick a window to capture, for example the Echo window")
            }
            if !shots.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(shots) { shot in
                            ShotThumb(shot: shot, onMarkUp: { markingUp = shot }) { remove(shot) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .background(dropTargeted ? Color.accentColor.opacity(0.12) : .clear)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func remove(_ shot: PendingShot) {
        shots.removeAll { $0.id == shot.id }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                }
                guard let url else { return }
                guard Self.isImage(url) else { return }
                guard let data = try? Data(contentsOf: url) else { return }
                let name = url.lastPathComponent
                DispatchQueue.main.async {
                    shots.append(PendingShot(name: name, data: data))
                }
            }
        }
        return handled
    }

    static func isImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "webp"].contains(url.pathExtension.lowercased())
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let data = try? Data(contentsOf: url) {
                shots.append(PendingShot(name: url.lastPathComponent, data: data))
            }
        }
    }

    /// Capture the Echo window (decision E3): the system picker lets the owner click any window.
    /// Runs `screencapture` off the main thread; cancelling the picker leaves no file and adds nothing.
    private func captureWindow() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hatch-capture-\(UUID().uuidString).png")
        Task {
            let data: Data? = await Task.detached { () -> Data? in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-w", "-x", file.path]
                do { try process.run() } catch { return nil }
                process.waitUntilExit()
                let result = try? Data(contentsOf: file)
                try? FileManager.default.removeItem(at: file)
                return result
            }.value
            if let data, !data.isEmpty {
                shots.append(PendingShot(name: "capture-\(shots.count + 1).png", data: data))
            }
        }
    }

    private func pasteFromClipboard() {
        if let images = ScreenshotClipboard.images() {
            shots += images.map { PendingShot(name: $0.name, data: $0.data) }
        } else {
            state.errorMessage = "The clipboard has no image."
        }
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Links

    private var linkArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(links) { link in
                HStack(spacing: 8) {
                    Text(LinkText.name(link.kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(link.ticket.displayNumber).foregroundStyle(.secondary)
                    Text(link.ticket.title).lineLimit(1)
                    Spacer()
                    Button { links.removeAll { $0.id == link.id } } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Picker("Kind", selection: $linkKind) {
                    ForEach(LinkKind.allCases.filter { $0 != .parent }, id: \.self) { kind in
                        Text(LinkText.name(kind)).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                TextField("#118", text: $linkRef)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: 120)
                    .onSubmit { addLinkFromField() }
                Button("Add link") { addLinkFromField() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(linkRef.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addLinkFromField() {
        let ref = linkRef
        guard let found: Ticket = state.perform("Could not find that ticket", { try state.store.resolve(ref) }) else { return }
        addLink(found, kind: linkKind)
        linkRef = ""
    }

    private func addLink(_ ticket: Ticket, kind: LinkKind) {
        if links.contains(where: { $0.ticket.id == ticket.id && $0.kind == kind }) { return }
        links.append(PendingLink(ticket: ticket, kind: kind))
    }

    private var branchLine: some View {
        let text: String = branchText()
        return Group {
            if !text.isEmpty {
                Text("Branches: \(text) (from the project settings)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func branchText() -> String {
        guard let config = project?.config else { return "" }
        var parts: [String] = []
        for repo in config.repos {
            switch repo.role {
            case .app: parts.append("App \u{2192} \(repo.branch)")
            case .designSystem: parts.append("Components \u{2192} \(repo.branch)")
            case .specimens: parts.append("Specimens \u{2192} \(repo.branch)")
            case .tickets, .notebook: break
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Hints (free, local)

    private func setUp() {
        if !typeLoaded {
            type = state.newTicketType
            typeLoaded = true
        }
        takeTitle()
        if projectId == nil {
            projectId = state.projectFilterId ?? state.projects.first?.id
        }
        loadThemes()
    }

    /// A title handed over by the palette (⌘Return), taken once.
    private func takeTitle() {
        guard let handed = state.composerTitle else { return }
        title = handed
        state.composerTitle = nil
    }

    private func projectChanged() {
        area = ""
        themeId = nil
        loadThemes()
        scheduleHints()
    }

    private func loadThemes() {
        guard let projectId else { themes = []; return }
        let all: [Ticket] = (try? state.store.tickets(TicketFilter(projectId: projectId, types: [.theme]))) ?? []
        themes = all.filter { !$0.status.isTerminal }
    }

    private func scheduleHints() {
        hintTask?.cancel()
        hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            runHints()
        }
    }

    private func runHints() {
        guard hasInput else {
            similar = []
            specs = []
            return
        }
        let hits = (try? state.store.similarTickets(projectId: projectId, title: title, body: bodyText, limit: 5)) ?? []
        similar = hits.map { SimilarHit(ticket: $0.ticket, score: $0.score) }
        if let projectId {
            specs = (try? state.store.searchSpec(projectId: projectId, query: title + " " + bodyText, limit: 5)) ?? []
        } else {
            specs = []
        }
    }

    // MARK: Create and submit

    private func create(submit: Bool) {
        guard let pid = projectId, let ticketType = type else { return }
        let ticketTitle = title
        let ticketBody = bodyText
        let ticketArea: String? = area.isEmpty ? nil : area
        let parent: Int? = ticketType == .theme ? nil : themeId
        let runCheck = submit && ticketType != .theme
        let created: Ticket? = state.perform("Could not create the ticket") {
            let t = try state.store.createTicket(projectId: pid, type: ticketType, title: ticketTitle, body: ticketBody,
                                                 area: ticketArea, parentId: parent, status: .draft, actor: .owner)
            try saveShots(for: t)
            for link in links {
                try state.store.link(from: t.id, to: link.ticket.id, kind: link.kind)
            }
            if runCheck {
                return try state.store.move(t.id, to: .checking, actor: .owner, reason: "submitted for check")
            }
            return t
        }
        guard let created else { return }
        if runCheck {
            VettingBridge.start(ticketId: created.id, state: state)
            submitted = created
        } else {
            state.open(created)
        }
    }

    private func saveShots(for ticket: Ticket) throws {
        guard !shots.isEmpty else { return }
        let relative = "attachments/\(ticket.id)"
        let dir = state.paths.root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (index, shot) in shots.enumerated() {
            let ext = (shot.name as NSString).pathExtension.lowercased()
            let fileName = "shot-\(index + 1).\(ext.isEmpty ? "png" : ext)"
            try shot.data.write(to: dir.appendingPathComponent(fileName))
            let digest = SHA256.hash(data: shot.data)
            let sha = digest.map { String(format: "%02x", $0) }.joined()
            try state.store.addAttachment(ticket.id, path: "\(relative)/\(fileName)", sha: sha, kind: "screenshot", caption: shot.name)
        }
    }

    // MARK: After submit

    private func submittedView(_ ticket: Ticket) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ticket.displayNumber) submitted")
                            .font(.title3.weight(.semibold))
                        Text(ticket.title)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { resetForm() } label: { Label("New ticket", systemImage: "plus") }
                        .buttonStyle(.glass)
                    Button { state.open(ticket) } label: { Label("Open ticket", systemImage: "arrow.right") }
                        .buttonStyle(.glassProminent)
                }
                if !VettingBridge.isAvailable {
                    Text("Iris is not connected in this build, so the check will not run on its own. The ticket waits in Checking.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                IrisReviewView(ticketId: ticket.id, showIdleMessage: true)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func resetForm() {
        submitted = nil
        title = ""
        bodyText = ""
        shots = []
        links = []
        similar = []
        specs = []
        area = ""
        themeId = nil
    }
}

struct ShotThumb: View {
    let shot: PendingShot
    var onMarkUp: () -> Void = {}
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = NSImage(data: shot.data) {
                Button(action: onMarkUp) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Mark up: box, arrow or note")
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 84, height: 84)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(3)
        }
    }
}

/// What the Iris inspector shows on the New ticket page.
struct HatchCheckState {
    let similar: [SimilarHit]
    let specs: [SpecItem]
    let hasInput: Bool
    let onLink: (Ticket, LinkKind) -> Void
}

/// The right-hand panel: related tickets and Spec items found locally while typing, and what happens after Submit (decision E2).
struct HatchCheckPanel: View {
    let similar: [SimilarHit]
    let specs: [SpecItem]
    let hasInput: Bool
    let onLink: (Ticket, LinkKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hatch check")
                    .font(.headline)
                Text("Found instantly. This is a local search: no network, no tokens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !hasInput {
                    Text("Start typing a title and related tickets and Spec items appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !similar.isEmpty { similarList }
                if !specs.isEmpty { specList }
                if hasInput && similar.isEmpty && specs.isEmpty {
                    Text("Nothing related found yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                afterSubmit
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.secondary.opacity(0.04))
    }

    private var similarList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related tickets")
                .font(.subheadline.weight(.semibold))
            VStack(spacing: 0) {
            ForEach(similar.indices, id: \.self) { index in
                let hit = similar[index]
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(hit.ticket.displayNumber)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(hit.ticket.title)
                            .font(.callout)
                            .lineLimit(2)
                    }
                    HStack {
                        StatusChip(status: hit.ticket.status)
                        Spacer()
                        Button("Link") { onLink(hit.ticket, .related) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 9)
                if index < similar.count - 1 { Divider() }
            }
            }
            .padding(.horizontal, 12)
            .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var specList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spec")
                .font(.subheadline.weight(.semibold))
            VStack(spacing: 0) {
            ForEach(specs.indices, id: \.self) { index in
                let item = specs[index]
                HStack(alignment: .top, spacing: 6) {
                    Text(item.code)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(item.text)
                        .font(.callout)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                if index < specs.count - 1 { Divider() }
            }
            }
            .padding(.horizontal, 12)
            .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var afterSubmit: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("After you submit")
                .font(.subheadline.weight(.semibold))
            Text("Iris compares the ticket with every other ticket and the Spec, and asks her questions before any work starts. She may also suggest a clearer text and a better type; you decide on both.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}
