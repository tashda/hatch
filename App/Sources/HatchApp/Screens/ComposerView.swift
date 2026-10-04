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

/// New ticket: one prompt, the way you would tell a colleague, with screenshots if you like (decision WF-C1). Iris works
/// out the type, title, area and the rest (WF-T1), so there is nothing else to fill in. The panel on the right shows the
/// related tickets and Spec items local search finds while you type: free, no model call.
struct ComposerView: View {
    @EnvironmentObject var state: AppState

    @State private var prompt = ""
    @State private var projectId: Int?
    @State private var shots: [PendingShot] = []
    /// The screenshot open in the mark-up sheet.
    @State private var markingUp: PendingShot?
    @State private var links: [PendingLink] = []
    @State private var similar: [SimilarHit] = []
    @State private var specs: [SpecItem] = []
    @State private var hintTask: Task<Void, Never>?
    @State private var dropTargeted = false
    @State private var submitted: Ticket?
    @FocusState private var promptFocused: Bool
    @ObservedObject private var keys = ShortcutStore.shared

    private var hasInput: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSubmit: Bool { projectId != nil && hasInput }

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
                prompt = "After running a query, focus jumps to the toolbar. It should stay in the editor so I can change the query and run it again without the mouse."
            }
        }
        .onChange(of: similar.map(\.ticket.id)) { _, _ in publishCheck() }
        .onChange(of: specs.map(\.code)) { _, _ in publishCheck() }
        .onChange(of: hasInput) { _, _ in publishCheck() }
        .onDisappear { state.hatchCheck = nil }
        // ⌘V with a screenshot on the clipboard, wherever the cursor is (decision E3).
        .pastesScreenshots { images in shots += images.map { PendingShot(name: $0.name, data: $0.data) } }
        .sheet(item: $markingUp) { shot in
            ScreenshotMarkupSheet(data: shot.data) { png in
                if let i = shots.firstIndex(where: { $0.id == shot.id }) { shots[i] = PendingShot(name: shot.name, data: png) }
            }
        }
        .onChange(of: prompt) { _, _ in scheduleHints() }
        .onChange(of: projectId) { _, _ in scheduleHints() }
        .onChange(of: state.composerTitle) { _, _ in takeTitle() }
    }

    private func publishCheck() {
        state.hatchCheck = HatchCheckState(similar: similar, specs: specs, hasInput: hasInput, onLink: addLink)
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text(hasInput ? "Iris files it: type, title, area and priority. She asks only what she cannot guess." : "Write what you want; that is all Hatch needs.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button { state.navigate(to: .desk) } label: { Label("Cancel", systemImage: "xmark") }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button { create(draft: true) } label: { Label("Save as draft", systemImage: "square.and.arrow.down") }
                .buttonStyle(.glass)
                .disabled(!canSubmit)
            Button { create(draft: false) } label: { Label("Send to Iris", systemImage: "paperplane") }
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
        Form {
            Section {
                promptEditor
            } header: {
                Text("What do you want?")
            } footer: {
                Text("A bug, an idea, a question, a change, several things at once. Paste a crash log or a screenshot if it helps.")
            }
            Section("Screenshots") { screenshotArea }
            if !links.isEmpty { Section("Links") { linkList } }
            if state.projects.count > 1 {
                Section {
                    Picker("Project", selection: $projectId) {
                        ForEach(state.projects) { p in Text(p.name).tag(Optional(p.id)) }
                    }
                } footer: {
                    Text("Iris moves it if it clearly belongs to another project, and says so.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var promptEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $prompt)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(4)
                .focused($promptFocused)
            if prompt.isEmpty {
                Text("For example: Opening a big table on SQL Server is really slow.")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 260)
    }

    // MARK: Screenshots

    private var screenshotArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                    .foregroundStyle(.secondary)
                Text("Drop, paste (⌘V) or capture; click one to mark it up. Iris looks at them too.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose…") { chooseFiles() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Capture area") { captureArea() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .shortcut("capture.area", keys)
                    .help(keys.help("Drag a rectangle over anything on screen", "capture.area"))
                Button("Capture window") { captureWindow() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Pick a window to capture, for example the Echo window")
            }
            if !shots.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(shots) { shot in
                            ShotThumb(shot: shot, onMarkUp: { markingUp = shot }) { shots.removeAll { $0.id == shot.id } }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .background(dropTargeted ? Color.accentColor.opacity(0.12) : .clear)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in handleDrop(providers) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) } else if let direct = item as? URL { url = direct }
                guard let url, Self.isImage(url), let data = try? Data(contentsOf: url) else { return }
                let name = url.lastPathComponent
                DispatchQueue.main.async { shots.append(PendingShot(name: name, data: data)) }
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
            if let data = try? Data(contentsOf: url) { shots.append(PendingShot(name: url.lastPathComponent, data: data)) }
        }
    }

    /// Capture the Echo window (decision E3): the system picker lets the owner click any window.
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
            if let data, !data.isEmpty { shots.append(PendingShot(name: "capture-\(shots.count + 1).png", data: data)) }
        }
    }

    /// Drag a rectangle over anything on screen; the shot is attached at once (click it to mark it up).
    private func captureArea() {
        if let problem = AreaCapture.permissionProblem() { state.errorMessage = problem; return }
        let window = NSApp.keyWindow
        window?.orderOut(nil)
        Task {
            let data = await AreaCapture.run()
            window?.makeKeyAndOrderFront(nil)
            if let data {
                shots.append(PendingShot(name: "area-\(shots.count + 1).png", data: data))
            }
        }
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Links (from the panel's Link buttons; Iris adds her own)

    private var linkList: some View {
        ForEach(links) { link in
            HStack(spacing: 8) {
                Text(LinkText.name(link.kind)).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                Text(link.ticket.displayNumber).foregroundStyle(.secondary)
                Text(link.ticket.title).lineLimit(1)
                Spacer()
                Button { links.removeAll { $0.id == link.id } } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addLink(_ ticket: Ticket, kind: LinkKind) {
        if links.contains(where: { $0.ticket.id == ticket.id && $0.kind == kind }) { return }
        links.append(PendingLink(ticket: ticket, kind: kind))
    }

    // MARK: Hints (free, local)

    private func setUp() {
        takeTitle()
        if projectId == nil { projectId = state.projectFilterId ?? state.projects.first?.id }
        promptFocused = true
    }

    /// Text handed over by the palette (⌘Return), taken once.
    private func takeTitle() {
        guard let handed = state.composerTitle else { return }
        prompt = handed
        state.composerTitle = nil
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
        guard hasInput else { similar = []; specs = []; return }
        let (title, body) = HatchStore.workingTitle(prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        similar = ((try? state.store.similarTickets(projectId: projectId, title: title, body: body, limit: 5)) ?? []).map { SimilarHit(ticket: $0.ticket, score: $0.score) }
        specs = projectId.flatMap { try? state.store.searchSpec(projectId: $0, query: prompt, limit: 5) } ?? []
    }

    // MARK: Create

    private func create(draft: Bool) {
        guard let pid = projectId else { return }
        let text = prompt
        let pendingShots = shots
        let pendingLinks = links
        let paths = state.paths
        let created: Ticket? = state.perform("Could not create the ticket") {
            try state.store.db.transaction { () -> Ticket in
                let t = try state.store.capture(prompt: text, projectId: pid, draft: true)
                try Self.saveShots(pendingShots, for: t, store: state.store, root: paths.root)
                for link in pendingLinks { try state.store.link(from: t.id, to: link.ticket.id, kind: link.kind) }
                // Screenshots are saved before Iris starts, so she sees them (WF-C5).
                if draft { return t }
                return try state.store.move(t.id, to: .checking, actor: .owner, reason: "captured; Iris files it")
            }
        }
        guard let created else { return }
        if draft {
            state.open(created)
        } else {
            VettingBridge.start(ticketId: created.id, state: state)
            submitted = created
        }
        state.refresh()
    }

    static func saveShots(_ shots: [PendingShot], for ticket: Ticket, store: HatchStore, root: URL) throws {
        guard !shots.isEmpty else { return }
        let relative = "attachments/\(ticket.id)"
        let dir = root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (index, shot) in shots.enumerated() {
            let ext = (shot.name as NSString).pathExtension.lowercased()
            let fileName = "shot-\(index + 1).\(ext.isEmpty ? "png" : ext)"
            try shot.data.write(to: dir.appendingPathComponent(fileName))
            let sha = SHA256.hash(data: shot.data).map { String(format: "%02x", $0) }.joined()
            try store.addAttachment(ticket.id, path: "\(relative)/\(fileName)", sha: sha, kind: "screenshot", caption: shot.name)
        }
    }

    // MARK: After sending

    private func submittedView(_ ticket: Ticket) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ticket.displayNumber) sent to Iris").font(.title3.weight(.semibold))
                        Text(ticket.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { resetForm() } label: { Label("New ticket", systemImage: "plus") }
                        .buttonStyle(.glass)
                    Button { state.open(ticket) } label: { Label("Open ticket", systemImage: "arrow.right") }
                        .buttonStyle(.glassProminent)
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
        prompt = ""
        shots = []
        links = []
        similar = []
        specs = []
        promptFocused = true
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
                    Text("Start typing and related tickets and Spec items appear here.")
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
            Text("After you send it")
                .font(.subheadline.weight(.semibold))
            Text("Iris files it: what kind of work it is, a clear title and text, the area, the priority and the links. She asks only what she cannot guess, with her guess picked, and checks design work against the components and earlier decisions. Everything she sets can be changed on the ticket.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}
