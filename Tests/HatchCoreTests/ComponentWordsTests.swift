import XCTest
@testable import HatchCore

/// Looks in plain words, and design system questions that read as questions (Decide shows them to the owner).
final class ComponentWordsTests: XCTestCase {
    func testButtonsReadAsThePersonSeesThem() {
        XCTAssertEqual(ComponentWords.look(element: "button", recipe: ["label": "titleOnly"]), "Standard button, text only")
        XCTAssertEqual(ComponentWords.look(element: "button", recipe: ["style": "plain", "label": "iconOnly"]), "Icon, no border")
        XCTAssertEqual(ComponentWords.look(element: "button", recipe: ["style": "plain", "label": "titleOnly"]), "Text, no border")
        XCTAssertEqual(ComponentWords.look(element: "button", recipe: ["style": "borderedProminent", "size": "large"]), "Filled button, large")
        XCTAssertEqual(ComponentWords.look(element: "button", recipe: ["style": "bordered", "tint": "critical"]), "Bordered button, red")
        XCTAssertEqual(ComponentWords.look(element: "toggle", recipe: [:]), "Standard toggle (a checkbox)")
        XCTAssertEqual(ComponentWords.look(element: "picker", recipe: ["style": "segmented"]), "Segmented control")
    }

    func testAQuestionAsksHowARoleShouldLook() {
        let system = ComponentTemplates.glass.system(name: "Acme")
        XCTAssertEqual(ComponentWords.lookQuestion(system.role("button.secondary")!), "How should other action buttons look?")
        XCTAssertEqual(ComponentWords.lookQuestion(system.role("button.sheetDefault")!), "How should default buttons look?")
    }

    /// Found in use: a Decide answer the system refused closed its ticket anyway; the question, still open, comes back.
    func testAQuestionWhoseTicketClosedComesBack() throws {
        let store = try HatchStore.inMemory()
        let p = try store.upsertProject(key: "acme", name: "Acme")
        var system = ComponentTemplates.glass.system(name: "Acme")
        system.questions = [ComponentQuestion(id: "look.button.secondary", kind: .look, role: "button.secondary", title: "?",
                                              options: [.init(title: "Plain", recipe: ["style": "plain"], count: 3, effect: "")], reason: "Most used.")]
        XCTAssertEqual(try store.syncComponentQuestions(projectId: p.id, system: system).added, 1)
        let first = try XCTUnwrap(try store.tickets(TicketFilter()).first)
        try store.move(first.id, to: .dropped, actor: .owner, reason: "closed without the answer saved")
        XCTAssertEqual(try store.syncComponentQuestions(projectId: p.id, system: system).added, 1, "asked again")
        XCTAssertEqual(try store.syncComponentQuestions(projectId: p.id, system: system).added, 0)
    }

    func testWaitingQuestionsTakeTheNewWording() throws {
        let store = try HatchStore.inMemory()
        let p = try store.upsertProject(key: "acme", name: "Acme")
        var system = ComponentTemplates.glass.system(name: "Acme")
        system.questions = [ComponentQuestion(id: "look.button.secondary", kind: .look, role: "button.secondary", title: "Other action: 3 looks in use",
                                              options: [.init(title: "label titleOnly", recipe: ["label": "titleOnly"], count: 3, effect: ""),
                                                        .init(title: "Not sure yet", effect: "Later.")], reason: "Most used.")]
        // A ticket written by an older Hatch, with the old words.
        let old = try store.createTicket(projectId: p.id, type: .question, title: "Other action: 3 looks in use",
                                         body: ComponentsSetup.questionMarker("look.button.secondary"), area: ComponentsSetup.area)
        try store.setQuestionOptions(ticketId: old.id, [QuestionOption(key: "0", title: "label titleOnly")])
        let changed = try store.syncComponentQuestions(projectId: p.id, system: system)
        XCTAssertEqual(changed.updated, 1)
        XCTAssertEqual(try store.ticket(id: old.id)?.title, "How should other action buttons look?")
        XCTAssertEqual(try store.questionOptions(ticketId: old.id).first?.title, "Standard button, text only")
        XCTAssertEqual(try store.syncComponentQuestions(projectId: p.id, system: system).updated, 0, "a second sync changes nothing")
    }

    /// CD20: every value has a plain name; code values stay out of sight.
    func testEveryValueHasAPlainName() {
        XCTAssertEqual(ComponentWords.value(element: "button", parameter: "style", value: "borderedProminent"), "Filled")
        XCTAssertEqual(ComponentWords.value(element: "picker", parameter: "style", value: "automatic"), "macOS default (pop-up)")
        XCTAssertEqual(ComponentWords.value(element: "toggle", parameter: "size", value: "extraLarge"), "Extra large")
        for e in ComponentElement.catalog {
            for p in e.parameters {
                for v in p.values {
                    let name = ComponentWords.value(element: e.id, parameter: p.id, value: v)
                    XCTAssertNotEqual(name, v == name && v.first?.isLowercase == true ? v : "", "\(e.id).\(p.id) \(v) has no plain name")
                }
            }
        }
        XCTAssertNotNil(ComponentWords.help(element: "button", parameter: "key"))
    }

    /// CD21: a setting that needs another one is only shown with it.
    func testSettingsThatNeedAnother() {
        let card = ComponentElement.named("card")!
        XCTAssertFalse(card.parameter("shadow")!.applies(to: ["container": "groupBox"]))
        XCTAssertTrue(card.parameter("shadow")!.applies(to: ["container": "custom"]))
        XCTAssertFalse(ComponentElement.named("badge")!.parameter("tint")!.applies(to: [:]), "tint only colours a capsule")
        XCTAssertTrue(ComponentElement.named("button")!.parameter("tint")!.applies(to: [:]))
    }
}
