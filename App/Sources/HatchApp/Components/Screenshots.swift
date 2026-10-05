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

    private struct UncheckedEvent: @unchecked Sendable { let event: NSEvent? }
    private struct Target { let id: UUID; weak var window: NSWindow?; let take: ([(name: String, data: Data)]) -> Void }
    private var targets: [Target] = []
    private var monitor: Any?

    func register(_ id: UUID, window: NSWindow, take: @escaping ([(name: String, data: Data)]) -> Void) {
        targets.removeAll { $0.id == id || $0.window == nil }
        targets.append(Target(id: id, window: window, take: take))
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // NSEvent is not Sendable; local monitors run on the main thread, so the hop is safe.
            let box = UncheckedEvent(event: event)
            return MainActor.assumeIsolated { UncheckedEvent(event: ScreenshotPasteCenter.shared.handle(box.event!)) }.event
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

/// Box and Arrow over a screenshot (decision E3), the editor both Quick Capture and the mark-up sheet use: a row of
/// icon tools, Undo and Clear, and the image with its marks. Marks are kept as data until they are drawn into the
/// file, so they can be changed again later.
struct MarkupEditor<Trailing: View>: View {
    let image: NSImage
    @Binding var marks: [ShotMark]
    /// A fixed canvas height (Quick Capture); nil lets the canvas fill the space it is given.
    var canvasHeight: CGFloat? = nil
    @ViewBuilder var trailing: () -> Trailing

    enum Tool { case box, arrow }
    @State private var tool: Tool = .box
    @State private var drawing: ShotMark?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 2) {
                toolButton(.box, "rectangle", "Box")
                toolButton(.arrow, "arrow.up.right", "Arrow")
                Divider().frame(height: 18).padding(.horizontal, 8)
                iconButton("arrow.uturn.backward", "Undo") { if !marks.isEmpty { marks.removeLast() } }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(marks.isEmpty)
                iconButton("xmark.circle", "Clear the marks") { marks = [] }
                    .disabled(marks.isEmpty)
                Text(tool == .box ? "Drag around what matters" : "Drag towards the spot")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 10)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing()
            }
            canvas
        }
        .hatchMark("MarkupEditor")
    }

    private func toolButton(_ t: Tool, _ symbol: String, _ name: String) -> some View {
        Button { tool = t } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 28)
                .foregroundStyle(tool == t ? Color.primary : Color.secondary)
                .background(tool == t ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(name)
        .accessibilityLabel(name)
    }

    private func iconButton(_ symbol: String, _ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .focusEffectDisabled()
        .help(name)
        .accessibilityLabel(name)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let fit = Self.fitted(image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().frame(width: fit.width, height: fit.height)
                ShotMarksLayer(marks: marks + [drawing].compactMap { $0 }, size: fit, scale: 1)
            }
            .frame(width: fit.width, height: fit.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                drawing = ShotMark(kind: tool == .box ? .box : .arrow, from: Self.norm(g.startLocation, fit), to: Self.norm(g.location, fit))
            }.onEnded { _ in
                if let d = drawing, hypot(d.to.x - d.from.x, d.to.y - d.from.y) > 0.01 { marks.append(d) }
                drawing = nil
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: canvasHeight)
    }

    static func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let s = min(box.width / size.width, box.height / size.height, 1.5)
        return CGSize(width: size.width * s, height: size.height * s)
    }

    static func norm(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x / size.width, 0), 1), y: min(max(p.y / size.height, 0), 1))
    }
}

/// The mark-up sheet on the New Ticket page and a ticket's screenshots: the editor, then Cancel and Save, which
/// flattens the marks into a new PNG at the image's own size.
struct ScreenshotMarkupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let data: Data
    /// Marks to start with (snapshot runs).
    var initial: [ShotMark] = []
    let save: (Data) -> Void

    @State private var marks: [ShotMark] = []

    var body: some View {
        VStack(spacing: 16) {
            if let image = NSImage(data: data) {
                MarkupEditor(image: image, marks: $marks) { EmptyView() }
            }
            HStack {
                Text("Marks are drawn into the saved image.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { if let png = render() { save(png) }; dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 900, minHeight: 480, idealHeight: 680)
        .onAppear { if marks.isEmpty { marks = initial } }
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
        .hatchMark("ShotMarksLayer")
    }
}
