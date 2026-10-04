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
        XCTAssertEqual(SwiftStructure.place(forView: "leadingToolbarItem", inStack: false), "toolbar")
        XCTAssertEqual(SwiftStructure.place(forView: "ScriptAsMenuContent", inStack: false), "contextMenu")
        XCTAssertEqual(SwiftStructure.place(forView: "IdentityFormSections", inStack: false), "form")
        XCTAssertNil(SwiftStructure.place(forView: "PlatformPicker", inStack: false), "platform is not form")
        XCTAssertEqual(SwiftStructure.place(forView: "MenuBarPanel", inStack: false), "popover")
        XCTAssertEqual(SwiftStructure.place(forView: "ViewCommands", inStack: false), "contextMenu")
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
