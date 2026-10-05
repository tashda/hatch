import XCTest
@testable import HatchAgent
@testable import HatchCore

/// Changing a component (decision CP3): the Proposal, the looks an agent offers, the owner's choice, and the build.
final class ComponentChangeTests: XCTestCase {
    var store: HatchStore!
    var project: Project!
    var system: ComponentSystem!

    override func setUpWithError() throws {
        (store, project) = try Fixture.store()
        system = ComponentTemplates.glass.system(name: "Echo")
        try system.agree("button.primary")
    }

    private func looks(_ recipes: [[String: String]], recommended: String? = "a") -> ComponentChangeOffer {
        ComponentChangeOffer(summary: "Two looks for the main action.",
                             looks: recipes.enumerated().map { i, r in
                                 .init(id: ["a", "b", "c", "d", "e"][i], title: "Look \(i)", recipe: r, gain: "Clearer.", cost: "Louder.")
                             },
                             recommended: recommended, why: "It reads as the main action without shouting.")
    }

    /// A filed change, taken by an agent to prepare it.
    private func filed(place: String? = nil) throws -> Ticket {
        let role = try XCTUnwrap(system.role("button.primary"))
        let t = try store.fileComponentChange(projectId: project.id, ComponentsSetup.changeDraft(role: role, what: "Make it calmer.", place: place, system: system))
        try store.take(t.id, agent: "Agent on \(t.displayNumber)")
        return try XCTUnwrap(store.ticket(id: t.id))
    }

    func testTheProposalCarriesTheRoleTheScopeAndTheSettings() throws {
        let role = try XCTUnwrap(system.role("button.primary"))
        let d = ComponentsSetup.changeDraft(role: role, what: "Make it calmer.", place: "sheetFooter", system: system)
        XCTAssertEqual(d.type, .proposal)
        XCTAssertEqual(d.area, ComponentsSetup.area)
        XCTAssertEqual(ComponentsSetup.changedRole(inBody: d.body), "button.primary")
        XCTAssertEqual(ComponentsSetup.changeScope(inBody: d.body).place, "sheetFooter")
        XCTAssertNil(ComponentsSetup.changeScope(inBody: d.body).area)
        XCTAssertTrue(d.body.contains("`style`: automatic, bordered"), "the settings an agent may use are in the ticket")
        XCTAssertTrue(d.body.contains("hatch offer <ticket> --components looks.json"))
    }

    func testFilingSkipsIrisAndIsReadyForAnAgent() throws {
        let role = try XCTUnwrap(system.role("button.primary"))
        let t = try store.fileComponentChange(projectId: project.id, ComponentsSetup.changeDraft(role: role, what: "Calmer.", system: system))
        XCTAssertEqual(t.status, .ready)
    }

    func testTheGateChecksEveryRecipe() {
        let ok = looks([["style": "bordered"], ["style": "glass", "size": "large"]])
        XCTAssertEqual(ok.problems(role: "button.primary", system: system).map(\.code), [])

        func codes(_ o: ComponentChangeOffer) -> Set<String> { Set(o.problems(role: "button.primary", system: system).map(\.code)) }
        XCTAssertTrue(codes(looks([["style": "bordered"]])).contains("looks.count"))
        XCTAssertTrue(codes(looks([["style": "bordered"], ["style": "shiny"]])).contains("look.value"))
        XCTAssertTrue(codes(looks([["style": "bordered"], ["glow": "yes"]])).contains("look.setting"))
        XCTAssertTrue(codes(looks([["style": "bordered"], ["style": "glass"]], recommended: nil)).contains("recommend.missing"))
        let today = system.role("button.primary")!.recipe
        XCTAssertTrue(codes(looks([today, ["style": "bordered"]])).contains("look.today"))
        XCTAssertEqual(ComponentChangeOffer(looks: [], recommended: nil).problems(role: "button.nope", system: system).map(\.code), ["change.role"])
    }

    func testAnOfferGoesToTheOwnerWithItsLooksAsOptions() throws {
        let t = try filed()
        let result = try OfferService(store: store).offer(ticketId: t.id, change: looks([["style": "bordered"], ["style": "glass"]]), system: system)
        XCTAssertTrue(result.isOffered)
        XCTAssertEqual(try store.ticket(id: t.id)?.status, .yourCall)
        let options = try store.questionOptions(ticketId: t.id)
        XCTAssertEqual(options.map(\.title), ["Look 0", "Look 1", "Keep today's look"])
        XCTAssertEqual(options.filter(\.recommended).map(\.key), ["0"])
        // Decide asks it as a pick, not a sitting in the Stage.
        XCTAssertEqual(try store.pendingDecisions(projectId: project.id).first { $0.ticket.id == t.id }?.kind, .pick)
    }

    func testABadOfferIsRejectedAndStaysWithTheAgent() throws {
        let t = try filed()
        let result = try OfferService(store: store).offer(ticketId: t.id, change: looks([["style": "shiny"], ["style": "glass"]]), system: system)
        XCTAssertFalse(result.isOffered)
        XCTAssertEqual(try store.ticket(id: t.id)?.status, .preparing)
    }

