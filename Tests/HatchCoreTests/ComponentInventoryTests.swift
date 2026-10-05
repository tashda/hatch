import XCTest
@testable import HatchCore

final class ComponentInventoryTests: XCTestCase {
    let source = #"""
        import SwiftUI

        struct DeskView: View {
            var body: some View {
                List {
                    ForEach(items) { item in
                        Text(item.title)
                            .contextMenu { rowMenu(item) }
                    }
                }
                .toolbar {
                    ToolbarItem {
                        Button("Refresh", systemImage: "arrow.clockwise") { reload() }.help("Refresh (⌘R)")
                    }
                }
                .searchable(text: $query)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button { accept() } label: { Label("Accept", systemImage: "checkmark") }
                            .buttonStyle(.glassProminent)
                            .keyboardShortcut(.defaultAction)
                        Button("Later") { later() }
                        Button("Note") { note() }.buttonStyle(.bordered)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                .alert("Drop it?", isPresented: $confirm) {
                    Button("Drop", role: .destructive) { drop() }
                    Button("Cancel", role: .cancel) {}
                }
                ZStack {
                    Button("Next") { next() }.keyboardShortcut(.downArrow)
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                // Button("Commented out") {}
                Text("Button(\"in a string\") { }")
                Text(#"raw "Button(" text"#)
                Text("\(count > 1 ? "Button(" : "x")")
            }

            @ViewBuilder private func rowMenu(_ item: Item) -> some View {
                Button("Open") { open(item) }
                Button("Close", role: .destructive) { close(item) }
            }

            private var header: some View {
                HStack {
                    Menu {
                        Button("Park") { park() }
                    } label: { Label("More", systemImage: "ellipsis") }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(.glass)
                }
            }
        }

        struct TicketRow: View {
            var body: some View {
                HStack {
                    Text("x")
                    Button { open() } label: { Image(systemName: "arrow.up.forward") }
                        .buttonStyle(.borderless)
                        .buttonRole(.inRow)
                }
            }
        }

        struct SettingsPage: View {
            var body: some View {
                Form {
                    Toggle("Sync", isOn: $sync).toggleStyle(.switch)
                    Picker("Model", selection: $model) { Text("A") }.pickerStyle(.menu)
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                }
            }
        }

        struct RenameSheet: View {
            var body: some View {
                VStack { TextField("Name", text: $name) }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
                    }
            }
        }

        #Preview {
            Button("Preview only") {}
        }
        """#

    lazy var uses = ComponentInventoryScanner.uses(in: source, file: "App/Desk.swift")

    func use(_ line: Int) -> ComponentInventory.Use? { uses.first { $0.line == line } }
    func use(titled marker: String) -> ComponentInventory.Use? {
        let lines = source.components(separatedBy: "\n")
        guard let i = lines.firstIndex(where: { $0.contains(marker) }) else { return nil }
        return use(i + 1)
    }

    func testStringsCommentsPreviewsAndHiddenButtonsAreSkipped() {
        XCTAssertNil(use(titled: "Commented out"))
        XCTAssertNil(use(titled: "in a string"))
        XCTAssertNil(use(titled: "raw \"Button("))
        XCTAssertNil(use(titled: "Preview only"))
        XCTAssertNil(use(titled: "Button(\"Next\")"), "a zero-size, transparent button is only there for its shortcut")
        XCTAssertEqual(uses.filter { $0.element == "button" }.count, 11)
    }

    func testToolbarAndSearch() {
        let refresh = use(titled: "Refresh")!
        XCTAssertEqual(refresh.place, "toolbar")
        XCTAssertEqual(refresh.recipe, ["style": "automatic", "label": "titleAndIcon", "tooltip": "title"])
        let search = uses.first { $0.element == "field" && $0.place == "toolbar" }
        XCTAssertNotNil(search)
    }

    func testStylesCascadeAndTheNearestWins() {
        let accept = use(titled: "Label(\"Accept\"")!
        XCTAssertEqual(accept.place, "bottomBar")
        XCTAssertEqual(accept.recipe["style"], "glassProminent", "its own style beats the stack's")
        XCTAssertEqual(accept.recipe["size"], "large", "the stack's size reaches it")
        XCTAssertEqual(accept.recipe["label"], "titleAndIcon")
        XCTAssertEqual(accept.recipe["key"], "defaultAction")
        XCTAssertEqual(accept.importance, .main)
        XCTAssertEqual(use(titled: "Button(\"Later\")")?.recipe["style"], "glass")
        XCTAssertEqual(use(titled: "Button(\"Note\")")?.recipe["style"], "bordered")
        XCTAssertEqual(use(titled: "Button(\"Later\")")?.importance, .other)
    }

    func testAlertItemsAndImportance() {
        XCTAssertEqual(use(titled: "Button(\"Drop\"")?.place, "alert")
        XCTAssertEqual(use(titled: "Button(\"Drop\"")?.importance, .destructive)
        XCTAssertEqual(use(titled: "Button(\"Cancel\"")?.importance, .quiet)
    }

    func testHelpersTakeThePlaceOfTheirCallSite() {
        let open = use(titled: "Button(\"Open\")")!
        XCTAssertEqual(open.place, "contextMenu", "rowMenu is called inside .contextMenu")
        XCTAssertEqual(use(titled: "Button(\"Close\"")?.importance, .destructive)
    }

    func testMenuItemsDoNotTakeTheMenuButtonsLook() {
        let park = use(titled: "Button(\"Park\")")!
        XCTAssertEqual(park.place, "contextMenu")
        XCTAssertEqual(park.recipe["style"], "automatic", "the glass style after the Menu is the menu button's, not its items'")
        let menu = uses.first { $0.element == "menu" }!
        XCTAssertEqual(menu.recipe["style"], "button")
        XCTAssertEqual(menu.recipe["look"], "glass")
        XCTAssertEqual(menu.recipe["indicator"], "hidden")
        XCTAssertEqual(menu.recipe["label"], "titleAndIcon")
    }

    func testViewNamesAndRoles() {
        let row = use(titled: "Image(systemName: \"arrow.up.forward\")")!
        XCTAssertEqual(row.place, "listRow")
        XCTAssertEqual(row.recipe["label"], "iconOnly")
        XCTAssertEqual(row.role, "button.inRow")
        XCTAssertEqual(row.view, "TicketRow")
    }

    func testFormControls() {
        let toggle = uses.first { $0.element == "toggle" }!
        XCTAssertEqual(toggle.place, "form")
        XCTAssertEqual(toggle.recipe, ["style": "switch"])
        XCTAssertEqual(uses.first { $0.element == "picker" }?.recipe["style"], "menu")
        XCTAssertEqual(uses.first { $0.element == "field" && $0.place == "form" }?.recipe["style"], "roundedBorder")
    }

    func testSheetFooterFromConfirmationPlacement() {
        XCTAssertEqual(use(titled: "Button(\"Save\")")?.place, "sheetFooter")
        XCTAssertEqual(use(titled: "VStack { TextField")?.place, "page", "a view nothing uses is a window's or sheet's content")
    }

    func testReusableViewsTakeThePlaceAndStylesOfTheirUses() {
        let keyView = """
            struct KeyChip: View {
                var body: some View {
                    HStack { Button("Record") { record() } }
                }
            }
            """
        let toolbar = """
            struct EditorView: View {
                var body: some View {
                    Text("x").toolbar {
                        ToolbarItem { KeyChip().buttonStyle(.glass) }
                    }
                }
            }
            """
        let list = """
            struct ShortcutsList: View {
                var body: some View {
                    List { KeyChip(); KeyChip() }
                }
            }
            """
        let host = """
            final class PanelController {
                func show() { let v = NSHostingView(rootView: AboutView()) }
            }
            struct AboutView: View {
                var body: some View { VStack { Button("Done") { close() } } }
            }
            """
        let inv = ComponentInventoryScanner.inventory(files: [("Key.swift", keyView), ("Editor.swift", toolbar), ("List.swift", list), ("Host.swift", host)])
        let record = inv.uses.first { $0.file == "Key.swift" }!
        XCTAssertEqual(record.place, "listRow", "two uses in a List beat one in a toolbar")
        XCTAssertEqual(record.trail.first { $0.hasPrefix("used in") }, "used in 3 places")
        let done = inv.uses.first { $0.file == "Host.swift" }!
        XCTAssertEqual(done.place, "page", "a view AppKit hosts is a window's content")

        let one = ComponentInventoryScanner.inventory(files: [("Key.swift", keyView), ("Editor.swift", toolbar)])
        let inToolbar = one.uses.first { $0.file == "Key.swift" }!
        XCTAssertEqual(inToolbar.place, "toolbar")
        XCTAssertEqual(inToolbar.recipe["style"], "glass", "the style set where the view is used reaches its buttons")
    }

    func testNamesAreReadAsWords() {
        XCTAssertEqual(SwiftStructure.words("HXSetupRow"), ["hx", "setup", "row"])
        XCTAssertEqual(SwiftStructure.words("leadingToolbarItem"), ["leading", "toolbar", "item"])
        // Names only break ties; toolbar, menus, popovers and inspectors come from real modifiers.
        for name in ["leadingToolbarItem", "TabSectionToolbar", "ScriptAsMenuContent", "ViewCommands", "filterRow"] {
            XCTAssertNil(SwiftStructure.place(forView: name, inStack: false), name)
        }
        XCTAssertEqual(SwiftStructure.place(forView: "IdentityFormSections", inStack: false), "form")
        XCTAssertNil(SwiftStructure.place(forView: "PlatformPicker", inStack: false), "platform is not form")
        XCTAssertEqual(SwiftStructure.place(forView: "UnavailableStateView", inStack: false), "emptyState")
        XCTAssertEqual(SwiftStructure.place(forView: "SettingsCard", inStack: false), "card")
        // Panel and Pane names were wrong 5 times in 6 on a held-out sample; only Inspector names count.
        XCTAssertNil(SwiftStructure.place(forView: "ProviderDetailPanel", inStack: false))
        XCTAssertEqual(SwiftStructure.place(forView: "OutlineInspectorView", inStack: false), "inspector")
        XCTAssertEqual(SwiftStructure.place(forView: "MenuBarPanel", inStack: false), "popover")
        XCTAssertEqual(SwiftStructure.place(forView: "actionRow", inStack: false), "actionRow")
    }

    func testOnlyTheMacsCodeIsRead() {
        let text = """
            struct V: View {
                var body: some View {
                    VStack {
                        #if os(iOS)
                        Button("Phone") {}.buttonStyle(.borderedProminent)
                        #elseif os(macOS)
                        Button("Mac") {}.buttonStyle(.glass)
                        #else
                        Button("Other") {}
                        #endif
                        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
                        Button("UIKit") {}
                        #endif
                        #if DEBUG
                        Button("Debug") {}
                        #endif
                    }
                }
            }
            """
        let uses = ComponentInventoryScanner.uses(in: text, file: "V.swift")
        XCTAssertEqual(uses.map(\.line), [7, 15])
        XCTAssertEqual(uses.first?.recipe["style"], "glass")
        XCTAssertTrue(PlatformCondition.evaluate(" os(macOS) || os(iOS)"))
        XCTAssertFalse(PlatformCondition.evaluate(" os(iOS) || os(visionOS)"))
        XCTAssertTrue(PlatformCondition.evaluate(" !os(iOS)"))
        XCTAssertTrue(ComponentInventoryScanner.isOtherPlatform("TableProMobile/Views/A.swift"))
        XCTAssertTrue(ComponentInventoryScanner.isOtherPlatform("App/Views/List+iOS.swift"))
        XCTAssertFalse(ComponentInventoryScanner.isOtherPlatform("App/macOS/List.swift"))
        XCTAssertFalse(ComponentInventoryScanner.isOtherPlatform("App/Views/MacOSSettings.swift"))
    }

    func testStructureRulesFromTheAudits() {
        let text = #"""
            struct Editor: View {
                var body: some View {
                    VStack {
                        Text("Title").font(.largeTitle)
                        HStack { Button("Share") {}; Button("Export") {} }
                        HStack {
                            Button("Cancel", role: .cancel) {}.keyboardShortcut(.cancelAction)
                            Button("Save") {}.keyboardShortcut(.defaultAction)
                        }
                        LazyVGrid(columns: cols) { ForEach(items) { i in Button("Open") {} } }
                        GlassEffectContainer { HStack { Button("Zoom") {} } }
                        VStack { Button("Card action") {} }.padding().background(.background, in: RoundedRectangle(cornerRadius: 12))
                        Picker("Kind", selection: $k) { Text("A") }
                    }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") {} } }
                    .accessibilityActions { Button("Hidden") {} }
                }
            }
            struct Plain: PrimitiveButtonStyle {
                func makeBody(configuration: Configuration) -> some View { Button(configuration) }
            }
            struct Bar: App {
                var body: some Scene {
                    MenuBarExtra("x") { Button("Quit") {} }
                }
            }
            let k = Kind.searchable(options: [])
            """#
        let uses = ComponentInventoryScanner.uses(in: text, file: "Editor.swift")
        func place(_ title: String) -> String? { uses.first { u in text.components(separatedBy: "\n")[u.line - 1].contains(title) }?.place }
        XCTAssertEqual(place("Share"), "actionRow")
        XCTAssertEqual(place("Cancel"), "sheetFooter")
        XCTAssertEqual(place("Open"), "listRow")
        XCTAssertEqual(place("Zoom"), "floating")
        XCTAssertEqual(place("Card action"), "card")
        let done = uses.first { text.components(separatedBy: "\n")[$0.line - 1].contains("Done") }!
        XCTAssertEqual(done.place, "sheetFooter")
        XCTAssertEqual(done.importance, .main)
        XCTAssertEqual(done.recipe["key"], "defaultAction")
        XCTAssertEqual(place("Quit"), "contextMenu", "a MenuBarExtra without the window style is a menu")
        XCTAssertNil(place("Hidden"))
        XCTAssertFalse(uses.contains { text.components(separatedBy: "\n")[$0.line - 1].contains("makeBody") })
        XCTAssertFalse(uses.contains { $0.element == "field" }, "an enum case named searchable is not the modifier")
    }

    func testTheAppsOwnContainersAndStyleWrappers() {
        let container = """
            struct SheetLayout<Content: View, Footer: View>: View {
                @ViewBuilder let content: () -> Content
                @ViewBuilder let footer: () -> Footer
                var body: some View {
                    VStack {
                        content()
                        HStack { Spacer(); footer() }.controlSize(.large)
                    }
                }
            }
            extension View {
                func checkboxStyle() -> some View { toggleStyle(.checkbox) }
                func fancyButtonStyle(style: FancyStyle) -> some View { buttonStyle(style.native) }
            }
            struct GlassButton: ViewModifier {
                func body(content: Content) -> some View { content.buttonStyle(.glassProminent).controlSize(.large) }
            }
            """
        let use = """
            struct Export: View {
                var body: some View {
                    SheetLayout {
                        Toggle("All", isOn: $all).checkboxStyle()
                    } footer: {
                        Button("Go") {}.modifier(GlassButton())
                        Button("Fancy") {}.fancyButtonStyle(style: .glass)
                    }
                }
            }
            """
        let inv = ComponentInventoryScanner.inventory(files: [("SheetLayout.swift", container), ("Export.swift", use)])
        let toggle = inv.uses.first { $0.element == "toggle" }!
        XCTAssertEqual(toggle.recipe["style"], "checkbox", "a wrapper that only applies a style is expanded")
        let go = inv.uses.first { $0.line == 6 && $0.file == "Export.swift" }!
        XCTAssertEqual(go.recipe["style"], "glassProminent")
        XCTAssertEqual(go.recipe["size"], "large")
        XCTAssertEqual(go.place, "sheetFooter", "footer() sits in a stack with a Spacer at the bottom: found inside the container")
        let fancy = inv.uses.first { $0.line == 7 && $0.file == "Export.swift" }!
        XCTAssertEqual(fancy.recipe["style"], "glass", "the style named at the call wins")
    }

    func testClustersRecommendTheMostUsedLook() {
        let inv = ComponentInventory(uses: [
            .init(element: "button", place: "listRow", recipe: ["style": "bordered", "size": "small"], importance: .other, role: nil, file: "a.swift", line: 1, view: nil),
            .init(element: "button", place: "listRow", recipe: ["style": "bordered", "size": "small"], importance: .other, role: nil, file: "a.swift", line: 1, view: nil),
            .init(element: "button", place: "listRow", recipe: ["style": "bordered", "size": "small"], importance: .other, role: nil, file: "b.swift", line: 9, view: nil),
            .init(element: "button", place: "listRow", recipe: ["style": "plain"], importance: .other, role: "button.inRow", file: "c.swift", line: 2, view: nil),
            .init(element: "button", place: nil, recipe: ["style": "plain"], importance: .quiet, role: nil, file: "d.swift", line: 3, view: nil),
        ], swiftFiles: 4)
        let looks = inv.clusters(element: "button", place: "listRow")
        XCTAssertEqual(looks.map(\.count), [3, 1])
        XCTAssertEqual(looks[0].signature, "style bordered, size small")
        XCTAssertEqual(looks[0].examples, ["a.swift:1", "b.swift:9"], "examples are distinct")
        XCTAssertEqual(inv.places(of: "button").map(\.place), ["listRow", nil], "unknown comes last")
        XCTAssertEqual(inv.coverage.withRole, 1)
        XCTAssertEqual(inv.unknownFiles().first?.file, "d.swift")
    }

    func testScanSkipsTestsAndExcludedFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, text) in [("App/A.swift", "struct A: View { var body: some View { Button(\"x\") {} } }"),
                             ("AppTests/T.swift", "struct T: View { var body: some View { Button(\"x\") {} } }"),
                             ("Packages/UI/B.swift", "struct B: View { var body: some View { Button(\"x\") {} } }")] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let inv = ComponentInventoryScanner.scan(appRoot: root.path, excluding: ["Packages/UI"])
        XCTAssertEqual(inv.uses.map(\.file), ["App/A.swift"])
    }
}
