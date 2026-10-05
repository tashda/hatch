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
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var keys: AnyCancellable?
    private var registered: [UInt32: KeyChord] = [:]
    /// Why a snap could not start (no Screen Recording permission); the bar shows it when it opens.
    var startupProblem: String?
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
        register(ShortcutStore.shared.chord("capture.quick"), id: Self.openKeyID)
        register(ShortcutStore.shared.chord("capture.snap"), id: Self.snapKeyID)
        keys = ShortcutStore.shared.$map.sink { [weak self] map in
            Task { @MainActor in
                self?.register(map.chord(for: "capture.quick"), id: Self.openKeyID)
                self?.register(map.chord(for: "capture.snap"), id: Self.snapKeyID)
            }
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
        // One fixed size, never resized: resizing the window while SwiftUI draws its glass crashed (a recursion in
        // the glass material). The bar draws at the top; the rest of the window is transparent, so clicks there go
        // to whatever is behind it, and a click elsewhere closes the bar.
        let p = CapturePanel(contentRect: NSRect(origin: .zero, size: QuickCaptureView.windowSize),
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
        host.sizingOptions = []
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        p.contentViewController = host
        p.setContentSize(QuickCaptureView.windowSize)
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

    /// The shadow follows what is drawn; it is worked out again after the bar changes shape.
    func refreshShadow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.panel?.invalidateShadow() }
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

    // MARK: The system-wide keys

    private static let openKeyID: UInt32 = 1, snapKeyID: UInt32 = 2

    /// The snap key: drag over an area first, then the bar opens with the picture attached and the cursor in the text,
    /// so one key press and one drag replace opening the bar, clipping and writing. Esc during the drag leaves things
    /// as they were. With the bar already open it adds the picture to what is there.
    func snap() async {
        guard state != nil, !snapping else { return }
        if let problem = AreaCapture.permissionProblem() {
            startupProblem = problem
            if panel == nil { show() }
            return
        }
        snapping = true
        defer { snapping = false }
        let wasOpen = panel?.isVisible == true
        let data = wasOpen ? await captureArea() : await AreaCapture.run()
        guard let data else { return }
        draft.add(name: "area-\(draft.shots.count + 1).png", data: data)
        if !wasOpen { show() }
    }

    private var snapping = false

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == 0x4854_4348 else { return OSStatus(eventNotHandledErr) }
            Task { @MainActor in
                if id.id == QuickCapture.snapKeyID { await QuickCapture.shared.snap() } else { QuickCapture.shared.show() }
            }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func register(_ chord: KeyChord?, id keyID: UInt32) {
        guard chord != registered[keyID] else { return }
        if let old = hotKeys.removeValue(forKey: keyID) { UnregisterEventHotKey(old) }
        registered[keyID] = chord
        guard let chord, let code = Self.keyCodes[chord.key] else { return }
        var mods: UInt32 = 0
        if chord.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
        if chord.modifiers.contains(.option) { mods |= UInt32(optionKey) }
        if chord.modifiers.contains(.control) { mods |= UInt32(controlKey) }
        if chord.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
        // "HTCH": Hatch's own signature, so the key is never mistaken for another app's.
        let id = EventHotKeyID(signature: 0x4854_4348, id: keyID)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(code), mods, id, GetApplicationEventTarget(), 0, &ref)
        if let ref { hotKeys[keyID] = ref }
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

/// A screenshot in the bar with its marks. The marks stay data until the ticket is sent, so closing and reopening the
/// bar keeps them editable.
struct CaptureShot: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var original: Data
    var marks: [ShotMark] = []

    var image: NSImage? { NSImage(data: original) }

    /// The file sent with the ticket: the marks drawn in.
    @MainActor var pending: PendingShot {
        PendingShot(name: name, data: ScreenshotMarkupSheet.flatten(original, marks: marks) ?? original)
    }
}

/// What the bar holds while it is closed: it opens again as it was left, editor and marks included, until it is sent
/// or started fresh.
@MainActor
final class QuickCaptureDraft: ObservableObject {
    @Published var prompt = ""
    @Published var shots: [CaptureShot] = []
    @Published var projectId: Int?
    /// The screenshot open in the editor, if any.
    @Published var editing: CaptureShot.ID?

    var isEmpty: Bool { prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && shots.isEmpty }

    func add(name: String, data: Data) { shots.append(CaptureShot(name: name, original: data)) }

    func remove(_ id: CaptureShot.ID) {
        shots.removeAll { $0.id == id }
        if editing == id { editing = nil }
    }

    func reset() {
        prompt = ""
        shots = []
        editing = nil
    }
}

/// The bar: Iris's mark, one field that grows with the text, and quiet controls on the right (project, start fresh,
/// capture an area, send). Each screenshot is a small glass pill under it; clicking one opens it into the editor, a
/// second piece of glass, and Done folds it back. The bar itself looks the same with or without them. The same glass
/// and radius as the command palette (DESIGN.md).
struct QuickCaptureView: View {
    static let width: CGFloat = 680
    /// The window's fixed size: the bar with eight lines of text and the editor open fits.
    static let windowSize = CGSize(width: width, height: 760)
    static let margin: CGFloat = 0

    @EnvironmentObject var state: AppState
    @ObservedObject var draft: QuickCaptureDraft
    let close: () -> Void

    @State private var problem: String?
    /// The name and key of the control under the pointer. Tooltips do not show for a panel while Hatch is not the
    /// active app, so the bar shows it itself, as Raycast does.
    @State private var hint: String?
    @ObservedObject private var keys = ShortcutStore.shared
    @FocusState private var focused: Bool

