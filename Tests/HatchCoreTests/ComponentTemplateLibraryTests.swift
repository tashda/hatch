import XCTest
@testable import HatchCore

final class ComponentTemplateLibraryTests: XCTestCase {
    private var folder: URL!
    override func setUp() { folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    /// CD46: with nothing marked, new projects start from macOS Native; the marked template wins.
    func testRecommendedIsTheMarkedOneElseNative() throws {
        let lib = ComponentTemplateLibrary(folder: folder)
        XCTAssertEqual(lib.recommended.id, "native")
        try lib.setDefault("compact")
        XCTAssertEqual(lib.recommended.id, "compact")
        XCTAssertThrowsError(try lib.setDefault("nope"))
    }

    /// CD47: a project's system saved as a template starts a new app with its looks, all provisional, no questions;
    /// saving again under the same name is the next version.
    func testSaveAndStartFromAnOwnTemplate() throws {
        let lib = ComponentTemplateLibrary(folder: folder)
        var hatch = ComponentTemplates.glass.system(name: "Hatch")
        try hatch.agree()
        hatch.questions = [ComponentQuestion(id: "q", kind: .look, role: "button.inRow", title: "?", options: [], reason: "")]
        let saved = try lib.save(hatch, title: "Hatch's Look", summary: "Glass, Hatch's way.", from: "Hatch")
        XCTAssertEqual(saved.id, "hatch-s-look")
        XCTAssertEqual(saved.version, 1)
        XCTAssertEqual(try lib.save(hatch, title: "Hatch's Look", summary: "", from: "Hatch").version, 2)
        XCTAssertEqual(lib.saved().count, 1)

        let t = try XCTUnwrap(lib.named("hatch-s-look"))
        XCTAssertFalse(t.isShipped)
        let echo = t.system(name: "Echo")
        XCTAssertEqual(echo.name, "Echo")
        XCTAssertEqual(echo.template, "hatch-s-look")
        XCTAssertTrue(echo.questions.isEmpty)
        XCTAssertTrue(echo.roles.allSatisfy { $0.status == .provisional })
        XCTAssertEqual(echo.problems(), [])

        try lib.setDefault(t.id)
        XCTAssertEqual(lib.recommended.id, t.id)
        try lib.remove(t.id)
        XCTAssertEqual(lib.recommended.id, "native", "removing the marked one falls back to Native")
        XCTAssertThrowsError(try lib.save(hatch, title: "Glass", summary: "", from: nil), "a shipped template's name")
    }

    /// CD47: comparing lines two systems up cell by cell and counts what is drawn differently.
    func testComparison() {
        let native = ComponentTemplates.native.system(name: "A"), glass = ComponentTemplates.glass.system(name: "A")
        let c = ComponentComparison(native, glass)
        XCTAssertGreaterThan(c.differences, 0)
        XCTAssertEqual(ComponentComparison(native, native).differences, 0)
        let bar = c.rows.first { $0.place == "bottomBar" && $0.element == "button" && $0.importance == .main }
        XCTAssertEqual(bar?.differs, true, "Native lets macOS draw it, Glass fills it with glass")
        XCTAssertEqual(c.rows.first?.place, "toolbar", "in the catalog's order of places")
    }
}
