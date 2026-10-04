import SwiftUI
import AppKit
import CryptoKit
import UniformTypeIdentifiers
import HatchCore

// Screenshots (decision E3): paste one with ⌘V wherever a ticket is being written or looked at, drop or choose one,
// capture a window, and mark it up with a box, an arrow or a note before it is saved.

// MARK: - The clipboard

enum ScreenshotClipboard {
    /// The images on the clipboard: image files copied in Finder, or image data from a screenshot or an app. Nil when
    /// there are none, so a normal text paste goes ahead.
    static func images(_ board: NSPasteboard = .general) -> [(name: String, data: Data)]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = board.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            let files = urls.filter(isImage).compactMap { url in (try? Data(contentsOf: url)).map { (url.lastPathComponent, $0) } }
            if !files.isEmpty { return files }
        }
        let types = board.types ?? []
        guard types.contains(.png) || types.contains(.tiff) || types.contains(NSPasteboard.PasteboardType("public.jpeg")) else { return nil }
        guard let image = NSImage(pasteboard: board), let png = pngData(image) else { return nil }
        return [("pasted.png", png)]
    }

    /// A clipboard with text on it is a text paste, even when an image comes along (copying from a web page).
    static func isImageOnly(_ board: NSPasteboard = .general) -> Bool {
        !(board.types ?? []).contains(.string)
    }

    static func isImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "webp"].contains(url.pathExtension.lowercased())
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - ⌘V anywhere

/// One ⌘V watcher for the whole app. Each view that takes screenshots registers itself for its window; the newest one
/// wins, so the Decide session over the Desk gets the paste, not the Desk underneath. A paste with text on the
/// clipboard, or in a window nobody registered for (a sheet with a text field), goes ahead as usual.
@MainActor
final class ScreenshotPasteCenter {
    static let shared = ScreenshotPasteCenter()

    private struct Target { let id: UUID; weak var window: NSWindow?; let take: ([(name: String, data: Data)]) -> Void }
    private var targets: [Target] = []
    private var monitor: Any?

    func register(_ id: UUID, window: NSWindow, take: @escaping ([(name: String, data: Data)]) -> Void) {
        targets.removeAll { $0.id == id || $0.window == nil }
        targets.append(Target(id: id, window: window, take: take))
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { ScreenshotPasteCenter.shared.handle(event) }
        }
    }

    func unregister(_ id: UUID) {
        targets.removeAll { $0.id == id }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v",
              let target = targets.last(where: { $0.window != nil && $0.window === event.window }),
              ScreenshotClipboard.isImageOnly(), let images = ScreenshotClipboard.images() else { return event }
        target.take(images)
        return nil
    }
}

private struct PastesScreenshots: ViewModifier {
    let take: ([(name: String, data: Data)]) -> Void
    @State private var id = UUID()
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window = $0 })
            .onChange(of: window) { _, w in if let w { ScreenshotPasteCenter.shared.register(id, window: w, take: take) } }
            .onAppear { if let window { ScreenshotPasteCenter.shared.register(id, window: window, take: take) } }
            .onDisappear { ScreenshotPasteCenter.shared.unregister(id) }
    }
}

extension View {
    /// ⌘V with an image on the clipboard hands the image to `take` instead of pasting nothing into a text field.
    func pastesScreenshots(_ take: @escaping ([(name: String, data: Data)]) -> Void) -> some View {
        modifier(PastesScreenshots(take: take))
    }
}

/// Finds the window a SwiftUI view is in.
private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { found(view.window) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { found(view.window) }
    }
}

// MARK: - Saving to a ticket

enum TicketScreenshots {
    /// Saves an image under `attachments/<ticket>/` in the Hatch folder and records it on the ticket.
    @discardableResult
    static func save(_ data: Data, name: String, ticketId: Int, state: AppState) throws -> Attachment {
        let relative = "attachments/\(ticketId)"
        let dir = state.paths.root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = (name as NSString).pathExtension.lowercased()
        let file = "shot-\(Int(Date().timeIntervalSince1970 * 1000))\(ext.isEmpty ? ".png" : "." + ext)"
        try data.write(to: dir.appendingPathComponent(file))
        return try state.store.addAttachment(ticketId, path: "\(relative)/\(file)", sha: sha(data), kind: "screenshot", caption: name)
    }

    /// Writes a marked-up image over the attachment's file, so the ticket keeps one screenshot, not two.
    static func replace(_ attachment: Attachment, with data: Data, state: AppState) throws {
        let url = attachment.path.hasPrefix("/") ? URL(fileURLWithPath: attachment.path) : state.paths.root.appendingPathComponent(attachment.path)
        try data.write(to: url)
        try state.store.setAttachmentSha(attachment.id, sha: sha(data))
    }

    static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Mark-up

/// One mark on a screenshot, in coordinates from 0 to 1 so it draws the same on screen and in the saved image.
struct ShotMark: Identifiable, Equatable {
    enum Kind: Equatable { case box, arrow, note(String) }
    let id = UUID()
    var kind: Kind
    var from: CGPoint
    var to: CGPoint
}

/// The three tools of decision E3 on top of the image: drag for a box or an arrow, click for a note. Saving flattens
/// the marks into a new PNG at the image's own size.
struct ScreenshotMarkupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let data: Data
    /// Marks to start with (snapshot runs).
    var initial: [ShotMark] = []
    let save: (Data) -> Void
    /// Set when the view is in a window of its own rather than a sheet (Quick Capture), to close that window.
    var onClose: (() -> Void)? = nil
    /// Inside Quick Capture's bar: no title, a smaller canvas, Done instead of Save.
    var compact = false

    private func finish() { if let onClose { onClose() } else { dismiss() } }

