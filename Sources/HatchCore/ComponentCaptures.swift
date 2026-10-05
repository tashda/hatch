import Foundation

// Pictures of the app's own views, drawn by the app itself (CM20, CM21). The app follows one contract, the same for
// any SwiftUI app: each of its own views ends its body with `.hatchMark("TypeName")` (from `HatchMarks.swift`, which
// Hatch writes), and its snapshot run saves every screen as `<screen>-light.png` / `-dark.png` with a `.json` beside it
// listing each marked view's frame. Hatch keeps them in the notebook, cuts each view out of the screen it is used on,
// outlines where it sits, and measures the screens (`ComponentTruth`). Nothing is drawn from memory.

/// One rectangle in points from the top left of a picture.
public struct CaptureRect: Codable, Equatable, Hashable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    init?(_ a: [Double]?) {
        guard let a, a.count == 4 else { return nil }
        self.init(x: a[0], y: a[1], width: a[2], height: a[3])
    }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var area: Double { max(0, width) * max(0, height) }
    public func intersection(_ o: CaptureRect) -> CaptureRect? {
        let x0 = max(x, o.x), y0 = max(y, o.y), x1 = min(maxX, o.maxX), y1 = min(maxY, o.maxY)
        return x1 > x0 && y1 > y0 ? CaptureRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) : nil
    }
    public func contains(_ o: CaptureRect, slack: Double = 0.5) -> Bool {
        o.x >= x - slack && o.y >= y - slack && o.maxX <= maxX + slack && o.maxY <= maxY + slack
    }
    public func scaled(_ s: Double) -> CaptureRect { CaptureRect(x: x * s, y: y * s, width: width * s, height: height * s) }
}

/// What the app's snapshot run writes beside each picture (`<screen>-<mode>.json`, version 2).
public struct CaptureFile: Codable, Equatable, Sendable {
    public struct Mark: Codable, Equatable, Sendable {
        /// The view's type name, as in `.hatchMark("HXChip")`.
        public var name: String
        public var frame: [Double]
        /// The part not scrolled or clipped away; a mark with nothing visible is not written.
        public var visible: [Double]?
        /// The index of the nearest marked view it sits in, if any.
        public var parent: Int?
        /// One use of the view; parts with the same instance are one view drawn as siblings.
        public var instance: Int?
        /// The scroll view it sits in, if any: views in different ones (content and a bar over it) may lie on each other.
        public var scroll: Int?
        /// Drawn over other views on purpose (a pin, an overlay): left out of the overlap check.
        public var layered: Bool?
        public init(name: String, frame: [Double], visible: [Double]? = nil, parent: Int? = nil, instance: Int? = nil, scroll: Int? = nil, layered: Bool? = nil) {
            self.name = name; self.frame = frame; self.visible = visible; self.parent = parent; self.instance = instance; self.scroll = scroll
            self.layered = layered
        }
    }
    public var version: Int
    /// Points to pixels.
    public var scale: Double
    /// The picture's size in points.
    public var size: [Double]
    public var marks: [Mark]
    public init(version: Int = 2, scale: Double, size: [Double], marks: [Mark]) {
        self.version = version; self.scale = scale; self.size = size; self.marks = marks
    }
}

public extension CaptureFile {
    /// One mark per use of a view: the parts of a view drawn as siblings (same instance) become one frame around them.
    func joined() -> CaptureFile {
        var out: [Mark] = [], newIndex: [Int: Int] = [:], byInstance: [Int: Int] = [:]
        for (i, m) in marks.enumerated() {
            if let inst = m.instance, let j = byInstance[inst] {
                out[j].frame = Self.union(out[j].frame, m.frame)
                if let v = m.visible { out[j].visible = out[j].visible.map { Self.union($0, v) } ?? v }
                newIndex[i] = j
                continue
            }
            var copy = m
            copy.parent = m.parent.flatMap { newIndex[$0] }
            newIndex[i] = out.count
            if let inst = m.instance { byInstance[inst] = out.count }
            out.append(copy)
        }
        var file = self; file.marks = out
        return file
    }

    private static func union(_ a: [Double], _ b: [Double]) -> [Double] {
        guard a.count == 4, b.count == 4 else { return a }
        let x = min(a[0], b[0]), y = min(a[1], b[1])
        return [x, y, max(a[0] + a[2], b[0] + b[2]) - x, max(a[1] + a[3], b[1] + b[3]) - y]
    }
}

