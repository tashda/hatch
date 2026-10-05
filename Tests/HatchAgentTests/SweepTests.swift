import XCTest
@testable import HatchAgent
@testable import HatchCore

final class SweepTests: XCTestCase {
    var store: HatchStore!
    var project: Project!

    override func setUpWithError() throws { (store, project) = try Fixture.store() }

    func items() -> [ManifestItem] {
        [ManifestItem(id: "decide-card", title: "Decide card", name: "DecideCard", file: "Views/DecideCard.swift", kind: "with actions"),
         ManifestItem(id: "agent-card", title: "Agent card", name: "AgentCard", file: "Views/AgentCard.swift", kind: "read only")]
    }

    /// A Proposal manifest for a Sweep. With `matrix`, a control names the items' kinds, as the gate wants for two or more.
    func sweepManifest(_ items: [ManifestItem], matrix: Bool = true) -> ProposalManifest {
        var m = Fixture.manifest(); m.items = items
        let kinds = Array(Set(items.compactMap(\.kind))).sorted()
        if matrix, kinds.count > 1 {
            m.controls.append(ManifestControl(id: "kind", title: "Kind", choices: kinds.map { ManifestChoice(id: ProposalValidator.slug($0), name: $0) }, defaultChoice: ProposalValidator.slug(kinds[0])))
            m.matrixControl = "kind"
        }
        return m
    }

    func testASweepGoesTheWayOfAProposal() {
        XCTAssertEqual(Workflow.path(for: .sweep), Workflow.path(for: .proposal))
        for (from, to, actor) in [(Status.ready, Status.preparing, Actor.agent), (.preparing, .yourCall, .agent), (.yourCall, .accepted, .owner),
                                  (.accepted, .building, .hatch), (.building, .toVerify, .hatch), (.toVerify, .merged, .hatch)] {
            XCTAssertTrue(Workflow.isAllowed(type: .sweep, from: from, to: to, actor: actor), "\(from) to \(to)")
        }
        XCTAssertEqual(TicketType.sweep.displayName, "Sweep")
        XCTAssertEqual(TicketType.theme.displayName, "Goal", "what groups Sweeps and tickets is a Goal")
    }

    func testItemsKeepTheirStateWhenTheSurveyIsHandedInAgain() throws {
        let t = try Fixture.ticket(store, project, type: .sweep, title: "All cards", body: "x")
        try store.saveSweepItems(ticketId: t.id, items: items().map(\.input))
        try store.setSweepItem(ticketId: t.id, key: "decide-card", to: .built, commit: "abc123", by: "agent")
        try store.setSweepItem(ticketId: t.id, key: "agent-card", to: .dropped, by: "owner")
        let again = try store.saveSweepItems(ticketId: t.id, items: items().map(\.input) + [SweepItemInput(key: "footer-card", title: "Footer card", name: "FooterCard", file: "Views/FooterCard.swift")])
        XCTAssertEqual(again.map(\.key), ["decide-card", "agent-card", "footer-card"], "a new item goes last")
        XCTAssertEqual(again.map(\.state), [.built, .dropped, .todo], "progress and the owner's drops survive")
        XCTAssertEqual(again[0].commit, "abc123")
        let progress = try store.sweepProgress(ticketId: t.id)
        XCTAssertEqual(progress.total, 2, "a dropped item does not count")
        XCTAssertEqual(progress.settled, 1)
        XCTAssertThrowsError(try store.setSweepItem(ticketId: t.id, key: "nope", to: .built, by: "agent")) { XCTAssertTrue("\($0)".contains("decide-card")) }
    }

    func testTheGateWantsItemsOnlyForASweep() {
        XCTAssertTrue(codes(ProposalValidator.validate(sweepManifest([]), isSweep: true)).contains("items.too-few"))
        XCTAssertTrue(codes(ProposalValidator.validate(sweepManifest([items()[0]]), isSweep: true)).contains("items.too-few"))
        XCTAssertFalse(codes(ProposalValidator.validate(sweepManifest(items()), isSweep: true)).contains("items.too-few"))
        XCTAssertFalse(codes(ProposalValidator.validate(sweepManifest([]), isSweep: false)).contains("items.too-few"), "any other Proposal needs none")
        XCTAssertTrue(codes(ProposalValidator.validate(sweepManifest(items() + [items()[0]]), isSweep: true)).contains("items.duplicate-id"))
        var bad = items(); bad[1].file = ""
        XCTAssertTrue(codes(ProposalValidator.validate(sweepManifest(bad), isSweep: true)).contains("items.incomplete"))
        let earlier = sweepManifest(items())
        XCTAssertTrue(codes(ProposalValidator.validate(sweepManifest([items()[0], ManifestItem(id: "x", title: "X", name: "X", file: "X.swift")]), previous: earlier, isSweep: true)).contains("items.removed"))
    }