    func testChoosingALookMakesTheDraftAndAcceptsTheProposal() throws {
        let t = try filed()
        let change = looks([["style": "bordered"], ["style": "glass"]])
        _ = try OfferService(store: store).offer(ticketId: t.id, change: change, system: system)
        system.addChange(change.question(role: system.role("button.primary")!, ticketId: t.id, ticketTitle: t.title, place: nil, area: nil))
        XCTAssertNotNil(system.changeQuestion(ticketId: t.id))
        // The Designer's question and Decide's option share the index.
        XCTAssertTrue(try system.applyDecided(ticketBody: t.body, choice: "1", decision: t.displayNumber, ticketId: t.id))
        let moved = try store.decideComponentChange(ticketId: t.id, choice: "1", reason: nil)
        XCTAssertEqual(moved.status, .accepted)
        let role = try XCTUnwrap(system.role("button.primary"))
        XCTAssertEqual(role.draft, ["style": "glass"])
        XCTAssertEqual(role.status, .inRedesign)
        XCTAssertNil(system.changeQuestion(ticketId: t.id))
        // A change never becomes a Question ticket of its own.
        XCTAssertEqual(try store.syncComponentQuestions(projectId: project.id, system: system).added, 0)

        // Building it applies the draft: the next baseline version.
        let version = system.version
        XCTAssertTrue(try system.applyChange(ticketBody: t.body, decision: t.displayNumber))
        XCTAssertEqual(system.version, version + 1)
        XCTAssertEqual(system.role("button.primary")?.recipe, ["style": "glass"])
    }

    func testKeepingTodaysLookDropsTheProposal() throws {
        let t = try filed()
        let change = looks([["style": "bordered"], ["style": "glass"]])
        _ = try OfferService(store: store).offer(ticketId: t.id, change: change, system: system)
        let before = system.role("button.primary")
        system.addChange(change.question(role: before!, ticketId: t.id, ticketTitle: t.title, place: nil, area: nil))
        XCTAssertTrue(try system.applyDecided(ticketBody: t.body, choice: "2", decision: nil, ticketId: t.id))
        XCTAssertEqual(try store.decideComponentChange(ticketId: t.id, choice: "2", reason: nil).status, .dropped)
        XCTAssertEqual(system.role("button.primary"), before)
    }

    func testAChangeInOnePlaceBecomesAVariantThere() throws {
        let t = try filed(place: "sheetFooter")
        let change = looks([["style": "bordered"], ["style": "glass"]])
        system.addChange(change.question(role: system.role("button.primary")!, ticketId: t.id, ticketTitle: t.title, place: "sheetFooter", area: nil))
        try system.answer(ComponentsSetup.changeQuestionId(ticketId: t.id), option: 0)
        let role = try XCTUnwrap(system.role("button.primary"))
        XCTAssertNil(role.draft)
        let variant = role.variants.first { $0.id == "sheetFooter" }
        XCTAssertEqual(variant?.places, ["sheetFooter"])
        XCTAssertEqual(variant?.recipe["style"], "bordered")
    }

    func testTheBriefAsksForLooksNotARound() throws {
        let t = try filed()
        let rules = BriefBuilder.rules(kind: .prepare, ticket: t, config: Fixture.config).joined(separator: "\n")
        XCTAssertTrue(rules.contains("--components looks.json"))
        XCTAssertFalse(rules.contains("specimens/"))
        XCTAssertTrue(BriefBuilder.nextCommands(kind: .prepare, ticket: t).joined().contains("--components looks.json"))
        let build = BriefBuilder.rules(kind: .build, ticket: t, config: Fixture.config).joined(separator: "\n")
        XCTAssertTrue(build.contains("hatch components generate --out"))
    }

    // The two calls a Sweep uses (SW6): check a design for a role, save an accepted one.

    func testADesignForARoleIsCheckedLikeAnOffer() {
        XCTAssertEqual(system.problems(look: ["style": "bordered"], forRole: "button.primary"), [])
        XCTAssertEqual(system.problems(look: ["style": "shiny"], forRole: "button.primary").map(\.code), ["look.value"])
        XCTAssertEqual(system.problems(look: ["glow": "yes"], forRole: "button.primary").map(\.code), ["look.setting"])
        XCTAssertEqual(system.problems(look: [:], forRole: "button.primary").map(\.code), ["look.empty"])
        XCTAssertEqual(system.problems(look: ["style": "bordered"], forRole: "button.nope").map(\.code), ["change.role"])
        // A named value of the right kind counts as a value.
        let color = system.foundations.first { $0.kind == .color }!.id
        XCTAssertEqual(system.problems(look: ["tint": color], forRole: "button.primary"), [])
    }

    func testAnAcceptedDesignBecomesTheDraftOrAVariant() throws {
        try system.acceptDesign(role: "button.primary", look: ["style": "bordered"], use: "Calmer", decision: "#200")
        XCTAssertEqual(system.role("button.primary")?.draft, ["style": "bordered"])
        XCTAssertEqual(system.role("button.primary")?.status, .inRedesign)
        XCTAssertEqual(system.role("button.primary")?.decision, "#200")

        try system.acceptDesign(role: "button.primary", look: ["style": "glass"], area: "Inspector", use: "Cards in the inspector", decision: nil)
        XCTAssertEqual(system.role("button.primary")?.variants.first { $0.id == "area-inspector" }?.recipe["style"], "glass")

        XCTAssertThrowsError(try system.acceptDesign(role: "button.primary", look: ["style": "shiny"], use: "", decision: nil))
    }
}