/// One captured screen in one appearance.
public struct CapturedScreen: Equatable, Sendable {
    /// `desk`, `settings-agents`, `component-gallery`…
    public var name: String
    public var dark: Bool
    public var picture: URL
    public var file: CaptureFile

    public var isGallery: Bool { name == ComponentCaptures.galleryName }
    /// The screen's name for people: "settings-agents" → "Settings agents".
    public var title: String {
        if isGallery { return "The app's gallery" }
        let words = name.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
    public func frame(_ i: Int) -> CaptureRect? { CaptureRect(file.marks[i].frame) }
    public func visible(_ i: Int) -> CaptureRect? { CaptureRect(file.marks[i].visible) ?? frame(i) }
    public var bounds: CaptureRect { CaptureRect(x: 0, y: 0, width: file.size.first ?? 0, height: file.size.dropFirst().first ?? 0) }
}

public struct ComponentCaptures: Sendable {
    public static let notebookPath = "components/captures"
    /// Screens go in a folder of their own, kept on this Mac only (git ignores their pictures): they are large and the
    /// app redraws them on request. The frames are kept with the notebook.
    public static let screensFolder = "screens"
    public static let galleryName = "component-gallery"

    public var folder: URL
    public var screens: [CapturedScreen]

    public init(folder: URL, screens: [CapturedScreen]) { self.folder = folder; self.screens = screens }

    /// Every `<name>-light|dark.json` with its picture in the folder and in `screens/`; the gallery's first contract
    /// (`component-gallery.json` with `items`) is read as the gallery screen. Nil when there is nothing.
    public static func load(from folder: URL) -> ComponentCaptures? {
        var screens: [CapturedScreen] = []
        let fm = FileManager.default
        for dir in [folder, folder.appendingPathComponent(screensFolder, isDirectory: true)] {
            for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where name.hasSuffix(".json") {
                let base = String(name.dropLast(5))
                let dark: Bool
                if base.hasSuffix("-light") { dark = false } else if base.hasSuffix("-dark") { dark = true } else { continue }
                let picture = dir.appendingPathComponent(base + ".png")
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                      let file = try? JSONDecoder().decode(CaptureFile.self, from: data).joined() else { continue }
                screens.append(CapturedScreen(name: String(base.dropLast(dark ? 5 : 6)), dark: dark, picture: picture, file: file))
            }
        }
        if !screens.contains(where: \.isGallery), let legacy = legacyGallery(folder) { screens += legacy }
        return screens.isEmpty ? nil : ComponentCaptures(folder: folder, screens: screens)
    }

    /// `component-gallery.json` from before marks: items by name, the same frames in both appearances.
    static func legacyGallery(_ folder: URL) -> [CapturedScreen]? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("component-gallery.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [String: [[Double]]] else { return nil }
        let marks = items.sorted { $0.key < $1.key }.flatMap { name, frames in frames.map { CaptureFile.Mark(name: name, frame: $0) } }
        let maxX = marks.map { $0.frame[0] + $0.frame[2] }.max() ?? 0, maxY = marks.map { $0.frame[1] + $0.frame[3] }.max() ?? 0
        let file = CaptureFile(version: 1, scale: json["scale"] as? Double ?? 2, size: [maxX + 24, maxY + 24], marks: marks)
        return [false, true].map { dark in
            CapturedScreen(name: galleryName, dark: dark, picture: folder.appendingPathComponent("component-gallery-\(dark ? "dark" : "light").png"), file: file)
        }
    }

    /// Where a view is drawn: a screen and its frame there.
    public struct Place: Equatable, Sendable {
        public var screen: CapturedScreen
        public var index: Int
        public var frame: CaptureRect
        /// Nothing of it is scrolled or clipped away.
        public var whole: Bool
        /// The frame in pixels of the screen's picture.
        public var pixels: CaptureRect { frame.scaled(screen.file.scale) }
    }

