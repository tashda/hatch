import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
import HatchCore

/// Quick Capture (decision WF-C2): a key that works from any app opens one glass bar, like Spotlight or Raycast. Write
/// what you want, paste a screenshot with ⌘V or drag over an area, press Return, and Iris files it. The menu bar item, the Ask panel's Make a Ticket and `hatch new` lead to the same capture.
@MainActor
final class QuickCapture: NSObject, NSWindowDelegate {
    static let shared = QuickCapture()

    private weak var state: AppState?
    private var panel: CapturePanel?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var keys: AnyCancellable?
    private var registered: KeyChord?
    /// While an area is dragged or a screenshot is marked up, losing focus does not close the bar.
    var holdOpen = false
    /// The bar's top centre on screen; it stays put while the bar grows with its content.
    private var anchor: NSPoint?
    /// What was typed and pasted, kept while the bar is closed, until it is sent or started fresh.
    let draft = QuickCaptureDraft()
    /// Clicks in other apps close the bar; the panel does not always lose key status for those.
    private var clickMonitor: Any?

    private override init() {}

    /// Registers the system-wide key, and registers it again when it is changed in Settings › Shortcuts.
    func start(state: AppState) {
        self.state = state
        installHandler()
        register(ShortcutStore.shared.chord("capture.quick"))
        keys = ShortcutStore.shared.$map.sink { [weak self] map in
            Task { @MainActor in self?.register(map.chord(for: "capture.quick")) }
        }
    }

