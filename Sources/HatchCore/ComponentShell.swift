import Foundation

// The app's window shell (decision NF2): how its windows are built, so the Components Designer's live window opens the
// same shell with the roles in it, and sidebars, toolbars, glass and sheets are SwiftUI's own. There are only a few
// ways to build a SwiftUI Mac app; this reads which one, from the Swift text, for free.

public struct ComponentShell: Codable, Equatable, Sendable {
    public enum Navigation: String, Codable, Sendable {
        /// `NavigationSplitView` with a sidebar and a detail.
        case splitView
        /// `NavigationSplitView` with a sidebar, a content column and a detail.
        case splitView3
        case stack
        case tabs
        /// One plain view in the window.
        case plain
    }

    public var navigation: Navigation
    /// Scenes the app declares: window, document, settings, menuBarMenu, menuBarWindow, utilityWindow.
    public var scenes: [String]
    public var inspector: Bool
    public var toolbar: Bool
    public var search: Bool

    public init(navigation: Navigation = .splitView, scenes: [String] = ["window"], inspector: Bool = false, toolbar: Bool = true, search: Bool = false) {
        self.navigation = navigation; self.scenes = scenes; self.inspector = inspector; self.toolbar = toolbar; self.search = search
    }

    /// "Sidebar and detail with an inspector, toolbar and search; also a Settings window and a menu bar extra."
    public var summary: String {
        var s: String
        switch navigation {
        case .splitView: s = "Sidebar and detail"
        case .splitView3: s = "Sidebar, content and detail"
        case .stack: s = "A navigation stack"
        case .tabs: s = "Tabs"
        case .plain: s = "One view"
        }
        var parts: [String] = []
        if inspector { parts.append("an inspector") }
        if toolbar { parts.append("a toolbar") }
        if search { parts.append("search") }
        if !parts.isEmpty { s += " with " + parts.joined(separator: ", ") }
        let extra = scenes.filter { $0 != "window" }.map { ["settings": "a Settings window", "document": "documents", "menuBarMenu": "a menu bar menu",
                                                            "menuBarWindow": "a menu bar window", "utilityWindow": "a utility window"][$0] ?? $0 }
        if !extra.isEmpty { s += "; also " + extra.joined(separator: ", ") }
        return s + "."
    }

    /// Reads the shell from the app's Swift files.
    public static func detect(files: [(path: String, text: String)]) -> ComponentShell {
        var shell = ComponentShell(navigation: .plain, scenes: [], toolbar: false)
        var splitViews = 0, threeColumn = false, stacks = 0, tabs = 0
        for (_, text) in files {
            let s = SwiftStructure(text)
            let code = String(decoding: s.b, as: UTF8.self)
            if code.contains("WindowGroup") || code.contains("Window(") { if !shell.scenes.contains("window") { shell.scenes.append("window") } }
            for (word, scene) in [("DocumentGroup", "document"), ("Settings {", "settings"), ("UtilityWindow", "utilityWindow")] where code.contains(word) {
                if !shell.scenes.contains(scene) { shell.scenes.append(scene) }
            }
            if code.contains("MenuBarExtra") {
                let scene = code.contains("menuBarExtraStyle(.window)") ? "menuBarWindow" : "menuBarMenu"
                if !shell.scenes.contains(scene) { shell.scenes.append(scene) }
            }
            if code.contains(".inspector(") { shell.inspector = true }
            if code.contains(".toolbar") { shell.toolbar = true }
            if code.contains(".searchable(") { shell.search = true }
            let views = s.structs()
            for brace in s.braceOpens {
                guard let o = s.owner(ofBrace: brace), !o.dotted, o.label == nil else { continue }
                let after = s.chain(after: s.partner[brace] + 1)
                switch o.name {
                case "NavigationSplitView":
                    splitViews += 1
                    if after.closures.contains(where: { $0.label == "content" }) { threeColumn = true }
                case "NavigationView":
                    // On macOS a NavigationView is a sidebar split unless it asks for a stack.
                    if after.modifiers.contains(where: { $0.name == "navigationViewStyle" && $0.args.contains("stack") }) { stacks += 1 } else { splitViews += 1 }
                case "NavigationStack": stacks += 1
                case "TabView":
                    // A Settings window's tabs are not the main window's shell.
                    let view = views.filter { $0.open < brace && brace < $0.close }.max { $0.open < $1.open }?.name.lowercased() ?? ""
                    if !view.contains("settings") && !view.contains("preferences") { tabs += 1 }
                default: break
                }
            }
        }
        if splitViews > 0 { shell.navigation = threeColumn ? .splitView3 : .splitView }
        else if stacks > 0 { shell.navigation = .stack }
        else if tabs > 0 { shell.navigation = .tabs }
        if shell.scenes.isEmpty { shell.scenes = ["window"] }
        return shell
    }
}