    enum Tool: String, CaseIterable, Identifiable { case box = "Box", arrow = "Arrow", note = "Note"; var id: String { rawValue } }
    @State private var tool: Tool = .box
    @State private var marks: [ShotMark] = []
    @State private var drawing: ShotMark?
    @State private var notePoint: CGPoint?
    @State private var noteText = ""
    @FocusState private var noteFocused: Bool

    private var image: NSImage? { NSImage(data: data) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if !compact { Text("Mark up").font(.title3.weight(.semibold)) }
                Picker("Tool", selection: $tool) {
                    Label("Box", systemImage: "rectangle").tag(Tool.box)
                    Label("Arrow", systemImage: "arrow.up.right").tag(Tool.arrow)
                    Label("Note", systemImage: "text.bubble").tag(Tool.note)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Button { if !marks.isEmpty { marks.removeLast() } } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .keyboardShortcut("z", modifiers: .command).disabled(marks.isEmpty)
                Spacer()
                Text(hint).font(.callout).foregroundStyle(.secondary)
            }
            if let image {
                canvas(image)
            }
            if notePoint != nil {
                HStack {
                    TextField("Note on the screenshot", text: $noteText).textFieldStyle(.roundedBorder).focused($noteFocused)
                        .onSubmit(addNote)
                    Button("Add Note", action: addNote).disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { notePoint = nil; noteText = "" }
                }
            }
            HStack {
                Text("Marks are drawn into the saved image.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { finish() }.keyboardShortcut(.cancelAction)
                Button(compact ? "Done" : "Save") { if let png = render() { save(png) }; finish() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(compact ? 0 : 20)
        .frame(minWidth: compact ? nil : 640, idealWidth: compact ? nil : 900, minHeight: compact ? 360 : 480, idealHeight: compact ? 360 : 680)
        .onAppear { if marks.isEmpty { marks = initial } }
    }

    private var hint: String {
        switch tool {
        case .box: "Drag around what matters"
        case .arrow: "Drag from the note to the spot"
        case .note: "Click where the note goes"
        }
    }

    private func canvas(_ image: NSImage) -> some View {
        GeometryReader { geo in
            let fit = fitted(image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().frame(width: fit.width, height: fit.height)
                ShotMarksLayer(marks: marks + [drawing].compactMap { $0 }, size: fit, scale: 1)
            }
            .frame(width: fit.width, height: fit.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                guard tool != .note else { return }
                let a = norm(g.startLocation, fit), b = norm(g.location, fit)
                drawing = ShotMark(kind: tool == .box ? .box : .arrow, from: a, to: b)
            }.onEnded { g in
                if tool == .note {
                    notePoint = norm(g.location, fit); noteFocused = true
                } else if let d = drawing, hypot(d.to.x - d.from.x, d.to.y - d.from.y) > 0.01 {
                    marks.append(d)
                }
                drawing = nil
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func addNote() {
        let text = noteText.trimmingCharacters(in: .whitespaces)
        guard let p = notePoint, !text.isEmpty else { return }
        marks.append(ShotMark(kind: .note(text), from: p, to: p))
        notePoint = nil; noteText = ""
    }

    private func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let s = min(box.width / size.width, box.height / size.height, 1.5)
        return CGSize(width: size.width * s, height: size.height * s)
    }

    private func norm(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x / size.width, 0), 1), y: min(max(p.y / size.height, 0), 1))
    }

    @MainActor private func render() -> Data? { Self.flatten(data, marks: marks) }

    /// The image with its marks drawn in, at the image's pixel size, as PNG. Without marks it is the image unchanged.
    @MainActor static func flatten(_ data: Data, marks: [ShotMark]) -> Data? {
        guard let image = NSImage(data: data), let rep = NSBitmapImageRep(data: data) else { return nil }
        guard !marks.isEmpty else { return data }
        let pixels = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let view = ZStack(alignment: .topLeading) {
            Image(nsImage: image).resizable().frame(width: pixels.width, height: pixels.height)
            ShotMarksLayer(marks: marks, size: pixels, scale: max(1, pixels.width / 900))
        }
        .frame(width: pixels.width, height: pixels.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let out = renderer.nsImage else { return nil }
        return ScreenshotClipboard.pngData(out)
    }
}

/// Draws marks over an image of `size`. `scale` thickens lines and type for a large saved image.
struct ShotMarksLayer: View {
    let marks: [ShotMark]
    let size: CGSize
    let scale: CGFloat
    /// A fixed red, so a mark reads the same in light and dark and in the saved file.
    static let ink = Color(red: 0.92, green: 0.18, blue: 0.16)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for m in marks {
                    let a = CGPoint(x: m.from.x * size.width, y: m.from.y * size.height)
                    let b = CGPoint(x: m.to.x * size.width, y: m.to.y * size.height)
                    switch m.kind {
                    case .box:
                        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                        ctx.stroke(Path(roundedRect: r, cornerRadius: 4 * scale), with: .color(Self.ink), lineWidth: 3 * scale)
                    case .arrow:
                        var p = Path(); p.move(to: a); p.addLine(to: b)
                        let angle = atan2(b.y - a.y, b.x - a.x), head = 14 * scale
                        for side in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
                            p.move(to: b)
                            p.addLine(to: CGPoint(x: b.x + head * cos(angle + side), y: b.y + head * sin(angle + side)))
                        }
                        ctx.stroke(p, with: .color(Self.ink), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round, lineJoin: .round))
                    case .note:
                        break
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            ForEach(marks) { m in
                if case .note(let text) = m.kind {
                    Text(text)
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6 * scale).padding(.vertical, 3 * scale)
                        .background(Self.ink, in: RoundedRectangle(cornerRadius: 5 * scale))
                        .fixedSize()
                        .position(x: m.from.x * size.width, y: m.from.y * size.height)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