    private var canSend: Bool { draft.projectId != nil && !draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var editingShot: CaptureShot? { draft.editing.flatMap { id in draft.shots.first { $0.id == id } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field
                .frame(width: Self.width)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(Theme.critical)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
            if let shot = editingShot, let image = shot.image {
                editor(shot, image)
                    .transition(.scale(scale: 0.15, anchor: .topLeading).combined(with: .opacity))
            } else if !draft.shots.isEmpty {
                pills
                    .transition(.opacity)
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: draft.editing)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: draft.shots.map(\.id))
        // No window background: SwiftUI would otherwise paint the whole transparent window as a grey rectangle.
        .containerBackground(.clear, for: .window)
        .pastesScreenshots { images in for i in images { draft.add(name: i.name, data: i.data) } }
        .onChange(of: draft.editing) { _, _ in QuickCapture.shared.refreshShadow() }
        .onChange(of: draft.shots.map(\.id)) { _, _ in QuickCapture.shared.refreshShadow() }
        .onChange(of: draft.prompt.count / 60) { _, _ in QuickCapture.shared.refreshShadow() }
        .onAppear {
            if draft.projectId == nil || !state.projects.contains(where: { $0.id == draft.projectId }) { draft.projectId = startProject }
            DispatchQueue.main.async {
                focused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { QuickCapture.shared.moveCaretToEnd() }
            }
            QuickCapture.shared.refreshShadow()
        }
    }

    // MARK: The bar

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
                .onKeyPress(.escape) {
                    if draft.editing != nil { draft.editing = nil } else { close() }
                    return .handled
                }
            HStack(spacing: 6) {
                if let hint {
                    Text(hint).font(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                        .padding(.trailing, 4)
                        .transition(.opacity)
                }
                if state.projects.count > 1 { projectMenu }
                if !draft.isEmpty {
                    QuietIconButton(symbol: "eraser") { startFresh() }
                        .shortcut("capture.fresh", keys)
                        .onHover { showHint($0, "Start fresh", "capture.fresh") }
                }
                QuietIconButton(symbol: "rectangle.dashed") { captureArea() }
                    .shortcut("capture.area", keys)
                    .onHover { showHint($0, "Capture an area", "capture.area") }
                SendButton(enabled: canSend) { send() }
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

    // MARK: Screenshots

    /// One small pill of glass per screenshot, left-aligned under the bar.
    private var pills: some View {
        HStack(spacing: 10) {
            ForEach(draft.shots) { shot in
                pill(shot)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }

    private func pill(_ shot: CaptureShot) -> some View {
        let size = CGSize(width: 72, height: 48)
        return ZStack(alignment: .topTrailing) {
            Button { draft.editing = shot.id } label: {
                ZStack(alignment: .topLeading) {
                    if let image = shot.image { Image(nsImage: image).resizable().scaledToFill() } else { Color.secondary.opacity(0.2) }
                    ShotMarksLayer(marks: shot.marks, size: size, scale: 0.4)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(6)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .onHover { showHint($0, shot.marks.isEmpty ? "Mark up" : "Edit the marks", nil) }
            RemoveBadge { draft.remove(shot.id) }
                .offset(x: 6, y: -6)
        }
    }

    /// The editor, opened from a pill: the tools, the image and Done.
    private func editor(_ shot: CaptureShot, _ image: NSImage) -> some View {
        // The canvas takes the image's own shape, at most 320 high, so a wide screenshot is not letterboxed.
        let inner = Self.width - 32
        let height = image.size.width > 0 ? min(320, inner * image.size.height / image.size.width) : 320
        return MarkupEditor(image: image, marks: marksBinding(shot.id), canvasHeight: height) {
            HStack(spacing: 8) {
                QuietIconButton(symbol: "trash", size: 14) { draft.remove(shot.id) }
                    .help("Remove the screenshot")
                DoneButton { draft.editing = nil; focused = true }
            }
        }
        .padding(16)
        .frame(width: Self.width)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func marksBinding(_ id: CaptureShot.ID) -> Binding<[ShotMark]> {
        Binding(get: { draft.shots.first { $0.id == id }?.marks ?? [] },
                set: { new in if let i = draft.shots.firstIndex(where: { $0.id == id }) { draft.shots[i].marks = new } })
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

    private func captureArea() {
        problem = AreaCapture.permissionProblem()
        if problem != nil { return }
        let draft = self.draft
        Task {
            if let data = await QuickCapture.shared.captureArea() {
                // Attached at once, nothing to confirm; click the pill to mark it up.
                draft.add(name: "area-\(draft.shots.count + 1).png", data: data)
            }
            focused = true
        }
    }

    /// Sends it to Iris, then starts fresh and closes: the next capture begins empty.
    private func send() {
        guard canSend, let pid = draft.projectId else { return }
        let text = draft.prompt
        let pending = draft.shots.map(\.pending)
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

// MARK: Controls drawn for the bar
//
// Drawn by hand rather than with the system glass button styles: those resolve their own glass inside the bar's glass,
// and a filled shape looks the same whether Hatch is the active app or not.

/// A secondary icon in the bar: grey, a soft circle on hover.
struct QuietIconButton: View {
    let symbol: String
    var size: CGFloat = 17
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }
}

/// The round send button: the accent colour when there is something to send.
struct SendButton: View {
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? Color.white : Color.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(enabled ? Color.accentColor.opacity(hovering ? 0.85 : 1) : Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: enabled)
    }
}

/// Done in the editor: a filled capsule in the accent colour.
struct DoneButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label("Done", systemImage: "checkmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(Color.accentColor.opacity(hovering ? 0.85 : 1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .keyboardShortcut(.defaultAction)
        .onHover { hovering = $0 }
    }
}

/// The small round remove badge on a screenshot pill.
struct RemoveBadge: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.black.opacity(hovering ? 0.75 : 0.55)))
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help("Remove")
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