    func testAnItemMustNameARealFileThatHoldsTheName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Views"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "struct DecideCard: View {}".write(to: root.appendingPathComponent("Views/DecideCard.swift"), atomically: true, encoding: .utf8)
        try "struct SomethingElse: View {}".write(to: root.appendingPathComponent("Views/AgentCard.swift"), atomically: true, encoding: .utf8)
        let found = codes(SweepItemCheck.problems(items() + [
            ManifestItem(id: "ghost", title: "Ghost", name: "GhostCard", file: "Views/GhostCard.swift"),
            ManifestItem(id: "out", title: "Out", name: "Out", file: "../secret.swift"),
            ManifestItem(id: "abs", title: "Abs", name: "Abs", file: "/etc/hosts"),
        ], appRoot: root.path))
        XCTAssertEqual(found.filter { $0 == "items.name-not-in-file" }.count, 1, "AgentCard.swift exists but does not hold AgentCard")
        XCTAssertEqual(found.filter { $0 == "items.file-missing" }.count, 1, "an invented card")
        XCTAssertEqual(found.filter { $0 == "items.file-outside" }.count, 2)
        XCTAssertTrue(SweepItemCheck.problems([items()[0]], appRoot: root.path).isEmpty, "the real one passes")
        let partial = ManifestItem(id: "p", title: "P", name: "Decide", file: "Views/DecideCard.swift")
        XCTAssertFalse(SweepItemCheck.problems([partial], appRoot: root.path).isEmpty, "a name inside a longer name is not the name")
    }

    func testOfferingASweepSavesItsItemsAndChecksThemAgainstTheCode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Views"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "struct DecideCard {}".write(to: root.appendingPathComponent("Views/DecideCard.swift"), atomically: true, encoding: .utf8)
        var service = OfferService(store: store, agent: "Agent on #151")
        service.itemRoot = { _ in root.path }
        let t = try Fixture.preparing(store, project, type: .sweep)
        guard case .rejected(let issues) = try service.offer(ticketId: t.id, manifest: sweepManifest(items())) else { return XCTFail("AgentCard.swift does not exist") }
        XCTAssertTrue(codes(issues).contains("items.file-missing"))
        XCTAssertTrue(try store.sweepItems(ticketId: t.id).isEmpty, "nothing is saved from a rejected survey")
        try "struct AgentCard {}".write(to: root.appendingPathComponent("Views/AgentCard.swift"), atomically: true, encoding: .utf8)
        guard case .offered(let after, _, _) = try service.offer(ticketId: t.id, manifest: sweepManifest(items())) else { return XCTFail("should pass now") }
        XCTAssertEqual(after.status, .yourCall)
        XCTAssertEqual(try store.sweepItems(ticketId: t.id).map(\.key), ["decide-card", "agent-card"])
    }

    func testResetRemovesTheItems() throws {
        let t = try store.capture(prompt: "Change all the cards", projectId: project.id)
        try store.saveSweepItems(ticketId: t.id, items: items().map(\.input))
        try store.resetTicket(t.id)
        XCTAssertTrue(try store.sweepItems(ticketId: t.id).isEmpty)
    }

    func testCandidatesComeFromAFreeNameScan() {
        let views = ["DecideCard", "AgentCard", "FooterCard", "ComponentsView.StatusBadge", "SettingsView", "CardStyle", "PanelResizer"].map { ViewEntry(name: $0, kind: .view, file: "Views/\($0).swift") }
            + [ViewEntry(name: ".cardBackground()", kind: .modifier, file: "Views/Mods.swift")]
        let found = SweepCandidates.scan(text: "Change how all the cards in the Inspector look", views: views, pathPrefix: "App/Sources/")
        XCTAssertEqual(found.map(\.name), ["AgentCard", "CardStyle", "DecideCard", "FooterCard"], "views that share a word with the text, a modifier is not a candidate")
        XCTAssertEqual(found.first?.file, "App/Sources/Views/AgentCard.swift", "the path is relative to the app, which is what the check wants")
        XCTAssertTrue(SweepCandidates.scan(text: "make it look nice", views: views).isEmpty, "no distinctive word, no guess")
        XCTAssertEqual(SweepCandidates.tokens("DecideSessionView"), ["decide", "session", "view"])
    }

    func testTheBriefForASweepAsksForASurveyThenForItemsOneCommitEach() throws {
        let t = try Fixture.preparing(store, project, type: .sweep)
        let prepare = try BriefBuilder.brief(store: store, ticketId: t.id, agent: "Agent on #151", kind: .prepare)
        XCTAssertTrue(prepare.contains("This is a Sweep"))
        XCTAssertTrue(prepare.contains("Hatch checks both against the code"))
        XCTAssertTrue(prepare.contains("One unified design for all of them"))
        XCTAssertTrue(prepare.contains("`matrixControl`"), "the design is drawn for every kind")
        try store.saveSweepItems(ticketId: t.id, items: items().map(\.input))
        try store.setSweepItem(ticketId: t.id, key: "decide-card", to: .built, commit: "abc", by: "agent")
        let build = try BriefBuilder.brief(store: store, ticketId: t.id, agent: "Agent on #151", kind: .build)
        XCTAssertTrue(build.contains("- decide-card [Built] DecideCard in Views/DecideCard.swift · kind: with actions"))
        XCTAssertTrue(build.contains("- agent-card [To do] AgentCard in Views/AgentCard.swift"))
        XCTAssertTrue(build.contains("One commit per item"))
        XCTAssertTrue(build.contains("hatch item built"))
        let ordinary = try BriefBuilder.brief(store: store, ticketId: try Fixture.preparing(store, project).id, agent: "Agent on #151", kind: .prepare)
        XCTAssertFalse(ordinary.contains("This is a Sweep"))
    }

    func testTheOwnerLeavesItemsOutVerifiesThemAndSendsOneBack() throws {
        let t = try Fixture.ticket(store, project, type: .sweep, title: "All cards", body: "x", status: .ready)
        for (status, actor) in [(Status.preparing, Actor.agent), (.yourCall, .agent), (.accepted, .owner), (.building, .hatch), (.toVerify, .hatch)] {
            try store.move(t.id, to: status, actor: actor)
        }
        try store.saveSweepItems(ticketId: t.id, items: items().map(\.input))
        try store.setSweepItem(ticketId: t.id, key: "decide-card", to: .built, commit: "a1", by: "agent")
        try store.setSweepItem(ticketId: t.id, key: "agent-card", to: .built, commit: "b2", by: "agent")
        XCTAssertThrowsError(try store.dropSweepItem(ticketId: t.id, key: "decide-card"), "a built item is sent back, not left out")
        XCTAssertEqual(try store.verifySweepItem(ticketId: t.id, key: "decide-card").state, .verified)
        let moved = try store.sendBackSweepItem(ticketId: t.id, key: "agent-card", note: "The action row should sit under the text")
        XCTAssertEqual(moved.status, .fixing)
        let all = try store.sweepItems(ticketId: t.id)
        XCTAssertEqual(all.map(\.state), [.verified, .todo], "the other items stay as they were")
        let note = try XCTUnwrap(try store.notes(ticketId: t.id).last)
        XCTAssertEqual(note.kind, .instruction)
        XCTAssertTrue(note.body.contains("AgentCard") && note.body.contains("under the text"))
        XCTAssertThrowsError(try store.sendBackSweepItem(ticketId: t.id, key: "decide-card", note: " "))
        XCTAssertEqual(try store.dropSweepItem(ticketId: t.id, key: "agent-card").state, .dropped)
        XCTAssertEqual(try store.restoreSweepItem(ticketId: t.id, key: "agent-card").state, .todo)
        XCTAssertThrowsError(try store.restoreSweepItem(ticketId: t.id, key: "agent-card"), "it is not left out any more")
    }

    func testAnAnsweredQuestionBecomesASweepWithItsFindings() throws {
        let q = try store.capture(prompt: "Look at every place we show a count badge and tell me whether we do it consistently", projectId: project.id)
        try store.file(q.id, Filing(path: .question), by: "Iris")
        for (status, actor) in [(Status.ready, Actor.hatch), (.preparing, .agent)] { try store.move(q.id, to: status, actor: actor) }
        _ = try store.addNote(q.id, kind: .agent, author: "Agent on #1", body: "Three badges, three styles: toolbar, Dock, row.")
        try store.move(q.id, to: .yourCall, actor: .hatch)
        let sweep = try store.promoteToSweep(from: q.id)
        XCTAssertEqual(sweep.type, .sweep)
        XCTAssertEqual(sweep.path, .sweep)
        XCTAssertEqual(sweep.status, .ready, "the path is decided, so no second vetting")
        XCTAssertTrue(sweep.body.hasPrefix("Look at every place we show a count badge"), "the owner's words")
        XCTAssertTrue(try store.notes(ticketId: sweep.id).contains { $0.body.contains("Three badges, three styles") }, "the findings travel with it")
        XCTAssertEqual(try store.ticket(id: q.id)?.status, .done)
        XCTAssertTrue(try store.links(ticketId: sweep.id).contains { $0.link.kind == .related })
        XCTAssertThrowsError(try store.promoteToSweep(from: sweep.id), "only a Question can")
    }

    func testABigItemIsSplitOffIntoItsOwnTicket() throws {
        let t = try Fixture.ticket(store, project, type: .sweep, title: "All cards", body: "x", status: .ready)
        try store.saveSweepItems(ticketId: t.id, items: items().map(\.input))
        try store.setSweepItem(ticketId: t.id, key: "agent-card", to: .built, commit: "b", by: "agent")
        XCTAssertThrowsError(try store.splitOffSweepItem(ticketId: t.id, key: "agent-card"), "a built item cannot be split off")
        let own = try store.splitOffSweepItem(ticketId: t.id, key: "decide-card")
        XCTAssertEqual(own.type, .tweak)
        XCTAssertEqual(own.status, .ready)
        XCTAssertTrue(own.title.hasPrefix("DecideCard"))
        XCTAssertEqual(try store.sweepItems(ticketId: t.id).first?.state, .dropped, "the Sweep leaves it out")
        XCTAssertTrue(try store.notes(ticketId: t.id).contains { $0.body.contains("split off to") })
    }

    func testASweepWithSeveralKindsMustDrawTheDesignForEachOfThem() {
        func codesFor(_ m: ProposalManifest) -> [String] { codes(ProposalValidator.validate(m, isSweep: true)) }
        var m = sweepManifest(items(), matrix: false)   // kinds: "with actions", "read only"
        XCTAssertTrue(codesFor(m).contains("matrix.missing"), "two kinds and no control that names them")
        m.matrixControl = "nope"
        XCTAssertTrue(codesFor(m).contains("matrix.control-unknown"))
        m.controls.append(ManifestControl(id: "kind", title: "Kind", choices: [ManifestChoice(id: "with-actions", name: "With actions")], defaultChoice: "with-actions"))
        m.matrixControl = "kind"
        XCTAssertTrue(codesFor(m).contains("matrix.kind-not-drawn"), "Read only has no choice, so nothing draws it")
        m.controls[m.controls.count - 1].choices.append(ManifestChoice(id: "readonly", name: "Read only"))
        XCTAssertFalse(codesFor(m).contains { $0.hasPrefix("matrix.") }, "every kind is a choice (by id or name, ignoring case and spaces)")
        var one = items(); one[1].kind = "With Actions"
        XCTAssertFalse(codesFor(sweepManifest(one)).contains { $0.hasPrefix("matrix.") }, "one kind needs no matrix")
        let json = try? sweepManifest(items()).jsonString()
        XCTAssertNotNil(json)
    }

    func testHatchCanPrepareASweepThatArrivesWaitingForTheOwnersCall() throws {
        let goal = try Fixture.ticket(store, project, type: .theme, title: "Components for the app", body: "x", status: .draft)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Views"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "struct DecideCard {}".write(to: root.appendingPathComponent("Views/DecideCard.swift"), atomically: true, encoding: .utf8)
        try "struct AgentCard {}".write(to: root.appendingPathComponent("Views/AgentCard.swift"), atomically: true, encoding: .utf8)
        let service = PreparedSweepService(store: store)
        let sweep = PreparedSweep(title: "How cards look", body: "One look for the card role.", parentId: goal.id, manifest: sweepManifest(items()), note: "Made from the code check.")
        guard case .created(let ticket) = try service.create(projectId: project.id, sweep, appRoot: root.path) else { return XCTFail("should be created") }
        XCTAssertEqual(ticket.type, .sweep)
        XCTAssertEqual(ticket.status, .yourCall, "waiting for the owner, with no agent and no model call")
        XCTAssertEqual(ticket.parentId, goal.id)
        XCTAssertEqual(try store.sweepItems(ticketId: ticket.id).count, 2)
        XCTAssertNotNil(try store.proposalManifest(ticketId: ticket.id))
        XCTAssertTrue(try store.notes(ticketId: ticket.id).contains { $0.body == "Made from the code check." })
        XCTAssertEqual(try store.events(ticketId: ticket.id, kinds: ["offer"]).count, 1)
        XCTAssertNil(ticket.takenBy)
        // The owner can accept it like any Proposal.
        XCTAssertEqual(try store.acceptProposal(ticketId: ticket.id).ticket.status, .accepted)

        let ghost = PreparedSweep(title: "Ghost", body: "x", manifest: sweepManifest(items() + [ManifestItem(id: "g", title: "G", name: "GhostCard", file: "Views/GhostCard.swift", kind: "with actions")]))
        guard case .rejected(let issues) = try service.create(projectId: project.id, ghost, appRoot: root.path) else { return XCTFail("a card that does not exist must be refused") }
        XCTAssertTrue(codes(issues).contains("items.file-missing"))
        XCTAssertEqual(try store.tickets(TicketFilter(types: [.sweep])).count, 1, "nothing was made for the refused one")
    }
}
