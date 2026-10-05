import SwiftUI
import AppKit
import StageCore

/// What the Stage was launched with.
///
///     HatchStageToast --demo                       runs on its own with the in-memory data source
///     HatchStageToast --ticket 151                 talks to Hatch's local API (HatchAPIStageDataSource)
///     HatchStageToast --manifest /path/m.json      uses that manifest instead of the one compiled into the round
///     HatchStageToast --home /path/to/Hatch        Hatch's support directory (token and port), as the launching app passes it
///     HatchStageToast --render-icon out.png [--hatch | --designer] [--dark] [--full] [--ticket 151]
///                                                  writes the Stage's icon (with the number when given), Hatch's or the
///                                                  Components Designer's at 1024 px and exits; `--full` is full-bleed
///                                                  artwork for an Icon Composer file, `--dark` the dark colouring
///     HatchStageToast --check                      headless: draws every specimen in every scenario, prints JSON, exits 0 or 1
public struct StageLaunchOptions: Equatable {
    public var demo: Bool = false
    public var ticket: String? = nil
    public var manifestPath: String? = nil
    public var home: String? = nil
    public var check: Bool = false
    public var snapshotDirectory: URL? = nil
    public var renderIconPath: String? = nil
    /// With `--render-icon`: which app's icon (`--hatch`, `--designer`; the Stage's by default).
    public var renderIconKind = "stage"
    /// With `--render-icon`: the dark colouring.
    public var renderDarkIcon = false
    /// With `--render-icon`: full-bleed artwork for an Icon Composer layer instead of the tile.
    public var renderFullIcon = false

    public init() {}

    public static func parse(_ arguments: [String]) -> StageLaunchOptions {
        var o = StageLaunchOptions()
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "--demo" {
                o.demo = true
            } else if a == "--ticket", i + 1 < arguments.count {
                o.ticket = arguments[i + 1]
                i += 1
            } else if a == "--manifest", i + 1 < arguments.count {
                o.manifestPath = arguments[i + 1]
                i += 1
            } else if a == "--home", i + 1 < arguments.count {
                o.home = arguments[i + 1]
                i += 1
            } else if a == "--render-icon", i + 1 < arguments.count {
                o.renderIconPath = arguments[i + 1]
                i += 1
            } else if a == "--designer" || a == "--hatch" {
                o.renderIconKind = String(a.dropFirst(2))
            } else if a == "--dark" {
                o.renderDarkIcon = true
            } else if a == "--full" {
                o.renderFullIcon = true
            } else if a == "--check" {
                o.check = true
            } else if a == "--snapshots", i + 1 < arguments.count {
                o.snapshotDirectory = URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
                i += 1
            }
            i += 1
        }
        return o
    }
}

/// The entry point a round's executable calls from `main.swift`:
///
///     StageApp.run(provider: MyProvider(), manifest: MyManifest.load())
@MainActor
public enum StageApp {
    private static var delegate: StageAppDelegate? = nil

    /// Opens the Stage window and runs until it is closed.
    /// - Parameters:
    ///   - provider: the round's specimens.
    ///   - manifest: the Proposal as compiled into the round; `--manifest <path>` overrides it.
    ///   - dataSource: where picks go. When `nil`: `--demo` or no `--ticket` uses the in-memory source, `--ticket` uses Hatch.
    public static func run(provider: any SpecimenProvider, manifest: StageManifest,
                           dataSource: StageDataSource? = nil, arguments: [String] = CommandLine.arguments) {
        // The Components Designer is a mode of the Stage (decision DS1): it needs no round.
        let designer = DesignerLaunchOptions.parse(Array(arguments.dropFirst()))
        if designer.isDesigner { DesignerApp.run(designer) }
        let options = StageLaunchOptions.parse(Array(arguments.dropFirst()))
        if let path = options.renderIconPath {
            let ok = StageIcon.writePNG(to: URL(fileURLWithPath: path), kind: AppIconKind(rawValue: options.renderIconKind) ?? .stage,
                                        number: StageIcon.digits(from: options.ticket), dark: options.renderDarkIcon, full: options.renderFullIcon)
            exit(ok ? 0 : 1)
        }
        // The arguments choose the mode, not the bundle (decision AI3). Components Designer.app opened from Finder has no
        // project, so it says where to open it from instead of showing a Stage.
        if Bundle.main.bundleIdentifier == DesignerApp.bundleIdentifier { DesignerApp.explainAndQuit() }
        var effective = manifest
        if let path = options.manifestPath {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                effective = try StageManifest.parse(data: data)
            } catch {
                FileHandle.standardError.write(Data("Could not read the manifest at \(path): \(error)\n".utf8))
            }
        }
        if options.check {
            // Decision S6: Hatch runs the built Stage headless before the ticket becomes Your call.
            exit(StageSelfCheck.run(provider: provider, manifest: effective))
        }
        let source: StageDataSource
        if let given = dataSource {
            source = given
        } else if options.snapshotDirectory == nil, !options.demo, let ticket = options.ticket {
            if let home = options.home, !home.isEmpty {
                source = HatchAPIStageDataSource(ticket: ticket, home: URL(fileURLWithPath: home, isDirectory: true))
            } else {
                source = HatchAPIStageDataSource(ticket: ticket)
            }
        } else {
            source = InMemoryStageDataSource(manifest: effective)
        }
        let model = StageModel(manifest: effective, provider: provider, dataSource: source)
        model.captureView = { StageSnapshot.jpegOfFrontStageWindow() }
        let d = StageAppDelegate(model: model, title: windowTitle(effective, options), snapshotDirectory: options.snapshotDirectory,
                                ticketNumber: StageIcon.digits(from: options.ticket))
        delegate = d
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = d
        app.run()
    }

    private static func windowTitle(_ manifest: StageManifest, _ options: StageLaunchOptions) -> String {
        let name = manifest.title.isEmpty ? "Proposal" : manifest.title
        return "Stage · \(name) · rev \(manifest.revision)"
    }
}

