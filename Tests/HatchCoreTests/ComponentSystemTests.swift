import XCTest
@testable import HatchCore

final class ComponentSystemTests: XCTestCase {
    func testTemplatesAreNativeFirst() {
        for t in ComponentTemplates.all {
            let s = t.system(name: "Acme")
            XCTAssertEqual(s.advice().map(\.message), [], "\(t.id) sets nothing macOS does anyway and nothing against Apple's guidance")
            for r in s.roles {
                XCTAssertFalse(r.sources.isEmpty, "\(t.id) \(r.id) says which Apple page it follows")
                for id in r.sources { XCTAssertNotNil(ComponentNative.reference(id), id) }
            }
        }
        let native = ComponentTemplates.native.system(name: "Acme")
        XCTAssertGreaterThan(native.roles.filter(\.followsMacOS).count, native.roles.count / 2, "macOS Native mostly follows macOS")
    }

    func testAdviceFindsWhatFightsTheSystem() {
        var s = ComponentTemplates.glass.system(name: "Acme")
        s.roles.append(ComponentRole("button.rowGlass", "x", use: "x", places: ["form"], importance: .quiet, recipe: ["style": "glass", "size": "regular", "key": "defaultAction"]))
        s.roles.append(ComponentRole("menu.inMenu", "x", use: "x", places: ["contextMenu"], importance: .other, recipe: ["look": "bordered"]))
        s.roles.append(ComponentRole("switcher.page", "x", use: "x", places: ["page"], importance: .other, recipe: ["style": "segmented"]))
        let kinds = Set(s.advice().map(\.kind))
        XCTAssertEqual(kinds, [.redundant, .glassInContent, .wrongDefault, .systemPlace, .switcherInContent])
        XCTAssertTrue(s.advice().allSatisfy { ComponentNative.reference($0.source) != nil })
        XCTAssertTrue(ComponentNative.stale(installedSDK: "27.0").isEmpty)
        XCTAssertEqual(ComponentNative.stale(installedSDK: "28.0").count, ComponentNative.references.count)
    }

    func testDesignDocumentKeepsHandWrittenText() {
        let s = ComponentTemplates.glass.system(name: "Hatch")
        let doc = "# Hatch design rules\n\n## Principles\n\n1. Native first.\n"
        let once = s.designDocument(updating: doc)
        XCTAssertTrue(once.hasPrefix(doc), "principles stay")
        XCTAssertTrue(once.contains(ComponentSystem.designStart) && once.contains("## Buttons"))
        XCTAssertEqual(s.designDocument(updating: once), once, "regenerating changes nothing")
        var t = s
        try? t.followMacOS(role: "button.inRow")
        let twice = t.designDocument(updating: once)
        XCTAssertTrue(twice.hasPrefix(doc))
        XCTAssertEqual(twice.components(separatedBy: ComponentSystem.designStart).count, 2, "replaced, not added again")
    }

    func testTemplatesHaveNoProblems() {
        XCTAssertEqual(ComponentTemplates.all.map(\.id), ["native", "glass", "compact"], "Compact ships now (CD6)")
        for t in ComponentTemplates.all {
            let s = t.system(name: "Acme")
            XCTAssertEqual(s.problems(), [], t.id)
            XCTAssertEqual(s.template, t.id)
            XCTAssertTrue(s.roles.allSatisfy { $0.status == .provisional }, "a template is a guess until the owner agrees (DS8)")
            XCTAssertGreaterThanOrEqual(s.elementsUsed.count, 10, t.id)
        }
        XCTAssertNotNil(ComponentTemplates.named("Glass"))
        XCTAssertNotNil(ComponentTemplates.named("compact"), "Compact ships now (CD6)")
    }

    func testRoleTableAnswersWhichButtonWhere() {
        let s = ComponentTemplates.glass.system(name: "Hatch")
        XCTAssertEqual(s.role(element: "button", place: "actionRow", importance: .main)?.id, "button.primary")
        XCTAssertEqual(s.role(element: "button", place: "actionRow", importance: .other)?.id, "button.secondary")
        XCTAssertEqual(s.role(element: "button", place: "listRow", importance: .other)?.id, "button.inRow")
        XCTAssertEqual(s.role(element: "button", place: "contextMenu", importance: .destructive)?.id, "button.destructive")
        XCTAssertNil(s.role(element: "button", place: "toolbar", importance: .main), "an empty cell is a question, not a default")
        XCTAssertEqual(s.role("button.primary")?.perScreen, 1)

        let native = ComponentTemplates.native.system(name: "Acme")
        // In a sheet the default button is only its key: macOS draws it (NF1).
        XCTAssertEqual(native.role(element: "button", place: "sheetFooter", importance: .main)?.recipe, ["key": "defaultAction"])
        XCTAssertTrue(native.role(element: "button", place: "sheetFooter", importance: .main)!.followsMacOS)
        XCTAssertEqual(s.role(element: "button", place: "sheetFooter", importance: .main)?.id, "button.sheetDefault")
    }

