import XCTest
@testable import HatchCore

final class ComponentDraftTests: XCTestCase {
    func use(_ element: String, _ place: String?, _ recipe: [String: String], _ importance: ComponentRole.Importance = .other,
             file: String = "A.swift", line: Int = 1, view: String? = "V", role: String? = nil, branches: [String] = []) -> ComponentInventory.Use {
        ComponentInventory.Use(element: element, place: place, recipe: recipe, importance: importance, role: role, file: file, line: line,
                               view: view, branches: branches)
    }

    lazy var inventory = ComponentInventory(uses: [
        // Rows: bordered small three times, plain once.
        use("button", "listRow", ["style": "bordered", "size": "small", "label": "titleOnly"], line: 1),
        use("button", "listRow", ["style": "bordered", "size": "small", "label": "titleOnly", "tooltip": "title"], line: 2),
        use("button", "card", ["style": "bordered", "size": "small", "label": "titleOnly"], line: 3),
        use("button", "listRow", ["style": "plain", "label": "iconOnly"], line: 4),
        // Main actions in sheets.
        use("button", "sheetFooter", ["style": "borderedProminent", "label": "titleOnly", "key": "defaultAction"], .main, line: 5),
        use("button", "sheetFooter", ["style": "automatic", "label": "titleOnly", "key": "cancelAction"], .quiet, line: 6),
        // A place the Glass template has no button role for at this importance: form.
        use("button", "form", ["style": "link", "label": "titleOnly"], .quiet, line: 7),
        // A custom style and an unknown place.
        use("button", "popover", ["style": "custom:MenuRowStyle", "label": "titleAndIcon"], line: 8),
        use("button", nil, ["style": "glass"], line: 9),
        // Menu items.
        use("button", "contextMenu", ["style": "automatic", "label": "titleOnly"], line: 10),
    ], swiftFiles: 1)

    func testDraftUsesTheTemplateAsSkeletonAndTheAppsLooks() {
        let s = ComponentDraft.fromApp(name: "Acme", inventory: inventory, template: ComponentTemplates.glass, minimumMacOS: "14.0")
        XCTAssertEqual(s.problems(), [])
        XCTAssertEqual(s.minimumMacOS, "14.0")
        XCTAssertNil(s.template, "a system from the app is not a template's")
        let inRow = s.role("button.inRow")!
        XCTAssertEqual(inRow.recipe, ["style": "bordered", "size": "small", "label": "titleOnly"], "the most used look, tooltips aside")
        XCTAssertEqual(inRow.title, "Row action", "the template's words")
        XCTAssertEqual(inRow.status, .provisional)
        XCTAssertNil(inRow.custom)
        let primary = s.role("button.primary")!
        XCTAssertEqual(primary.recipe["style"], "borderedProminent")
        XCTAssertEqual(primary.recipe["key"], "defaultAction", "behaviour most uses share is kept")
        XCTAssertEqual(s.role("button.cancel")?.recipe["key"], "cancelAction")
        XCTAssertEqual(s.role("button.menuItem")?.places, ["contextMenu"])
        // The link in a form joins the Link role, whose places include form.
        XCTAssertEqual(s.role("button.link")?.recipe["style"], "link")
        // The custom style is one of the row role's looks, offered with its name.
        XCTAssertTrue(s.questions.first { $0.role == "button.inRow" }!.options.contains { $0.custom == "MenuRowStyle" })
        // Unused template roles stay as guesses.
        XCTAssertTrue(s.role("toast.feedback")!.use.contains("Not used in the app yet"))
    }