    /// Opens the bar, optionally with text already in it (the Ask panel's Make a Ticket). Pressing the key again while
    /// it is open closes it, as Spotlight does.
    func show(prefill: String = "") {
        guard let state else { return }
        if let panel, panel.isVisible {
            if prefill.isEmpty { hide() } else { panel.makeKeyAndOrderFront(nil) }
            return
        }
        if !prefill.isEmpty { draft.prompt = prefill }
        let p = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: QuickCaptureView.width + 2 * QuickCaptureView.margin, height: 120),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.backgroundColor = .clear
        p.isOpaque = false
        // macOS draws the shadow from the bar's own shape, as for Spotlight; a SwiftUI shadow would be cut off at the
        // window's edge and show as a grey rectangle.
        p.hasShadow = true
        // Moved by dragging its edge or Iris's mark (WindowDragGesture), never by a drag on a screenshot being marked up.
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self
        let host = NSHostingController(rootView: QuickCaptureView(draft: draft, close: { [weak self] in self?.hide() })
            .environmentObject(state))
        // The window follows the bar's height as text, screenshots or a message are added.
        host.sizingOptions = [.preferredContentSize]
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        p.contentViewController = host
        p.setContentSize(host.view.fittingSize)
        place(p)
        panel = p
        p.makeKeyAndOrderFront(nil)
        p.invalidateShadow()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in QuickCapture.shared.clickedElsewhere() }
        }
    }

    func hide() {
        holdOpen = false
        panel?.orderOut(nil)
        panel = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    /// A click in another app, or in one of Hatch's own windows, closes the bar (it keeps the draft).
    private func clickedElsewhere() {
        guard !holdOpen, panel != nil else { return }
        hide()
    }

    /// Where the bar was last dragged to, or where Spotlight sits: centred, a little above the middle of the screen
    /// with the pointer. A remembered place on a screen that is no longer there is forgotten.
    private func place(_ p: NSPanel) {
        let d = UserDefaults.standard
        if let x = d.object(forKey: Self.anchorX) as? Double, let y = d.object(forKey: Self.anchorY) as? Double,
           NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(NSPoint(x: x, y: y)) }) {
            anchor = NSPoint(x: x, y: y)
        } else {
            let mouse = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
            let f = screen.visibleFrame
            anchor = NSPoint(x: f.midX, y: f.maxY - f.height * 0.22)
        }
        keepAnchored(p)
    }

    private static let anchorX = "hatch.quickCapture.x", anchorY = "hatch.quickCapture.y"

    /// Dragged somewhere: it opens there next time.
    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            guard let p = self.panel else { return }
            let top = NSPoint(x: p.frame.midX, y: p.frame.maxY)
            guard top != self.anchor else { return }
            self.anchor = top
            UserDefaults.standard.set(Double(top.x), forKey: Self.anchorX)
            UserDefaults.standard.set(Double(top.y), forKey: Self.anchorY)
        }
    }

    /// Puts the cursor after the remembered text rather than selecting it, so typing adds to it.
    func moveCaretToEnd() {
        guard let editor = panel?.firstResponder as? NSTextView else { return }
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    }

    private func keepAnchored(_ p: NSWindow) {
        guard let anchor else { return }
        let origin = NSPoint(x: anchor.x - p.frame.width / 2, y: anchor.y)
        if p.frame.origin.x != origin.x || p.frame.maxY != anchor.y { p.setFrameTopLeftPoint(origin) }
    }

    nonisolated func windowDidResize(_ notification: Notification) {
        Task { @MainActor in
            if let p = self.panel { self.keepAnchored(p); p.invalidateShadow() }
        }
    }


    /// Clicking elsewhere closes the bar, like Spotlight and Raycast; what was typed is gone only if nothing was sent.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            self.clickedElsewhere()
        }
    }

    /// Drag a rectangle over anything on screen: the bar steps aside while you drag and comes back with the picture.
    /// Nil when the drag was cancelled with Esc.
    func captureArea() async -> Data? {
        holdOpen = true
        panel?.orderOut(nil)
        let data = await AreaCapture.run()
        panel?.makeKeyAndOrderFront(nil)
        holdOpen = false
        return data
    }

    // MARK: The system-wide key

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in QuickCapture.shared.show() }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func register(_ chord: KeyChord?) {
        guard chord != registered else { return }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registered = chord
        guard let chord, let code = Self.keyCodes[chord.key] else { return }
        var mods: UInt32 = 0
        if chord.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
        if chord.modifiers.contains(.option) { mods |= UInt32(optionKey) }
        if chord.modifiers.contains(.control) { mods |= UInt32(controlKey) }
        if chord.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
        // "HTCH": Hatch's own signature, so the key is never mistaken for another app's.
        let id = EventHotKeyID(signature: 0x4854_4348, id: 1)
        RegisterEventHotKey(UInt32(code), mods, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    /// Key positions (the key at that place on any layout), for the keys a capture shortcut can use.
    static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
        "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N,
        "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
        "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6,
        "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, "space": kVK_Space, "return": kVK_Return,
    ]
}

/// A borderless panel that can take typing without bringing Hatch's other windows forward.
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// What the bar holds while it is closed: it opens again as it was left, until it is sent or started fresh.
@MainActor
final class QuickCaptureDraft: ObservableObject {
    @Published var prompt = ""
    @Published var shots: [PendingShot] = []
    @Published var projectId: Int?
    #if DEBUG
    /// `--quick-capture-markup <png>`: open with this screenshot in mark-up, to look at it without clicking.
    var openMarkupOnShow = false
    #endif

    var isEmpty: Bool { prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && shots.isEmpty }

    func reset() {
        prompt = ""
        shots = []
    }
}

/// The bar: Iris's mark, one field that grows with the text, and quiet controls on the right (project, start fresh,
/// capture an area, send). Screenshots appear as a row of thumbnails under the field. The same glass and radius as the
/// command palette, so the two read as one family (DESIGN.md).
struct QuickCaptureView: View {
    static let width: CGFloat = 680
    /// Room around the bar inside the transparent window; the window's own shadow is drawn outside it.
    static let margin: CGFloat = 0

    @EnvironmentObject var state: AppState
    @ObservedObject var draft: QuickCaptureDraft
    let close: () -> Void