    func testMatrixListsPlacesAndImportances() {
        let s = ComponentTemplates.glass.system(name: "Hatch")
        let m = s.matrix(element: "button")
        XCTAssertEqual(m.importances, [.main, .other, .quiet, .destructive])
        XCTAssertEqual(m.places.first?.id, "toolbar", "standard places come first, in their order")
        XCTAssertTrue(m.places.contains { $0.id == "actionRow" })
        let row = m.places.firstIndex { $0.id == "listRow" }!
        XCTAssertEqual(m.cells[row].map { $0?.id }, [nil, "button.inRow", nil, nil])
    }

    func testCodeNames() {
        let s = ComponentTemplates.glass.system(name: "Hatch")
        XCTAssertEqual(s.role("button.inRow")?.codeName, ".buttonRole(.inRow)")
        XCTAssertEqual(s.role("emptyState.standard")?.codeName, "ContentUnavailableView")
        XCTAssertEqual(s.role("button.inRow")?.element, "button")
        XCTAssertEqual(s.role("button.inRow")?.name, "inRow")
    }

    func testRoundTripIsStableAndDeterministic() throws {
        let s = ComponentTemplates.glass.system(name: "Hatch")
        let data = try s.encoded()
        XCTAssertEqual(try JSONDecoder().decode(ComponentSystem.self, from: data), s)
        XCTAssertEqual(try s.encoded(), data, "the same system always writes the same bytes")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).hasSuffix("}\n"))
    }

    func testDecodingIsForgiving() throws {
        let json = #"{"name":"Tiny","roles":[{"id":"button.primary","use":"The main action","places":["sheetFooter"],"importance":"main","recipe":{"style":"borderedProminent"}}]}"#
        let s = try JSONDecoder().decode(ComponentSystem.self, from: Data(json.utf8))
        XCTAssertEqual(s.version, 1)
        XCTAssertEqual(s.format, ComponentSystem.currentFormat)
        XCTAssertEqual(s.roles.first?.status, .provisional)
        XCTAssertEqual(s.problems(), [])
    }

    func testLoadFromNotebook() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(try ComponentSystem.load(notebook: dir.path))
        let file = dir.appendingPathComponent(ComponentSystem.notebookPath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let s = ComponentTemplates.native.system(name: "Acme")
        try s.encoded().write(to: file)
        XCTAssertEqual(try ComponentSystem.load(notebook: dir.path), s)
    }

    func testProblemsAreFound() {
        var s = ComponentTemplates.glass.system(name: "Hatch")
        s.roles.append(ComponentRole("button.extra", "Extra", use: "Clashes", places: ["listRow"], importance: .other, recipe: ["style": "glass"]))
        s.roles.append(ComponentRole("slider.volume", "Volume", use: "x", places: ["form"], importance: .other, recipe: ["style": "x"]))
        s.roles.append(ComponentRole("button.odd", "Odd", use: "x", places: ["nowhere"], importance: .quiet,
                                     recipe: ["style": "huge", "colour": "red", "tint": "color.brand"]))
        s.roles.append(ComponentRole("card.empty", "Empty", use: "x", places: ["page"], importance: .quiet))
        s.roles.append(ComponentRole("button.primary", "Again", use: "x", places: ["popover"], importance: .main, recipe: ["style": "glass"]))
        s.foundations.append(ComponentFoundation("brand", .color, use: "x", light: "#12"))
        s.places.append(ComponentPlace("toolbar", "Toolbar", "Again"))
        let p = s.problems()
        func has(_ text: String) -> Bool { p.contains { $0.contains(text) } }
        XCTAssertTrue(has("Roles button.inRow and button.extra both claim button in listRow"), p.joined(separator: "\n"))
        XCTAssertTrue(has("no element called slider"))
        XCTAssertTrue(has("no place called nowhere"))
        XCTAssertTrue(has("huge is not a value of style"))
        XCTAssertTrue(has("has no setting colour"))
        XCTAssertTrue(has("tint uses color.brand, which is not a foundation"))
        XCTAssertTrue(has("card.empty has neither a recipe nor a custom view"))
        XCTAssertTrue(has("Role button.primary is listed twice"))
        XCTAssertTrue(has("Foundation brand should be named color.something"))
        XCTAssertTrue(has("#12 is not #RRGGBB"))
        XCTAssertTrue(has("Place toolbar is already a standard place"))
    }

    func testFoundationReferencesMustMatchTheirKind() {
        var s = ComponentTemplates.native.system(name: "Acme")
        let i = s.roles.firstIndex { $0.id == "card.group" }!
        s.roles[i].recipe["radius"] = "space.group"
        XCTAssertTrue(s.problems().contains { $0.contains("space.group is not a value of radius") })
    }

    func testReadmeTellsAgentsTheRules() {
        let s = ComponentTemplates.glass.system(name: "Hatch")
        let md = s.readme()
        XCTAssertTrue(md.contains("Baseline v1, started from the Glass template."))
        XCTAssertTrue(md.contains("never invent a look"))
        XCTAssertTrue(md.contains("## Buttons"))
        XCTAssertTrue(md.contains("| `button.inRow` Row action |"))
        XCTAssertTrue(md.contains("`.buttonRole(.inRow)`"))
        XCTAssertTrue(md.contains("`button.primary.stop`"))
        XCTAssertTrue(md.contains("Which role where:"))
        XCTAssertTrue(md.contains("not decided"))
        XCTAssertTrue(md.contains("| `space.group` | 16 pt |"))
        XCTAssertTrue(md.contains("**Action row** (`actionRow`)"))
    }
}