    func testOneQuestionPerRoleWithSeveralLooks() throws {
        var s = ComponentDraft.fromApp(name: "Acme", inventory: inventory)
        let q = try XCTUnwrap(s.questions.first { $0.role == "button.inRow" })
        XCTAssertEqual(q.kind, .look)
        XCTAssertEqual(q.options.count, 4, "three looks (one a custom style) and Not sure yet")
        XCTAssertEqual(q.options[0].count, 3)
        XCTAssertEqual(q.recommended, 0)
        XCTAssertTrue(q.reason.contains("3 of 5"))
        XCTAssertEqual(q.options.last?.title, "Not sure yet")
        XCTAssertFalse(q.reason.contains("macOS 27 reference"), "Glass's row look is bordered small, which is option 1")

        let plain = q.options.firstIndex { $0.recipe?["style"] == "plain" }!
        try s.answer(q.id, option: plain, decision: "#7")
        XCTAssertEqual(s.role("button.inRow")?.recipe["style"], "plain")
        XCTAssertEqual(s.role("button.inRow")?.status, .agreed)
        XCTAssertEqual(s.role("button.inRow")?.decision, "#7")
        XCTAssertFalse(s.questions.contains { $0.id == q.id })
        XCTAssertThrowsError(try s.answer(q.id, option: 0))
    }

    func testNotSureYetKeepsTheGuess() throws {
        var s = ComponentDraft.fromApp(name: "Acme", inventory: inventory)
        let q = s.questions.first { $0.role == "button.inRow" }!
        try s.answer(q.id, option: q.options.count - 1)
        XCTAssertEqual(s.role("button.inRow")?.status, .provisional)
        XCTAssertEqual(s.role("button.inRow")?.recipe["style"], "bordered")
    }

    func testAgreeAndVariants() throws {
        var s = ComponentTemplates.glass.system(name: "Acme")
        try s.agree("button.inRow")
        XCTAssertEqual(s.role("button.inRow")?.status, .agreed)
        try s.addVariant(to: "button.inRow", id: "icon", use: "Rows with little room: the icon only.", recipe: ["style": "bordered", "label": "iconOnly"])
        XCTAssertEqual(s.role("button.inRow")?.variants.first?.recipe, ["label": "iconOnly"], "only what differs")
        try s.agree()
        XCTAssertEqual(s.counts.provisional, 0)
        XCTAssertEqual(s.problems(), [])
    }

    func testNamesReadLikeTheTemplateAndLeftoversByFamily() {
        let inv = ComponentInventory(uses: [
            use("button", "listRow", ["style": "glassProminent"], .main),
            use("button", "card", ["style": "glassProminent"], .main),
            use("toggle", "toolbar", ["style": "checkbox"]),
        ], swiftFiles: 1)
        let s = ComponentDraft.fromApp(name: "Acme", inventory: inv)
        XCTAssertNotNil(s.role("button.primaryInRow"), "main actions in rows are their own role, one per row")
        XCTAssertNil(s.role("button.primaryInRow")?.perScreen)
        XCTAssertNotNil(s.role("toggle.toolbar"))
        XCTAssertEqual(s.problems(), [])
    }

    func testMinimumMacOSFromProjects() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
        try "MACOSX_DEPLOYMENT_TARGET = 14.0;\nMACOSX_DEPLOYMENT_TARGET = 14.0;\nMACOSX_DEPLOYMENT_TARGET = 13.0;".write(
            to: root.appendingPathComponent("App.xcodeproj/project.pbxproj"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ComponentInventoryScanner.minimumMacOS(appRoot: root.path), "14.0", "the value most targets use")
        let pkg = root.appendingPathComponent("Pkg")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try "let p = Package(platforms: [.macOS(.v26)])".write(to: pkg.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ComponentInventoryScanner.minimumMacOS(appRoot: pkg.path), "26.0")
    }
}

final class ComponentCheckTests: XCTestCase {
    let system = ComponentTemplates.glass.system(name: "Acme")

    func use(_ place: String?, _ recipe: [String: String], _ importance: ComponentRole.Importance = .other, line: Int = 1,
             view: String? = "V", role: String? = nil, branches: [String] = [], element: String = "button") -> ComponentInventory.Use {
        ComponentInventory.Use(element: element, place: place, recipe: recipe, importance: importance, role: role, file: "A.swift", line: line,
                               view: view, branches: branches)
    }