/// Set by the task that tells Hatch the Stage closed; the delegate waits for it for a moment.
private final class DoneFlag: @unchecked Sendable {
    var value = false
}

@MainActor
final class StageAppDelegate: NSObject, NSApplicationDelegate {
    private let model: StageModel
    private let title: String
    private let snapshotDirectory: URL?
    private let ticketNumber: String?
    private var window: NSWindow? = nil

    init(model: StageModel, title: String, snapshotDirectory: URL? = nil, ticketNumber: String? = nil) {
        self.model = model
        self.title = title
        self.snapshotDirectory = snapshotDirectory
        self.ticketNumber = ticketNumber
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        // The Dock icon carries this Proposal's ticket number, so two open Stages can be told apart. Drawn locally, lasts until quit.
        if ticketNumber != nil, let icon = StageIcon.image(number: ticketNumber) { NSApp.applicationIconImage = icon }
        let hosting = NSHostingView(rootView: StageView(model: model))
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.isReleasedWhenClosed = false
        w.title = title
        w.contentView = hosting
        w.contentMinSize = NSSize(width: 760, height: 540)
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
        NSApp.activate(ignoringOtherApps: true)
        if snapshotDirectory != nil {
            Task { @MainActor in await captureSnapshots() }
        }
    }

    private func captureSnapshots() async {
        guard let snapshotDirectory else { return }
        try? FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        // StageView restores asynchronously on appear. Let it settle before taking the fixture captures.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        model.send(.useAllRecommendations)
        model.send(.addPin(text: "Keep the action aligned with the message.", option: "b", x: 0.72, y: 0.31))
        model.send(.pinMix)
        try? await Task.sleep(nanoseconds: 500_000_000)

        for appearance in StageAppearance.allCases {
            model.send(.dismissSheet)
            model.send(.setMode(.side))
            model.send(.setAppearance(appearance))
            model.send(.setScenario("rest"))
            model.send(.showAllOptions)
            model.send(.toggleRedlines)
            model.send(.toggleRedlines)
            try? await capture("stage-main-\(appearance.rawValue)", into: snapshotDirectory)

            for mode in [StageMode.overlay, .flip, .wipe, .matrix] {
                model.send(.setMode(mode))
                try? await capture("stage-\(mode.rawValue)-\(appearance.rawValue)", into: snapshotDirectory)
            }

            model.send(.setMode(.side))
            for scenario in ["error", "long-text", "many-items"] {
                model.send(.setScenario(scenario))
                try? await capture("stage-\(scenario)-\(appearance.rawValue)", into: snapshotDirectory)
            }

            model.send(.toggleRedlines)
            try? await capture("stage-redlines-\(appearance.rawValue)", into: snapshotDirectory)
            model.send(.toggleRedlines)

            for (name, action) in [
                ("accept", StageAction.requestAccept),
                ("send-back", StageAction.requestSendBack),
                ("ask", StageAction.requestAsk),
                ("help", StageAction.toggleHelp),
            ] {
                model.send(.setScenario("rest"))
                model.send(action)
                if name == "send-back" { model.send(.setSendBackNote("Keep the action visible at large text sizes.")) }
                if name == "ask" { model.send(.setAskDraft("Does the larger padding keep the action easy to find?")) }
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let sheet = window?.attachedSheet, let view = sheet.contentView {
                    save(view, name: "stage-\(name)-sheet-\(appearance.rawValue)", into: snapshotDirectory)
                }
                model.send(.dismissSheet)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        await model.announceClosed()
        NSApp.terminate(nil)
    }

    private func capture(_ name: String, into directory: URL) async throws {
        try await Task.sleep(nanoseconds: 350_000_000)
        guard let view = window?.contentView else { return }
        save(view, name: name, into: directory)
    }

    private func save(_ view: NSView, name: String, into directory: URL) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Tells Hatch this Stage was closed on purpose, so it can tell that from a crash (decision S7). Gives the call half a second.
    func applicationWillTerminate(_ notification: Notification) {
        let flag = DoneFlag()
        let model = self.model
        Task { @MainActor in
            await model.announceClosed()
            flag.value = true
        }
        let deadline = Date().addingTimeInterval(0.5)
        while !flag.value && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// A programmatic app has no menu bar unless it makes one. Quit and the Edit items (so Paste works in notes) are enough.
    private func installMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Stage", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
