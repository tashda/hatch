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
        // SwiftUI's opacity reaches the probe's own view: a view faded out (a card waiting to slide in) isn't drawn.
        // And through the layers SwiftUI makes itself (a row faded in with a scale effect), which aren't views.
        func opacity(_ v: NSView) -> CGFloat {
            var a: CGFloat = 1, x: NSView? = v
            while let c = x, c !== root.superview { a *= c.alphaValue; x = c.superview }
            var l = v.layer
            while let layer = l { a *= layer.isHidden ? 0 : CGFloat(layer.opacity); l = layer.superlayer }
            return a
        }
        // What is left of it inside every view that clips (a scroll view, a clipped frame): SwiftUI clips by layer,
        // so `visibleRect` doesn't know (measured: it is larger than the view, and set for a row scrolled away).
        func shown(_ v: NSView) -> NSRect {
            var r = v.convert(v.bounds, to: root), x = v.superview
            while let c = x, c !== root.superview {
                var clips = c.layer?.masksToBounds ?? false
                if #available(macOS 14.0, *) { clips = clips || c.clipsToBounds }
                if clips { r = r.intersection(c.convert(c.bounds, to: root)) }
                x = c.superview
            }
            return r.intersection(root.bounds)
        }
        func walk(_ view: NSView, parent: Int?) {
            var inside = parent
            if let mark = view as? HatchMarkView, !mark.isHiddenOrHasHiddenAncestor, opacity(mark) > 0.05,
               case let seen = shown(mark), seen.width >= 1, seen.height >= 1 {
                var entry: [String: Any] = ["name": mark.name, "instance": mark.instance, "frame": rect(mark.convert(mark.bounds, to: root)),
                                            "visible": rect(seen)]
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
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { super.init(coder: coder); wantsLayer = true }
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