    func testKindsOfFinding() {
        let uses = [
            use("listRow", ["style": "bordered", "size": "small", "label": "titleOnly"], line: 1),         // matches inRow
            use("listRow", ["style": "glass", "size": "small", "label": "titleOnly"], line: 2),            // differs
            use("toolbar", ["style": "automatic"], .main, line: 3),                                         // no role
            use("listRow", [:], line: 4, role: "button.primary"),                                           // out of place
            use("listRow", [:], line: 5, role: "button.fancy"),                                             // unknown
            use("contextMenu", ["style": "glass"], line: 6),                                                // menu item: never differs
            use(nil, ["style": "glass"], line: 7),                                                          // unknown place: skipped
            use("listRow", ["style": "bordered", "size": "small", "label": "titleOnly"], line: 8, role: "button.inRow"),
        ]
        let f = ComponentCheck.findings(uses, system: system)
        XCTAssertEqual(f.map(\.kind), [.couldUseRole, .mismatch, .noRole, .wrongPlace, .unknownRole])
        XCTAssertTrue(f[0].message.contains(".buttonRole(.inRow)"))
        XCTAssertTrue(f[1].message.contains("style glass (role: bordered)"))
        XCTAssertTrue(f[3].message.contains("use button.inRow"))
        let cov = ComponentCheck.coverage(uses, system: system)
        XCTAssertEqual(cov.usingRole, 3)
        XCTAssertEqual(cov.total, 7)
    }

    func testGuessedPlacesAreUnsure() {
        var guessed = use("listRow", ["style": "glass"], line: 1)
        guessed.evidence = "name"
        let f = ComponentCheck.findings([guessed, use("listRow", ["style": "glass"], line: 2)], system: system)
        XCTAssertEqual(f.map(\.certain), [false, true])
        XCTAssertTrue(f[0].message.contains("Place guessed"))
    }

    func testVariantsAndLabelsTheScannerCannotRead() {
        var s = system
        try? s.addVariant(to: "button.inRow", id: "icon", use: "Tight rows.", recipe: ["label": "iconOnly"])
        let f = ComponentCheck.findings([
            use("listRow", ["style": "bordered", "size": "small", "label": "iconOnly"], line: 1),
            use("listRow", ["style": "bordered", "size": "small", "label": "custom"], line: 2),
        ], system: s)
        XCTAssertEqual(f.map(\.kind), [.couldUseRole, .couldUseRole])
    }

    func testOneMainActionPerScreenButNotAcrossBranches() {
        let prominent = ["style": "glassProminent", "size": "large", "label": "titleAndIcon", "shape": "capsule"]
        let f = ComponentCheck.findings([
            use("bottomBar", prominent, .main, line: 1, branches: ["if@10#10"]),
            use("bottomBar", prominent, .main, line: 2, branches: ["if@10#20"]),   // the else branch
            use("bottomBar", prominent, .main, line: 3),                          // always shown: a second one
        ], system: system).filter { $0.kind == .tooMany }
        XCTAssertEqual(f.map(\.line), [3])
    }

    func testBranchesFromSource() {
        let text = """
            struct V: View {
                var body: some View {
                    HStack {
                        if a {
                            Button("One") {}.buttonStyle(.glassProminent)
                        } else if b {
                            Button("Two") {}.buttonStyle(.glassProminent)
                        } else {
                            Button("Three") {}.buttonStyle(.glassProminent)
                        }
                        switch mode {
                        case .x: Button("Four") {}
                        case .y: Button("Five") {}
                        }
                    }
                }
            }
            """
        let uses = ComponentInventoryScanner.uses(in: text, file: "V.swift")
        XCTAssertEqual(uses.count, 5)
        XCTAssertTrue(ComponentInventory.exclusive(uses[0], uses[1]))
        XCTAssertTrue(ComponentInventory.exclusive(uses[0], uses[2]))
        XCTAssertTrue(ComponentInventory.exclusive(uses[3], uses[4]))
        XCTAssertFalse(ComponentInventory.exclusive(uses[0], uses[3]))
    }

    func testDiffLines() {
        let diff = """
            diff --git a/A.swift b/A.swift
            --- a/A.swift
            +++ b/A.swift
            @@ -10,0 +11,2 @@
            +Button("x") {}
            +Button("y") {}
            @@ -40 +42 @@
            -old
            +new
            """
        XCTAssertEqual(ComponentCheck.addedLines(diff: diff)["A.swift"], [11, 12, 42])
    }
}