    @State private var problem: String?
    /// The screenshot being marked up, inside the bar.
    @State private var markingUp: PendingShot?
    /// The name and key of the control under the pointer. Tooltips do not show for a panel while Hatch is not the
    /// active app, so the bar shows it itself, as Raycast does.
    @State private var hint: String?
    @ObservedObject private var keys = ShortcutStore.shared
    @FocusState private var focused: Bool

    private var canSend: Bool { draft.projectId != nil && !draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasTray: Bool { !draft.shots.isEmpty || problem != nil || markingUp != nil }

    var body: some View {
        VStack(spacing: 0) {
            field
            if hasTray {
                Divider().opacity(0.5)
                tray
            }
        }
        .frame(width: Self.width)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(Self.margin)
        // No window background: SwiftUI would otherwise paint the whole transparent window as a grey rectangle.
        .containerBackground(.clear, for: .window)
        // Drawn as the active window even while another app is in front, so the glass never turns grey.
        .environment(\.controlActiveState, .key)
        .pastesScreenshots { images in draft.shots += images.map { PendingShot(name: $0.name, data: $0.data) } }
        .onAppear {
            if draft.projectId == nil || !state.projects.contains(where: { $0.id == draft.projectId }) { draft.projectId = startProject }
            #if DEBUG
            if draft.openMarkupOnShow, let first = draft.shots.first { markingUp = first; draft.openMarkupOnShow = false }
            #endif
            DispatchQueue.main.async {
                focused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { QuickCapture.shared.moveCaretToEnd() }
            }
        }
    }

    // MARK: Parts

    private var field: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image("IrisIcon")
                .resizable().scaledToFit().frame(width: 20, height: 20)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 7 }
            TextField("What do you want?", text: $draft.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title2)
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit { send() }
                .onKeyPress(.escape) { close(); return .handled }
            HStack(spacing: 6) {
                if let hint {
                    Text(hint).font(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                        .padding(.trailing, 4)
                        .transition(.opacity)
                }
                if state.projects.count > 1 { projectMenu }
                if !draft.isEmpty {
                    Button { startFresh() } label: { Image(systemName: "eraser") }
                        .buttonStyle(.borderless)
                        .focusEffectDisabled()
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .shortcut("capture.fresh", keys)
                        .onHover { showHint($0, "Start fresh", "capture.fresh") }
                }
                Button { captureArea() } label: { Image(systemName: "rectangle.dashed") }
                    .buttonStyle(.borderless)
                    .focusEffectDisabled()
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .shortcut("capture.area", keys)
                    .onHover { showHint($0, "Capture an area", "capture.area") }
                Button { send() } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.semibold)).frame(width: 22, height: 22)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .focusEffectDisabled()
                .disabled(!canSend)
                .onHover { showHint($0, "Send to Iris  ↩", nil) }
            }
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 7 }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 17)
        // Dragging the bar anywhere but the text moves it; it opens there next time.
        .background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
    }

    private func showHint(_ hovering: Bool, _ title: String, _ id: String?) {
        withAnimation(.easeOut(duration: 0.12)) {
            hint = hovering ? title + (id.flatMap { keys.hint($0) }.map { "  \($0)" } ?? "") : nil
        }
    }

    private var projectMenu: some View {
        Menu {
            ForEach(state.projects) { p in Button(p.name) { draft.projectId = p.id } }
        } label: {
            Text(draft.projectId.flatMap { state.project(id: $0)?.name } ?? "Project").font(.callout)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.visible)
        .foregroundStyle(.secondary)
        .fixedSize()
        .help("The project it goes to. Iris moves it if it clearly belongs elsewhere.")
    }

    /// Screenshots under the field, pasted with ⌘V or captured: thumbnails, click one to mark it up.
    private var tray: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem {
                Text(problem).font(.callout).foregroundStyle(Theme.critical).fixedSize(horizontal: false, vertical: true)
            }
            if let shot = markingUp {
                ScreenshotMarkupSheet(data: shot.data, save: { png in
                    if let i = draft.shots.firstIndex(where: { $0.id == shot.id }) { draft.shots[i] = PendingShot(name: shot.name, data: png) }
                }, onClose: { markingUp = nil; focused = true }, compact: true)
            } else if !draft.shots.isEmpty {
                HStack(spacing: 8) {
                    ForEach(draft.shots) { shot in thumbnail(shot) }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func thumbnail(_ shot: PendingShot) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { markUp(shot) } label: {
                Group {
                    if let image = NSImage(data: shot.data) { Image(nsImage: image).resizable().scaledToFill() } else { Color.secondary.opacity(0.2) }
                }
                .frame(width: 56, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Mark up: box, arrow or note")
            Button { draft.shots.removeAll { $0.id == shot.id } } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .offset(x: 5, y: -5)
            .help("Remove")
        }
    }

    // MARK: Actions

    /// The project in the title bar, or the first one; never a remembered id the database does not have.
    private var startProject: Int? {
        if let id = state.projectFilterId, state.projects.contains(where: { $0.id == id }) { return id }
        return state.projects.first?.id
    }

    private func startFresh() {
        draft.reset()
        problem = nil
        focused = true
    }

    /// Mark-up opens inside the bar, under the field: Box, Arrow, Note, Undo, then Done.
    private func markUp(_ shot: PendingShot) { markingUp = shot }

    private func captureArea() {
        problem = AreaCapture.permissionProblem()
        if problem != nil { return }
        let draft = self.draft
        Task {
            if let data = await QuickCapture.shared.captureArea() {
                // Attached at once, nothing to confirm; click the thumbnail to mark it up.
                draft.shots.append(PendingShot(name: "area-\(draft.shots.count + 1).png", data: data))
            }
            focused = true
        }
    }

    /// Sends it to Iris, then starts fresh and closes: the next capture begins empty.
    private func send() {
        guard canSend, let pid = draft.projectId else { return }
        let text = draft.prompt
        let pending = draft.shots
        let root = state.paths.root
        let made: Ticket? = state.perform("Could not create the ticket") {
            try state.store.db.transaction { () -> Ticket in
                let t = try state.store.capture(prompt: text, projectId: pid, draft: true)
                // Screenshots are saved before Iris starts, so she sees them (WF-C5).
                try ComposerView.saveShots(pending, for: t, store: state.store, root: root)
                return try state.store.move(t.id, to: .checking, actor: .owner, reason: "captured; Iris files it")
            }
        }
        guard let made else { return }
        VettingBridge.start(ticketId: made.id, state: state)
        state.refresh()
        draft.reset()
        close()
    }
}

/// An area of the screen, chosen by dragging a rectangle. Uses macOS's own `screencapture -i -s`, so it looks and
/// behaves like ⇧⌘4: Space switches to a window, Esc cancels. The first time, macOS asks to allow Screen Recording.
enum AreaCapture {
    /// Nil when Hatch may record the screen. Otherwise macOS is asked (once; it shows its own prompt) and the text says
    /// what to do: without the permission a capture shows only the desktop.
    @MainActor static func permissionProblem() -> String? {
        if CGPreflightScreenCaptureAccess() { return nil }
        CGRequestScreenCaptureAccess()
        return "Hatch needs Screen Recording to capture an area. Allow it in System Settings › Privacy & Security › Screen Recording, then reopen Hatch."
    }

    static func run() async -> Data? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hatch-area-\(UUID().uuidString).png")
        return await Task.detached { () -> Data? in
            // A moment for the bar to leave the screen before the crosshair appears.
            try? await Task.sleep(nanoseconds: 150_000_000)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-s", "-x", file.path]
            do { try process.run() } catch { return nil }
            process.waitUntilExit()
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
            return data
        }.value
    }
}