    /// Every place a view is drawn in one appearance: the screens first, the gallery last.
    public func places(of id: String, dark: Bool) -> [Place] {
        screens.filter { $0.dark == dark }.sorted { ($0.isGallery ? 1 : 0, $0.name) < ($1.isGallery ? 1 : 0, $1.name) }.flatMap { s in
            s.file.marks.indices.compactMap { i -> Place? in
                guard s.file.marks[i].name == id, let f = s.frame(i) else { return nil }
                let v = s.visible(i) ?? f
                return Place(screen: s, index: i, frame: f, whole: abs(v.width - f.width) < 1 && abs(v.height - f.height) < 1)
            }
        }
    }

    /// The picture to show for a view: the gallery's when it has one (drawn on purpose, with sample data), otherwise a
    /// whole instance on a screen at the size it usually has.
    public func best(of id: String, dark: Bool) -> Place? {
        let all = places(of: id, dark: dark)
        if let g = all.first(where: { $0.screen.isGallery }) { return g }
        let whole = all.filter(\.whole)
        guard !whole.isEmpty else { return all.first }
        let heights = whole.map(\.frame.height).sorted(), median = heights[heights.count / 2]
        return whole.min { abs($0.frame.height - median) < abs($1.frame.height - median) }
    }

    /// The views the app has drawn somewhere.
    public var drawn: Set<String> { Set(screens.flatMap { $0.file.marks.map(\.name) }) }

    /// The screens a view is on, by name, with how many times (the gallery left out).
    public func screens(of id: String) -> [(name: String, count: Int)] {
        let counts = Dictionary(grouping: places(of: id, dark: false).filter { !$0.screen.isGallery }, by: \.screen.name).mapValues(\.count)
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map { ($0.key, $0.value) }
    }

    /// Each view's height in points as the app drew it (the gallery's, else the usual one on screens).
    public var heights: [String: Double] {
        var out: [String: Double] = [:]
        for id in drawn { if let p = best(of: id, dark: false) { out[id] = p.frame.height } }
        return out
    }
}

/// The contract file and the check that each view carries its mark.
public enum ComponentMarks {
    /// Where an app keeps the file Hatch gives it, when the owner has not said otherwise.
    public static let fileName = "HatchMarks.swift"

