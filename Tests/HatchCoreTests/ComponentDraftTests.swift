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
        XCTAssertEqual(s.template, "glass", "a system from the app remembers the template it is compared with (CD46)")
        let inRow = s.role("button.inRow")!
        XCTAssertEqual(inRow.recipe, ["style": "bordered", "size": "small", "label": "titleOnly"], "the most used look, tooltips aside")
        XCTAssertEqual(inRow.title, "Row action", "the template's words")
        XCTAssertEqual(inRow.status, .provisional)
        XCTAssertNil(inRow.custom)
        // The app's sheets use borderedProminent for the default button: that is a look of its own, kept.
        let sheetDefault = s.role("button.sheetDefault")!
        XCTAssertEqual(sheetDefault.recipe["style"], "borderedProminent")
        XCTAssertEqual(sheetDefault.recipe["key"], "defaultAction", "behaviour most uses share is kept")
        XCTAssertFalse(sheetDefault.followsMacOS)
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
        XCTAssertEqual(s.template, "native", "macOS Native is the template an app is compared with by default (CD46)")
        let q = try XCTUnwrap(s.questions.first { $0.role == "button.inRow" })
        XCTAssertEqual(q.kind, .look)
        XCTAssertEqual(q.options.count, 5, "three looks (one a custom style), Follow macOS and Not sure yet")
        XCTAssertEqual(q.options[0].count, 2, "Native has no row action in cards, so the card's button joins Other action")
        XCTAssertEqual(q.options.last?.title, "Not sure yet")
        // CD28: Native lets macOS draw row actions, so Follow macOS is recommended, and the reason says why.
        XCTAssertEqual(q.options[q.recommended].follow, true)
        XCTAssertTrue(q.reason.contains("lets macOS draw it"), q.reason)

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

    func testAgreeingAfterThreeTickets() throws {
        var s = ComponentTemplates.glass.system(name: "Acme")
        XCTAssertEqual(s.recordUse(roles: ["button.inRow"], ticket: "#1"), [])
        XCTAssertEqual(s.recordUse(roles: ["button.inRow"], ticket: "#1"), [], "a ticket counts once")
        XCTAssertEqual(s.recordUse(roles: ["button.inRow"], ticket: "#2"), [])
        XCTAssertEqual(s.recordUse(roles: ["button.inRow", "button.toolbar"], ticket: "#3"), ["button.inRow"])
        let q = s.questions.first { $0.kind == .confirm }!
        XCTAssertTrue(q.reason.contains("#1, #2, #3"))
        try s.answer(q.id, option: 1)  // Not yet
        XCTAssertEqual(s.role("button.inRow")?.status, .provisional)
        for n in 4...5 { s.recordUse(roles: ["button.inRow"], ticket: "#\(n)") }
        XCTAssertTrue(s.questions.isEmpty, "not asked on every ticket after Not yet")
        s.recordUse(roles: ["button.inRow"], ticket: "#6")
        try s.answer("confirm.button.inRow", option: 0)
        XCTAssertEqual(s.role("button.inRow")?.status, .agreed)
        // A role that follows macOS is agreed as following.
        var n = ComponentTemplates.native.system(name: "Acme")
        for t in ["#1", "#2", "#3"] { n.recordUse(roles: ["button.secondary"], ticket: t) }
        try n.answer("confirm.button.secondary", option: 0)
        XCTAssertTrue(n.role("button.secondary")!.followsMacOS)
        XCTAssertEqual(n.role("button.secondary")?.status, .agreed)
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

    /// CD28 and CD5: Apple's guidance first, then the template's own look (offered even when unused), then use counts.
    func testRecommendationFollowsAppleThenTheTemplate() throws {
        let inv = ComponentInventory(uses: [
            // Row actions: the Glass look (small, bordered, title) is the second most used.
            use("button", "listRow", ["style": "plain"]), use("button", "listRow", ["style": "plain"], line: 2),
            use("button", "listRow", ["style": "bordered", "size": "small", "label": "titleOnly"], line: 3),
            // Toggles: the app never uses Glass's mini switch.
            use("toggle", "form", ["style": "checkbox"], line: 4), use("toggle", "form", ["style": "checkbox", "size": "small"], line: 5),
            // Main actions in rows: glass in content is most used, which Apple argues against.
            use("button", "listRow", ["style": "glassProminent"], .main, line: 6), use("button", "listRow", ["style": "glassProminent"], .main, line: 7),
            use("button", "card", ["style": "borderedProminent"], .main, line: 8),
        ], swiftFiles: 1)
        let s = ComponentDraft.fromApp(name: "Acme", inventory: inv, template: ComponentTemplates.glass)

        let row = try XCTUnwrap(s.questions.first { $0.role == "button.inRow" })
        XCTAssertEqual(row.options[row.recommended].recipe?["style"], "bordered", "the template's look wins over the most used")
        XCTAssertTrue(row.reason.contains("Glass template's look"), row.reason)

        let toggle = try XCTUnwrap(s.questions.first { $0.role == "toggle.setting" })
        let added = toggle.options[toggle.recommended]
        XCTAssertEqual(added.recipe?["style"], "switch", "the template's look is offered although the app doesn't use it")
        XCTAssertEqual(added.count, 0)
        XCTAssertTrue(toggle.reason.contains("doesn't use it yet"), toggle.reason)

        let main = try XCTUnwrap(s.questions.first { $0.role == "button.primaryInRow" })
        XCTAssertEqual(main.options[0].recipe?["style"], "glassProminent", "still listed first: it is the most used")
        XCTAssertEqual(main.options[main.recommended].recipe?["style"], "borderedProminent", "never a look Apple argues against")
        XCTAssertTrue(main.reason.contains("against Apple's guidance"), main.reason)
    }

    /// CD2: a role named after its places gets a job name to rename to; the id stays.
    func testRenameKeepsTheId() throws {
        var s = ComponentTemplates.glass.system(name: "Acme")
        let i = s.roles.firstIndex { $0.id == "button.inRow" }!
        s.roles[i].title = "Button (other, list row, card)"
        XCTAssertEqual(s.suggestedTitle("button.inRow"), "Other action in a row")
        try s.rename("button.inRow", title: "Row action")
        XCTAssertEqual(s.role("button.inRow")?.title, "Row action")
        XCTAssertNil(s.suggestedTitle("button.inRow"), "a real name needs no suggestion")
        XCTAssertThrowsError(try s.rename("button.inRow", title: "  "))
    }

    /// Found in use: a role that follows macOS (the app's most used look was the default) took a look of its own from an
    /// answer but still said it followed macOS, so the system was refused and the answer lost.
    func testALookOfItsOwnStopsFollowingMacOS() throws {
        var s = ComponentTemplates.native.system(name: "Acme")
        XCTAssertTrue(s.role("toggle.setting")!.followsMacOS)
        s.questions = [ComponentQuestion(id: "look.toggle.setting", kind: .look, role: "toggle.setting", title: "?",
                                         options: [.init(title: "Switch", recipe: ["style": "switch"], count: 1, effect: "")], reason: "")]
        try s.answer("look.toggle.setting", option: 0)
        XCTAssertFalse(s.role("toggle.setting")!.followsMacOS)
        XCTAssertEqual(s.problems(), [])
    }

    /// CD51: a checkbox and a toggle button are different controls: two roles, and no question mixes them.
    func testKindsOfControlAreNeverOneRole() {
        let inv = ComponentInventory(uses: [
            use("toggle", "form", ["style": "checkbox"]), use("toggle", "form", ["style": "checkbox"], line: 2),
            use("toggle", "form", ["style": "button"], line: 3), use("toggle", "form", ["style": "button"], line: 4),
            use("picker", "form", ["style": "segmented"], line: 5), use("picker", "form", ["style": "menu"], line: 6),
        ], swiftFiles: 1)
        let s = ComponentDraft.fromApp(name: "Acme", inventory: inv)
        let toggles = s.roles(of: "toggle").filter { $0.places.contains("form") }
        XCTAssertEqual(Set(toggles.map { ComponentDraft.kind("toggle", $0.recipe) }), ["check", "button"])
        XCTAssertTrue(s.roles(of: "toggle").contains { $0.title.hasPrefix("Toggle button") })
        for q in s.questions {
            let kinds = Set(q.options.compactMap(\.recipe).map { ComponentDraft.kind(s.role(q.role!)!.element, $0) })
            XCTAssertLessThanOrEqual(kinds.count, 1, "\(q.id) mixes kinds of control")
        }
        XCTAssertTrue(s.roles(of: "picker").contains { $0.title.hasPrefix("Segmented picker") })
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
        XCTAssertEqual(s.role("button.primaryInRow")?.title, "Main action in a row", "named by its job, not by its places (CD2)")
        XCTAssertEqual(s.role("toggle.inToolbar")?.title, "Setting toggle in the toolbar")
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
        XCTAssertEqual(f.map(\.kind), [.couldUseRole, .mismatch, .noRole, .wrongPlace, .unknownRole, .mismatch],
                       "the menu item follows macOS, so a style written on it is flagged")
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

final class ComponentFollowTests: XCTestCase {
    func use(_ element: String, _ place: String, _ recipe: [String: String], file: String = "App/Desk/A.swift") -> ComponentInventory.Use {
        ComponentInventory.Use(element: element, place: place, recipe: recipe, importance: .other, role: nil, file: file, line: 1, view: "V")
    }

    func testARoleFollowsMacOS() throws {
        var s = ComponentTemplates.glass.system(name: "Acme")
        try s.followMacOS(role: "button.toolbar", decision: "#3")
        let r = s.role("button.toolbar")!
        XCTAssertTrue(r.followsMacOS)
        XCTAssertEqual(r.status, .agreed)
        XCTAssertEqual(r.recipe, ["label": "titleAndIcon", "tooltip": "shortcut"], "behaviour and the label's content stay, styles go")
        XCTAssertEqual(r.lookSummary, "follows macOS; label titleAndIcon, tooltip shortcut")
        XCTAssertEqual(s.problems(), [])
        // Hand styling there is flagged; plain code is fine.
        let f = ComponentCheck.findings([use("button", "toolbar", ["style": "bordered"]), use("button", "toolbar", ["style": "automatic"])], system: s)
        XCTAssertEqual(f.count, 1)
        XCTAssertTrue(f[0].message.contains("follows macOS: remove style bordered"))
        // Code: only behaviour.
        let code = ComponentCodegen.roles(s)
        XCTAssertTrue(code.contains("case .toolbar:\n            // Follows macOS: the system draws it."))
        // Giving it a look again is a redesign.
        try s.setLook("button.toolbar", recipe: ["style": "glass"])
        XCTAssertEqual(s.role("button.toolbar")?.status, .inRedesign)
        XCTAssertFalse(s.role("button.toolbar")!.followsMacOS)
    }

    func testGroupsAndAreasFollowMacOS() throws {
        var s = ComponentTemplates.glass.system(name: "Acme")
        try s.followMacOS(ComponentFollow(element: "button", place: "contextMenu"))
        XCTAssertTrue(s.role("button.menuItem")!.followsMacOS, "the role that only lives in context menus follows too")
        try s.followMacOS(ComponentFollow(element: "button", place: "listRow"))
        XCTAssertFalse(s.role("button.inRow")!.followsMacOS, "a role that also lives elsewhere is left to the owner")
        try s.followMacOS(ComponentFollow(area: "Settings"))
        var config = ProjectConfig(name: "Acme", ticketsRepo: "o/t")
        config.areas = [AreaConfig(name: "Settings", paths: ["App/Settings/**"]), AreaConfig(name: "Desk", paths: ["App/Desk/**"])]
        XCTAssertEqual(config.area(ofFile: "App/Settings/General.swift"), "Settings")
        let uses = [use("toggle", "form", ["style": "switch"], file: "App/Settings/General.swift"),
                    use("toggle", "form", ["style": "switch"], file: "App/Desk/Filters.swift")]
        let f = ComponentCheck.findings(uses, system: s, areaOf: { config.area(ofFile: $0) })
        XCTAssertEqual(f.filter { $0.message.contains("follows macOS") }.map(\.file), ["App/Settings/General.swift"])
        XCTAssertEqual(s.problems(), [])
        let roundTrip = try JSONDecoder().decode(ComponentSystem.self, from: s.encoded())
        XCTAssertEqual(roundTrip.follows, s.follows)
    }

    func testFollowIsAnAnswer() throws {
        let inv = ComponentInventory(uses: [use("button", "toolbar", ["style": "bordered"]), use("button", "toolbar", ["style": "plain"])], swiftFiles: 1)
        var s = ComponentDraft.fromApp(name: "Acme", inventory: inv)
        let q = s.questions.first { $0.role == "button.toolbar" }!
        let i = q.options.firstIndex { $0.follow == true }!
        try s.answer(q.id, option: i)
        XCTAssertTrue(s.role("button.toolbar")!.followsMacOS)
    }
}

final class ComponentRuleTests: XCTestCase {
    let source = #"""
        struct V: View {
            var body: some View {
                List { Text("x") }
                    .contextMenu {
                        Button("Open", systemImage: "arrow.up.forward") {}
                        Button("rename item...") {}
                        Divider()
                        Button("Delete", role: .destructive) {}.keyboardShortcut(.delete)
                        Button("Duplicate") {}
                    }
                    .toolbar { Button("Refresh", systemImage: "arrow.clockwise") {} }
                    .toolbarBackground(.red, for: .windowToolbar)
                    .padding(12)
            }
        }
        struct Cmds: Commands {
            var body: some Commands { CommandMenu("Go") { Button("Open") {} } }
        }
        """#

    func testAppleRulesAreCheckedInTheText() {
        let system = ComponentTemplates.native.system(name: "Acme")
        XCTAssertEqual(system.problems(), [])
        XCTAssertEqual(Set(system.rules.map(\.kind)), Set(ComponentRuleKind.catalog.filter { $0.id != "note" }.map(\.id)))
        XCTAssertTrue(system.rules.first { $0.kind == "destructiveLast" }!.isOff, "Apple states it only for iOS: off until the owner chooses")
        let inv = ComponentInventoryScanner.inventory(files: [("V.swift", source)])
        let f = ComponentRuleCheck.findings(files: [("V.swift", source)], uses: inv.uses, system: system)
        let rules = Set(f.map { $0.role ?? "" })
        XCTAssertEqual(rules, ["menuIcons", "ellipsis", "titleCase", "contextMenuShortcuts", "toolbarInMenuBar", "noBarBackgrounds", "standardSpacing"])
        XCTAssertTrue(f.contains { $0.message.contains("rename item...") && $0.role == "titleCase" })
        XCTAssertTrue(f.allSatisfy { $0.kind == .rule })
    }

    func testRulesCanBeChangedAndNotesAreOnlyRead() {
        var s = ComponentTemplates.glass.system(name: "Acme")
        let i = s.rules.firstIndex { $0.kind == "menuIcons" }!
        s.rules[i].value = "never"
        s.rules.append(ComponentRule(id: "note-1", kind: "note", value: "text", text: "Settings pages open with the most used setting first."))
        XCTAssertEqual(s.problems(), [])
        XCTAssertTrue(s.briefLines().contains("- Rule: Settings pages open with the most used setting first."))
        XCTAssertTrue(s.readme().contains("## Rules"))
        XCTAssertTrue(s.readme().contains("https://developer.apple.com/design/human-interface-guidelines/menus"))
        s.rules[i].value = "sometimes"
        XCTAssertTrue(s.problems().contains { $0.contains("sometimes is not a value") })
    }

    func testConfigurableRulesAndRolesAreNotHeldToIt() throws {
        var s = ComponentTemplates.glass.system(name: "Acme")
        try s.makeConfigurable("titleCase")
        try s.makeConfigurable("button.inRow")
        let inv = ComponentInventoryScanner.inventory(files: [("V.swift", source)])
        XCTAssertFalse(ComponentRuleCheck.findings(files: [("V.swift", source)], uses: inv.uses, system: s).contains { $0.role == "titleCase" })
        let use = ComponentInventory.Use(element: "button", place: "listRow", recipe: ["style": "glass"], importance: .other, role: nil, file: "A.swift", line: 1, view: "V")
        XCTAssertTrue(ComponentCheck.findings([use], system: s).isEmpty, "other looks are fine until the setting exists")
        XCTAssertTrue(s.readme().contains("Will become a setting"))
        XCTAssertThrowsError(try s.makeConfigurable("nothing"))
    }

    func testCapitalization() {
        XCTAssertNil(ComponentRuleCheck.capitalizationProblem("Open in New Window", rule: "titleCase"))
        XCTAssertNotNil(ComponentRuleCheck.capitalizationProblem("Open in new window", rule: "titleCase"))
        XCTAssertNil(ComponentRuleCheck.capitalizationProblem("Save", rule: "titleCase"), "one word says nothing")
        XCTAssertNotNil(ComponentRuleCheck.capitalizationProblem("Open In New Window", rule: "sentenceCase"))
        XCTAssertNil(ComponentRuleCheck.capitalizationProblem("Run \\(name) now", rule: "titleCase"), "interpolation is skipped")
    }
}

final class ComponentShellTests: XCTestCase {
    func testShellsAreRead() {
        let split = """
            @main struct A: App {
                var body: some Scene {
                    WindowGroup { ContentView() }
                    Settings { SettingsView() }
                    MenuBarExtra("x") { Text("y") }.menuBarExtraStyle(.window)
                }
            }
            struct ContentView: View {
                var body: some View {
                    NavigationSplitView {
                        Sidebar()
                    } detail: {
                        NavigationStack { Detail() }
                    }
                    #if os(macOS)
                    .frame(minWidth: 600)
                    #endif
                    .inspector(isPresented: $on) { Text("i") }
                    .toolbar { Button("A") {} }
                    .searchable(text: $q)
                }
            }
            struct SettingsView: View { var body: some View { TabView { Text("General") } } }
            """
        let shell = ComponentShell.detect(files: [("App.swift", split)])
        XCTAssertEqual(shell.navigation, .splitView)
        XCTAssertEqual(Set(shell.scenes), ["window", "settings", "menuBarWindow"])
        XCTAssertTrue(shell.inspector && shell.toolbar && shell.search)
        let old = "struct C: View { var body: some View { NavigationView { List { Text(\"a\") }; Text(\"b\") } } }"
        XCTAssertEqual(ComponentShell.detect(files: [("C.swift", old)]).navigation, .splitView, "NavigationView on macOS is a sidebar split")
        let three = "struct C: View { var body: some View { NavigationSplitView { A() } content: { B() } detail: { D() } } }"
        XCTAssertEqual(ComponentShell.detect(files: [("C.swift", three)]).navigation, .splitView3)
    }
}
