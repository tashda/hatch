import SwiftUI
import AppKit
import HatchCore
import HatchComponentKit

/// How the Components Designer was asked to open (decision DS1: a mode of the Stage app).
///
///     Stage --components <project> [--home <Hatch support dir>] [--app <app folder>]   through Hatch's local API
///     Stage --notebook <folder> [--app <app folder>]                                   read from a notebook; changes stay in the window
///     Stage --components-demo [glass|native] [--app <app folder>]                      a template, changes in the window
///     … --snapshots <dir>                                                              draws every element and view, saves PNGs, exits
public struct DesignerLaunchOptions: Equatable {
    public var project: String?
    public var notebook: String?
    public var demoTemplate: String?
    public var appFolder: String?
    public var home: String?
    public var snapshotDirectory: URL?
    /// With --snapshots: only the live window.
    public var liveOnly = false

    public var isDesigner: Bool { project != nil || notebook != nil || demoTemplate != nil }

    public static func parse(_ arguments: [String]) -> DesignerLaunchOptions {
        var o = DesignerLaunchOptions()
        var i = 0
        func value() -> String? { i + 1 < arguments.count && !arguments[i + 1].hasPrefix("--") ? arguments[i + 1] : nil }
        while i < arguments.count {
            switch arguments[i] {
            case "--components": o.project = value(); if o.project != nil { i += 1 }
            case "--notebook": o.notebook = value(); if o.notebook != nil { i += 1 }
            case "--components-demo": o.demoTemplate = value() ?? "glass"; if value() != nil { i += 1 }
            case "--app": o.appFolder = value(); if o.appFolder != nil { i += 1 }
            case "--home": o.home = value(); if o.home != nil { i += 1 }
            case "--snapshots": if let v = value() { o.snapshotDirectory = URL(fileURLWithPath: v, isDirectory: true); i += 1 }
            case "--live-only": o.liveOnly = true
            default: break
            }
            i += 1
        }
        return o
    }
}

@MainActor
enum DesignerApp {
    private static var delegate: DesignerDelegate?

    /// The bundle `tools/build-stage.sh` builds next to Stage.app: the same program with its own name and icon (decision AI3).
    static let bundleIdentifier = "app.hatch.ComponentsDesigner"

    /// Components Designer.app started without a project (opened from Finder): one short message, then quit.
    static func explainAndQuit() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.applicationIconImage = StageIcon.image(.designer)
        app.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Open the Components Designer from Hatch"
        alert.informativeText = "It works on one project's design system. In Hatch, open the project's Components page and open the Designer from there."
        alert.addButton(withTitle: "OK")
        alert.runModal()
        exit(0)
    }

    static func run(_ options: DesignerLaunchOptions) -> Never {
        let source: ComponentsSource
        do {
            if let project = options.project {
                source = HatchComponentsSource(project: project, home: options.home.map { URL(fileURLWithPath: $0, isDirectory: true) })
            } else if let folder = options.notebook {
                guard let system = try ComponentSystem.load(notebook: folder) else { throw StoreError.notFound("No design system in \(folder).") }
                source = LocalComponentsSource(system: system)
            } else {
                let template = ComponentTemplates.named(options.demoTemplate ?? "glass") ?? ComponentTemplates.glass
                source = LocalComponentsSource(system: template.system(name: "Demo"))
            }
            let inventory = options.appFolder.map { ComponentInventoryScanner.scan(appRoot: $0) }
            let model = try DesignerModel(source: source, inventory: inventory, appRoot: options.appFolder)
            let d = DesignerDelegate(model: model, snapshotDirectory: options.snapshotDirectory)
            d.liveOnly = options.liveOnly
            delegate = d
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            // Its own icon even when started from a plain Stage (a Stage path set in Settings › Tools).
            app.applicationIconImage = StageIcon.image(.designer)
            app.delegate = d
            app.run()
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Components Designer: \(error)\n".utf8))
            exit(1)
        }
    }
}

@MainActor
final class DesignerDelegate: NSObject, NSApplicationDelegate {
    let model: DesignerModel
    let snapshotDirectory: URL?
    var window: NSWindow?
    var liveWindow: NSWindow?
    var liveOnly = false

    /// The live window (NF2): the app's shell with the roles in it.
    func openLiveWindow() {
        if let liveWindow { liveWindow.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = "\(model.appName) — Live"
        w.contentView = NSHostingView(rootView: LiveWindowView(model: model, live: model.live))
        w.center()
        w.makeKeyAndOrderFront(nil)
        liveWindow = w
    }

    init(model: DesignerModel, snapshotDirectory: URL?) {
        self.model = model
        self.snapshotDirectory = snapshotDirectory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Components Designer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = menu

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 860),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = "Components · \(model.appName)"
        w.contentView = NSHostingView(rootView: DesignerView(model: model))
        w.contentMinSize = NSSize(width: 980, height: 600)
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
        model.openLiveWindow = { [weak self] in self?.openLiveWindow() }
        installMouseBack()
        NSApp.activate(ignoringOtherApps: true)
        if snapshotDirectory != nil { Task { @MainActor in await snapshots() } }
    }