    /// The views among `ids` whose declaration does not end its body with `.hatchMark("<its name>")`. Reads the Swift
    /// files under `root` once each; free.
    public static func unmarked(_ views: [AppView], root: String) -> [String] {
        var texts: [String: String] = [:]
        return views.filter { v in
            let path = v.file.hasPrefix("/") ? v.file : (root as NSString).appendingPathComponent(v.file)
            if texts[path] == nil { texts[path] = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
            return !(texts[path] ?? "").contains(".hatchMark(\"\(v.id)\")")
        }.map(\.id)
    }

    /// `HatchMarks.swift`: the one file an app adds so Hatch can find its views on screen. It has no dependency and does
    /// nothing unless the app runs with `--snapshots` (or `HATCH_MARKS=1`).
    public static let appFile = #"""
    // HatchMarks.swift: written by Hatch (`hatch components marks-file`). Keep it as it is; Hatch replaces it when the
    // contract changes.
    //
    // Each of the app's own views ends its body with `.hatchMark("TypeName")`. In a normal run that does nothing. When
    // the app runs its snapshots (`--snapshots <folder>`), every marked view on screen is found and its frame is written
    // beside the picture (`HatchMarks.capture`), so Hatch shows each view as the app draws it, outlines where it is used
    // and measures the screens: overlap, cut off, sizes that drift. Nothing is drawn from memory.

    import SwiftUI
    import AppKit
    import ObjectiveC

    public enum HatchMarks {
        /// On only for a snapshot run, so the app's normal run pays nothing.
        public static let isOn: Bool = ProcessInfo.processInfo.arguments.contains("--snapshots")
            || ProcessInfo.processInfo.environment["HATCH_MARKS"] == "1"

        /// A window level below the desktop picture: a window there is drawn and can be captured, but never seen.
        public static let hiddenLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)

        /// Keeps a snapshot run out of the user's way. Call it first thing when the app starts with `--snapshots`: the app
        /// can't come forward or take the menu bar, and every window it shows stays hidden below the desktop picture,
        /// where it is still drawn and captured. Give the root views `.hatchMarksRoot()` so controls draw as in a front
        /// window.
        @MainActor public static func quiet() {
            guard isOn else { return }
            NSApplication.shared.setActivationPolicy(.prohibited)
            guard !quieted else { return }
            quieted = true
            for (original, replacement) in [(#selector(NSWindow.makeKeyAndOrderFront(_:)), #selector(NSWindow.hatchMarks_hide(_:))),
                                            (#selector(NSWindow.orderFront(_:)), #selector(NSWindow.hatchMarks_hide(_:))),
                                            (#selector(NSWindow.orderFrontRegardless), #selector(NSWindow.hatchMarks_hideRegardless))] {
                guard let a = class_getInstanceMethod(NSWindow.self, original), let b = class_getInstanceMethod(NSWindow.self, replacement) else { continue }
                method_setImplementation(a, method_getImplementation(b))
            }
        }
        @MainActor private static var quieted = false

        /// Saves `<name>.png` (the window with its title bar and toolbar) and `<name>.json` (every marked view in it) in
        /// `folder`. Name screens `<screen>-light` and `<screen>-dark`. With screen recording already allowed, the window
        /// server's own picture is used (it draws Liquid Glass); otherwise the window's views draw themselves. It never
        /// asks for the permission.
        @MainActor public static func capture(_ window: NSWindow, as name: String, into folder: URL) {
            guard let root = window.contentView?.superview ?? window.contentView else { return }
            let url = folder.appendingPathComponent(name + ".png")
            var done = false
            if CGPreflightScreenCaptureAccess() {
                window.displayIfNeeded()
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
                try? p.run()
                p.waitUntilExit()
                done = p.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
            }
            if !done, let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            writeMarks(of: root, scale: window.backingScaleFactor, to: folder.appendingPathComponent(name + ".json"))
        }

        /// Only the `.json`, for an app that saves its own pictures of `root`.
        @MainActor public static func writeMarks(of root: NSView, scale: CGFloat, to url: URL) {
            var marks: [[String: Any]] = []
            func rect(_ r: NSRect) -> [Double] {
                let y = root.isFlipped ? r.minY : root.bounds.height - r.maxY
                return [r.minX, y, r.width, r.height].map { (Double($0) * 100).rounded() / 100 }
            }
            func walk(_ view: NSView, parent: Int?) {
                var inside = parent
                if let mark = view as? HatchMarkView, !mark.isHiddenOrHasHiddenAncestor, !mark.visibleRect.isEmpty {
                    var entry: [String: Any] = ["name": mark.name, "instance": mark.instance, "frame": rect(mark.convert(mark.bounds, to: root)),
                                                "visible": rect(mark.convert(mark.visibleRect, to: root))]
                    if let parent { entry["parent"] = parent }
                    if let scroll = mark.enclosingScrollView { entry["scroll"] = ObjectIdentifier(scroll).hashValue & 0x7fff_ffff }
                    if mark.layered { entry["layered"] = true }
                    marks.append(entry)
                    inside = marks.count - 1
                }
                for sub in view.subviews { walk(sub, parent: inside) }
            }
            walk(root, parent: nil)
            let json: [String: Any] = ["version": 2, "scale": Double(scale),
                                       "size": [Double(root.bounds.width), Double(root.bounds.height)], "marks": marks]
            if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url)
            }
        }
    }

    public extension View {
        /// Marks one of the app's own views for Hatch: `.hatchMark("StatusChip")` at the end of its body. `layered`: it is
        /// drawn over other views on purpose (a pin, an overlay), so Hatch doesn't report it as overlapping them.
        func hatchMark(_ name: String, layered: Bool = false) -> some View { modifier(HatchMarkModifier(name: name, layered: layered)) }

        /// On each window's root view: in a snapshot run the hidden windows draw their controls as a front window does.
        func hatchMarksRoot() -> some View { modifier(HatchMarksRootModifier()) }
    }

    struct HatchMarksRootModifier: ViewModifier {
        func body(content: Content) -> some View {
            if HatchMarks.isOn, #available(macOS 15.0, *) { content.environment(\.appearsActive, true) } else { content }
        }
    }

    extension NSWindow {
        /// In a quiet snapshot run, showing a window puts it below the desktop picture instead (`HatchMarks.quiet`).
        @objc func hatchMarks_hide(_ sender: Any?) { level = HatchMarks.hiddenLevel; orderBack(sender) }
        @objc func hatchMarks_hideRegardless() { level = HatchMarks.hiddenLevel; orderBack(nil) }
    }

    struct HatchMarkModifier: ViewModifier {
        let name: String
        var layered = false
        /// One per use of the view: a view whose body is several siblings (a Group) marks each, and Hatch joins them.
        @State private var instance = Int.random(in: 1...Int(Int32.max))
        func body(content: Content) -> some View {
            if HatchMarks.isOn { content.background(HatchMarkProbe(name: name, instance: instance, layered: layered)) } else { content }
        }
    }

    /// An empty view the size of the marked view; it draws nothing and takes no clicks.
    final class HatchMarkView: NSView {
        var name = ""
        var instance = 0
        var layered = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var isFlipped: Bool { true }
    }

    struct HatchMarkProbe: NSViewRepresentable {
        let name: String
        let instance: Int
        let layered: Bool
        func makeNSView(context: Context) -> HatchMarkView { let v = HatchMarkView(); updateNSView(v, context: context); return v }
        func updateNSView(_ view: HatchMarkView, context: Context) { view.name = name; view.instance = instance; view.layered = layered }
    }

    """#
}

public extension ComponentCaptures {
    /// Replaces the notebook's captures with a capture run's (`folder`): the gallery beside the system, every other
    /// screen in `screens/` with its pictures kept on this Mac only. Returns what was kept.
    @discardableResult
    static func keep(from folder: URL, notebook: String) throws -> ComponentCaptures {
        let fm = FileManager.default
        guard let run = load(from: folder) else {
            throw OwnChangeError(description: "No captures in \(folder.path): the app's snapshot run writes <screen>-light.png and .json there.")
        }
        let target = URL(fileURLWithPath: notebook).appendingPathComponent(notebookPath, isDirectory: true)
        let screens = target.appendingPathComponent(screensFolder, isDirectory: true)
        try? fm.removeItem(at: screens)
        try fm.createDirectory(at: screens, withIntermediateDirectories: true)
        try "*.png\n".write(to: screens.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        // A new run replaces the old gallery too, including the first contract's files.
        for old in ((try? fm.contentsOfDirectory(atPath: target.path)) ?? []) where old.hasPrefix(galleryName) {
            try? fm.removeItem(at: target.appendingPathComponent(old))
        }
        for s in run.screens {
            let dir = s.isGallery ? target : screens
            let base = s.name + (s.dark ? "-dark" : "-light")
            let json = s.picture.deletingLastPathComponent().appendingPathComponent(base + ".json")
            if fm.fileExists(atPath: json.path) { try fm.copyItem(at: json, to: dir.appendingPathComponent(base + ".json")) }
            if fm.fileExists(atPath: s.picture.path) { try fm.copyItem(at: s.picture, to: dir.appendingPathComponent(base + ".png")) }
        }
        if run.screens.contains(where: { $0.isGallery && $0.file.version == 1 }) {
            try? fm.copyItem(at: folder.appendingPathComponent("component-gallery.json"), to: target.appendingPathComponent("component-gallery.json"))
        }
        return load(from: target) ?? run
    }

    /// The command that runs the app's snapshots for Hatch: the app repo's `captureCommand`, else a `hatch-capture.sh`
    /// at its root or in `tools/`. It gets the folder to write into as `$HATCH_CAPTURES`.
    static func command(appRoot: String, configured: String?) -> String? {
        if let configured, !configured.trimmingCharacters(in: .whitespaces).isEmpty { return configured }
        for path in ["hatch-capture.sh", "tools/hatch-capture.sh"] where FileManager.default.fileExists(atPath: (appRoot as NSString).appendingPathComponent(path)) {
            return "sh " + path
        }
        return nil
    }

    /// Runs the capture command in `appRoot` into a new folder and returns it, or the tail of its output on failure.
    static func run(command: String, appRoot: String, timeout: TimeInterval = 900) -> (folder: URL?, log: String) {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("hatch-captures-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        p.currentDirectoryURL = URL(fileURLWithPath: appRoot, isDirectory: true)
        var env = ProcessInfo.processInfo.environment
        env["HATCH_CAPTURES"] = out.path
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        var data = Data()
        let lock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; lock.lock(); data.append(d); lock.unlock() }
        do { try p.run() } catch { return (nil, "Could not start \(command): \(error.localizedDescription)") }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        if p.isRunning { p.terminate() }
        pipe.fileHandleForReading.readabilityHandler = nil
        lock.lock(); let text = String(decoding: data, as: UTF8.self); lock.unlock()
        let tail = text.split(separator: "\n").suffix(15).joined(separator: "\n")
        guard p.terminationReason == .exit, p.terminationStatus == 0, load(from: out) != nil else {
            return (nil, tail.isEmpty ? "\(command) wrote no captures." : tail)
        }
        return (out, tail)
    }
}

public extension ComponentMarks {
    /// What still keeps a view out of the pictures: no mark in its code, or marked but on no screen yet.
    struct Coverage: Equatable, Sendable {
        /// The app's own views (components, wrappers and the ones Hatch is unsure of).
        public var views: [String]
        public var drawn: [String]
        public var unmarked: [String]
        /// Marked, but no captured screen shows them: the gallery has to draw them with sample data.
        public var offScreen: [String]
        public var complete: Bool { drawn.count == views.count }
    }

    static func coverage(_ model: AppViewModel, root: String, captures: ComponentCaptures?) -> Coverage {
        let own = model.views.filter { [.component, .wrapper, .unknown].contains($0.kind) }
        let drawn = captures?.drawn ?? []
        let unmarked = Set(unmarked(own, root: root))
        let ids = own.map(\.id)
        return Coverage(views: ids, drawn: ids.filter(drawn.contains), unmarked: ids.filter(unmarked.contains),
                        offScreen: ids.filter { !drawn.contains($0) && !unmarked.contains($0) })
    }

    /// The ticket that makes the app draw every view of its own for Hatch (CM21): the marks file, a mark on each view,
    /// a snapshot run with the frames, a gallery for what no screen shows, and the command Hatch runs. An agent does it;
    /// `hatch components capture` then says what is still missing, so "done" is measured, not claimed.
    static func drawDraft(_ c: Coverage, hasMarksFile: Bool, hasCommand: Bool) -> ComponentsSetup.Draft {
        let missing = c.views.count - c.drawn.count
        var steps: [String] = []
        if !hasMarksFile {
            steps.append("Add `\(fileName)` to the app target: `hatch components marks-file --write <path>`. Keep it as Hatch writes it.")
        }
        if !c.unmarked.isEmpty {
            steps.append("End the body of each of these views with `.hatchMark(\"<its type name>\")` (a body of several siblings: wrap them in a `Group` first). "
                         + "Nothing else in them changes:\n" + c.unmarked.map { "   - \($0)" }.joined(separator: "\n"))
        }
        if !hasCommand {
            steps.append("Give the app a snapshot run if it has none: launched with `--snapshots <folder>`, it opens each main screen, sheet and step on made-up "
                         + "data (never the user's), and saves each with `HatchMarks.capture(window, as: \"<screen>-light\", into: folder)`, then dark, then quits. "
                         + "Add `hatch-capture.sh` at the app's root: it builds the app and runs it with `--snapshots \"$HATCH_CAPTURES\"`.")
        }
        if !c.offScreen.isEmpty {
            steps.append("These views are on no screen the snapshot run draws. Draw each in a gallery screen named `component-gallery` (a window of samples with "
                         + "realistic data, each sample also marked with the view's name), or add the screen they are on to the run:\n"
                         + c.offScreen.map { "   - \($0)" }.joined(separator: "\n"))
        }
        steps.append("Run `hatch components capture`. It runs the command, keeps the pictures, and lists any view still not drawn; repeat until it says "
                     + "every view of its own is drawn.")
        let body = """
        Hatch shows each of the app's own views as the app draws it, outlines where it is used, and measures the screens (overlap, cut-off \
        text, sizes that drift). \(missing) of \(c.views.count) views are not drawn yet, so the Components Designer can't show them.

        \(steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

        Done when: `hatch components capture` reports every view drawn. Do not change how any view looks.
        """
        var draft = ComponentsSetup.Draft(type: .tweak, title: "Draw the app's own views for Hatch (\(missing) not drawn)", body: body)
        draft.area = ComponentsSetup.area
        return draft
    }
}

public extension ComponentMarks {
    /// True when some Swift file of the app declares `HatchMarks` (the contract file is in).
    static func hasFile(appRoot: String, excluding: [String] = []) -> Bool {
        ComponentInventoryScanner.appFiles(appRoot: appRoot, excluding: excluding).contains { $0.text.contains("enum HatchMarks") }
    }
}
