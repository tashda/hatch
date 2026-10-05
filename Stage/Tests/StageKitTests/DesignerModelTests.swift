import XCTest
import HatchCore
@testable import StageKit

@MainActor
final class DesignerModelTests: XCTestCase {
    private func model() throws -> DesignerModel {
        var system = ComponentTemplates.glass.system(name: "Acme")
        // One open look question, as Hatch writes it for an app with two looks in a role.
        let role = system.role("button.inRow")!
        system.questions.append(ComponentQuestion(
            id: "look.button.inRow", kind: .look, role: role.id, title: "How should row action buttons look?",
            options: [.init(title: "Bordered", recipe: ["style": "bordered", "size": "small"], count: 3, effect: ""),
                      .init(title: "Plain", recipe: ["style": "plain"], count: 1, effect: ""),
                      .init(title: "Follow macOS", follow: true, effect: ""),
                      .init(title: "Not sure yet", effect: "")],
            recommended: 0, reason: "Most used."))
        return try DesignerModel(source: LocalComponentsSource(system: system))
    }

    /// CD13: a look is tried everywhere without saving; Keep saves it once; Esc drops it.
    func testPreviewIsNotSavedUntilKeep() throws {
        let m = try model()
        let row = m.system.role("button.inRow")!
        m.tryLook(DesignerPreview(role: row.id, recipe: ["style": "glass"], label: "Glass"))
        XCTAssertEqual(m.look(of: row)["style"], "glass", "drawn with the preview")
        XCTAssertEqual(m.system.role(row.id)?.recipe, row.recipe, "nothing saved yet")
        m.discard()
        XCTAssertEqual(m.look(of: row), row.recipe)
        XCTAssertTrue(m.undoStack.isEmpty)

        m.tryLook(DesignerPreview(role: row.id, recipe: ["style": "plain", "size": "regular"], label: "Plain"))
        m.keep()
        XCTAssertNil(m.preview)
        XCTAssertEqual(m.system.role(row.id)?.recipe, ["style": "plain"], "saved once, without what macOS does anyway (CD35)")
        XCTAssertEqual(m.undoStack.count, 1)
    }

    /// CD27: choosing an option of the open question and keeping it answers the question.
    func testKeepingAnOptionAnswersTheQuestion() throws {
        let m = try model()
        let row = m.system.role("button.inRow")!
        let q = try XCTUnwrap(m.question(for: row))
        m.tryLook(RoleInspectorPreview.make(row, q, 1))
        XCTAssertEqual(m.look(of: row)["style"], "plain")
        m.keep()
        XCTAssertNil(m.question(for: row), "answered")
        XCTAssertEqual(m.system.role(row.id)?.recipe["style"], "plain")
        XCTAssertEqual(m.system.role(row.id)?.status, .agreed)
    }

    /// CD23: ⌘Z puts the system back as it was before the last kept change, question included.
    func testUndoRestoresTheSystem() throws {
        let m = try model()
        let before = m.system
        let row = m.system.role("button.inRow")!
        m.tryLook(RoleInspectorPreview.make(row, m.question(for: row)!, 2))
        m.keep()
        XCTAssertTrue(m.system.role(row.id)!.followsMacOS)
        m.undo()
        XCTAssertEqual(m.system, before)
        XCTAssertTrue(m.undoStack.isEmpty)
    }

    /// CD19: a Fine-tune value is tried, and macOS's default removes the setting.
    func testFineTuneTriesAValue() throws {
        let m = try model()
        m.open("button.inRow")
        let size = ComponentElement.named("button")!.parameter("size")!
        m.tryValue(size, "large")
        XCTAssertEqual(m.preview?.recipe["size"], "large")
        m.tryValue(size, nil)
        XCTAssertNil(m.preview?.recipe["size"])
        XCTAssertEqual(m.preview?.label, "Size: macOS default")
    }

    /// CD8 and CD27: ⌘] walks the questions; opening a role closes another role's preview.
    func testQueueAndLevels() throws {
        let m = try model()
        m.tryLook(DesignerPreview(role: "button.primary", recipe: [:], label: "x"))
        m.nextQuestion()
        XCTAssertEqual(m.selectedRole, "button.inRow")
        XCTAssertTrue(m.focused)
        XCTAssertNil(m.preview, "the other role's preview is closed")
        m.back()
        XCTAssertFalse(m.focused)
    }

    /// CD18: the picks name where each look comes from and merge duplicates.
    func testPicksNameTheirSource() throws {
        let m = try model()
        let picks = m.picks(for: m.system.role("button.primary")!)
        XCTAssertEqual(picks.first?.label.hasPrefix("Current"), true)
        XCTAssertTrue(picks.contains { $0.label.contains("Glass") }, "the template it is from is named")
        XCTAssertTrue(picks.contains { $0.label.contains("macOS Native") || $0.label.contains("macOS default") })
        XCTAssertLessThanOrEqual(picks.count, 5)
    }

    /// CD4 and CD24: a template for all buttons is previewed on every role, then kept as one change with one undo.
    func testTemplateForAnElementIsOneChange() throws {
        let m = try model()
        let before = m.system
        let b = m.batchTemplate(ComponentTemplates.native, element: "button", place: nil)
        XCTAssertFalse(b.items.isEmpty)
        m.tryBatch(b)
        XCTAssertEqual(m.previews.count, b.items.count, "every role it changes is drawn with its new look")
        XCTAssertEqual(m.system, before, "nothing saved yet")
        m.keep()
        XCTAssertNil(m.batch)
        XCTAssertTrue(m.previews.isEmpty)
        XCTAssertEqual(m.undoStack.count, 1, "one change")
        XCTAssertTrue(m.system.role("button.secondary")!.followsMacOS, "Native lets macOS draw other actions")
        m.undo()
        XCTAssertEqual(m.system, before)
    }

    /// CD26: only here makes a variant for the place, with the reason; the role keeps its look elsewhere.
    func testOnlyHereMakesAVariant() throws {
        let m = try model()
        let row = m.system.role("button.inRow")!
        let param = ComponentElement.named("button")!.parameter("style")!
        var b = m.batchSetting(param, "plain", element: "button", place: "card")
        let i = try XCTUnwrap(b.items.firstIndex { $0.role == row.id })
        XCTAssertFalse(b.items[i].otherPlaces.isEmpty, "says where else it sits")
        b.items[i].onlyHere = true
        b.reason = "Cards are dense."
        m.tryBatch(b)
        m.keep()
        let kept = m.system.role(row.id)!
        XCTAssertEqual(kept.recipe, row.recipe, "unchanged elsewhere")
        XCTAssertEqual(kept.variants.first?.id, "card")
        XCTAssertEqual(kept.variants.first?.use, "Cards are dense.")
        XCTAssertEqual(kept.variants.first?.recipe["style"], "plain")
    }

    /// CD24: following macOS for everything in a place, as a batch.
    func testFollowAPlace() throws {
        let m = try model()
        let b = m.batchFollow(element: nil, place: "floating")
        XCTAssertTrue(b.items.allSatisfy(\.follow))
        m.tryBatch(b)
        m.keep()
        XCTAssertTrue(m.system.roles.filter { $0.places == ["floating"] }.allSatisfy(\.followsMacOS))
    }
}