    /// The mouse's back button (3) does what the role's Back link does: from a role to its element. There is no forward.
    private func installMouseBack() {
        NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard event.buttonNumber == 3 else { return event }
            let window = event.window
            let handled = MainActor.assumeIsolated {
                guard let self, window === self.window, self.model.focused else { return false }
                self.model.back()
                return true
            }
            return handled ? nil : event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Every element in every view, light and dark, as PNGs (window captures, so glass is drawn).
    private func snapshots() async {
        guard let dir = snapshotDirectory, let window else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? await Task.sleep(nanoseconds: 800_000_000)
        for dark in [false, true] where !liveOnly {
            model.dark = dark
            for element in model.system.elementsUsed {
                model.selection = .element(element)
                model.selectedRole = model.system.roles(of: element).first?.id
                for mode in DesignerMode.allCases {
                    model.mode = mode
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    save(window, "\(element)-\(mode.rawValue)-\(dark ? "dark" : "light")", dir)
                }
                // The role level (CD8): the first role with a question, then its recommendation as a preview (CD13).
                model.mode = .inPlace
                if let q = model.questions(for: element).first, let id = q.role, let role = model.system.role(id) {
                    model.open(id)
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    save(window, "\(element)-role-\(dark ? "dark" : "light")", dir)
                    model.tryLook(RoleInspectorPreview.make(role, q, q.recommended))
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    save(window, "\(element)-preview-\(dark ? "dark" : "light")", dir)
                    model.back()
                }
            }
            // A batch change previewed (CD24): macOS Native for every button.
            model.selection = .element("button")
            model.mode = .inPlace
            model.tryBatch(model.batchTemplate(ComponentTemplates.native, element: "button", place: nil))
            try? await Task.sleep(nanoseconds: 500_000_000)
            save(window, "button-batch-\(dark ? "dark" : "light")", dir)
            model.discard()
            // The whole app and one place (CD9, CD33).
            model.selection = .all
            try? await Task.sleep(nanoseconds: 450_000_000)
            save(window, "all-\(dark ? "dark" : "light")", dir)
            for mode in DesignerMode.allCases {
                model.selection = .place("inspector")
                model.mode = mode
                try? await Task.sleep(nanoseconds: 450_000_000)
                save(window, "place-inspector-\(mode.rawValue)-\(dark ? "dark" : "light")", dir)
            }
            model.mode = .inPlace
            if !model.system.questions.isEmpty {
                model.selection = .decide
                try? await Task.sleep(nanoseconds: 500_000_000)
                save(window, "decide-\(dark ? "dark" : "light")", dir)
            }
            model.selection = .templates
            try? await Task.sleep(nanoseconds: 500_000_000)
            save(window, "templates-\(dark ? "dark" : "light")", dir)
            model.selection = .rules
            try? await Task.sleep(nanoseconds: 450_000_000)
            save(window, "rules-\(dark ? "dark" : "light")", dir)
            for kind in ComponentFoundation.Kind.allCases where model.system.foundations.contains(where: { $0.kind == kind }) {
                model.selection = .foundations(kind)
                try? await Task.sleep(nanoseconds: 350_000_000)
                save(window, "foundations-\(kind.rawValue)-\(dark ? "dark" : "light")", dir)
            }
        }
        // Light and dark side by side (Both), on an element's page and on a role being compared.
        if !liveOnly {
            model.appearance = .both
            model.selection = .element("button")
            model.mode = .inPlace
            try? await Task.sleep(nanoseconds: 600_000_000)
            save(window, "button-both", dir)
            model.appearance = .light
            // The hard cases: long labels and larger text must wrap, never cut or overlap.
            model.sample.longLabel = true
            try? await Task.sleep(nanoseconds: 600_000_000)
            save(window, "button-long", dir)
            model.sample.longLabel = false
            model.largeText = true
            try? await Task.sleep(nanoseconds: 600_000_000)
            save(window, "button-large", dir)
            model.largeText = false
        }
        // The live window: the shell, then its sheet, alert and empty state.
        model.dark = false
        openLiveWindow()
        if let live = liveWindow {
            live.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 900_000_000)
            save(live, "live-light", dir)
            model.live.sheet = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            save(live, "live-sheet", dir)
            model.live.sheet = false
            try? await Task.sleep(nanoseconds: 500_000_000)
            model.live.alert = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            save(live, "live-alert", dir)
            model.live.alert = false
            try? await Task.sleep(nanoseconds: 500_000_000)
            model.live.empty = true
            try? await Task.sleep(nanoseconds: 500_000_000)
            save(live, "live-empty", dir)
            model.live.empty = false
            model.dark = true
            try? await Task.sleep(nanoseconds: 600_000_000)
            save(live, "live-dark", dir)
        }
        NSApp.terminate(nil)
    }

    private func save(_ window: NSWindow, _ name: String, _ dir: URL) {
        // Capture it as the active window, as the owner sees it (inactive windows draw prominent buttons grey).
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let url = dir.appendingPathComponent(name + ".png")
        // A real window capture draws Liquid Glass; fall back to the view's own bitmap when capture is not allowed.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try? p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) { return }
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
