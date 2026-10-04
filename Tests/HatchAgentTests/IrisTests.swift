import XCTest
@testable import HatchAgent
@testable import HatchCore

final class IrisParseTests: XCTestCase {
    let json = ##"{"questions":[{"text":"Which toast?","suggestions":["Success","Error"]}],"rewrite":{"title":"Toast spacing","body":"Steps: ...","changes":["Added steps"]},"typeSuggestion":{"type":"Question","reason":"No steps."},"related":["#12",13],"specTouches":["NOTIF-1.2"],"duplicateOf":"#9"}"##

    func check(_ r: VettingResult, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.questions, [.init(text: "Which toast?", suggestions: ["Success", "Error"])], file: file, line: line)
        XCTAssertEqual(r.rewrite?.title, "Toast spacing", file: file, line: line)
        XCTAssertEqual(r.rewrite?.changes, ["Added steps"], file: file, line: line)
        XCTAssertEqual(r.typeSuggestion?.type, .question, file: file, line: line)
        XCTAssertEqual(r.related, ["#12", "#13"], file: file, line: line)
        XCTAssertEqual(r.specTouches, ["NOTIF-1.2"], file: file, line: line)
        XCTAssertEqual(r.duplicateOf, "#9", file: file, line: line)
    }

    func testPlainJSON() throws { check(try IrisResult.parse(json)) }
    func testCodeFence() throws { check(try IrisResult.parse("```json\n\(json)\n```")) }
    func testLeadingAndTrailingProse() throws { check(try IrisResult.parse("Sure! Here is my check:\n\n\(json)\n\nLet me know if you need more.")) }
    func testBracesInProseBeforeTheObject() throws { check(try IrisResult.parse("I looked at {the toast} and {} found this: \(json)")) }
    func testBracesInsideStrings() throws {
        let r = try IrisResult.parse(#"{"rewrite":{"title":"T","body":"Use {x} and \"} quotes\"","changes":[]}}"#)
        XCTAssertEqual(r.rewrite?.body, #"Use {x} and "} quotes""#)
    }
    func testSnakeCaseKeys() throws {
        let r = try IrisResult.parse(#"{"type_suggestion":{"type":"sketch","reason":"layout"},"spec_touches":["A-1"],"duplicate_of":7}"#)
        XCTAssertEqual(r.typeSuggestion?.type, .sketch)
        XCTAssertEqual(r.specTouches, ["A-1"])
        XCTAssertEqual(r.duplicateOf, "#7")
    }
    func testEmptyObjectIsAValidCleanResult() throws {
        let r = try IrisResult.parse("{}")
        XCTAssertEqual(r, VettingResult())
    }
    func testNullsAreLeftOut() throws {
        let r = try IrisResult.parse(#"{"rewrite":null,"typeSuggestion":null,"duplicateOf":null,"questions":[]}"#)
        XCTAssertEqual(r, VettingResult())
    }
    func testQuestionsAsPlainStringsAndBlanksDropped() throws {
        let r = try IrisResult.parse(#"{"questions":["What size?",{"text":"  "},{"text":"Which?","suggestions":["a","","b"]}]}"#)
        XCTAssertEqual(r.questions, [.init(text: "What size?"), .init(text: "Which?", suggestions: ["a", "b"])])
    }
    func testQuestionsAreCapped() throws {
        let qs = (1...9).map { #"{"text":"Q\#($0)"}"# }.joined(separator: ",")
        XCTAssertEqual(try IrisResult.parse("{\"questions\":[\(qs)]}").questions.count, IrisPrompt.maxQuestions)
    }
    func testFilingFields() throws {
        let r = try IrisResult.parse(##"{"path":"investigate","area":"Drivers","priority":"urgent","verify":"numbers","project":"echo-tools","confidence":{"path":0.6,"area":"x"},"parent":"#40","blocks":["#41"],"duplicateOf":"#9","duplicateSure":true,"split":[{"title":"A","path":"visual"},{"title":""}],"questions":[{"text":"Keep?","suggestions":["Keep","Replace"],"about":"decision #12"}]}"##)
        XCTAssertEqual(r.path, .investigate)
        XCTAssertEqual(r.area, "Drivers")
        XCTAssertEqual(r.priority, "urgent")
        XCTAssertEqual(r.verify, .numbers)
        XCTAssertEqual(r.project, "echo-tools")
        XCTAssertEqual(r.confidence, ["path": 0.6])
        XCTAssertFalse(r.isSure("path"))
        XCTAssertTrue(r.isSure("area"))
        XCTAssertEqual(r.parent, "#40")
        XCTAssertEqual(r.blocks, ["#41"])
        XCTAssertTrue(r.duplicateSure)
        XCTAssertEqual(r.split, [FilingChild(title: "A", path: .visual)])
        XCTAssertEqual(r.questions.first?.about, "decision #12")
    }
    func testPathNamesModelsUse() {
        XCTAssertEqual(WorkPath.parse("Bug, cause known"), .bug)
        XCTAssertEqual(WorkPath.parse("bug_known"), .bug)
        XCTAssertEqual(WorkPath.parse("Performance"), .investigate)
        XCTAssertNil(WorkPath.parse("whatever"))
        XCTAssertThrowsError(try IrisResult.parse(#"{"path":"whatever"}"#))
    }
    func testTheOlderTypeSuggestionStillGivesAPath() throws {
        XCTAssertEqual(try IrisResult.parse(#"{"typeSuggestion":{"type":"sketch","reason":"layout"}}"#).effectivePath, .visual)
    }
    func testNoJSONIsAnError() {
        XCTAssertThrowsError(try IrisResult.parse("I could not find anything wrong.")) { XCTAssertEqual($0 as? IrisError, .noJSON) }
        XCTAssertThrowsError(try IrisResult.parse("{ broken"))
    }
    func testUnknownTypeIsAnError() {
        XCTAssertThrowsError(try IrisResult.parse(#"{"typeSuggestion":{"type":"epic","reason":"x"}}"#)) { XCTAssertTrue("\($0)".contains("epic")) }
    }
    func testTheEchoedEmptyShapeMeansNoSuggestion() throws {
        let r = try IrisResult.parse(#"{"questions":[],"rewrite":{"title":"","body":"","changes":[""]},"typeSuggestion":{"type":"","reason":""},"related":[],"duplicateOf":""}"#)
        XCTAssertNil(r.rewrite)
        XCTAssertNil(r.typeSuggestion)
        XCTAssertNil(try IrisResult.parse(#"{"typeSuggestion":{}}"#).typeSuggestion)
        XCTAssertThrowsError(try IrisResult.parse(#"{"typeSuggestion":{"type":"","reason":"no steps"}}"#), "a reason without a type is inconsistent")
    }
    func testRewriteWithoutTextIsAnError() {
        XCTAssertThrowsError(try IrisResult.parse(#"{"rewrite":{"changes":["x"]}}"#))
        XCTAssertThrowsError(try IrisResult.parse(#"{"rewrite":"just text"}"#))
    }
    func testObjectWithKnownKeysBeatsAnEarlierObject() throws {
        let r = try IrisResult.parse(#"Example: {"foo": 1} Real: {"specTouches":["X-1"]}"#)
        XCTAssertEqual(r.specTouches, ["X-1"])
    }
}

final class IrisPromptTests: XCTestCase {
    func testPromptDemandsJSONAndIncludesTheCandidates() throws {
        let (store, p) = try Fixture.store()
        let other = try Fixture.ticket(store, p, title: "Toast padding too small", body: "Padding on toasts.")
        try store.upsertSpecItems(projectId: p.id, items: [(code: "NOTIF-1.2", area: "Notifications", text: "A toast has 12pt padding.", source: nil)])
        let t = try Fixture.ticket(store, p, title: "Toast spacing in dark mode", body: "Toasts feel cramped.")
        let prompt = IrisPrompt.make(try VettingRequest.build(store: store, ticketId: t.id))
        XCTAssertTrue(prompt.contains("ONE JSON object"))
        XCTAssertTrue(prompt.contains(other.displayNumber + " [proposal"))
        XCTAssertTrue(prompt.contains("NOTIF-1.2: A toast has 12pt padding."))
        XCTAssertTrue(prompt.contains("Notifications (NOTIF)"))
        XCTAssertFalse(prompt.contains("\(t.displayNumber) [proposal"), "the ticket is not its own candidate")
    }
    func testLongBodiesAreCut() throws {
        let (store, p) = try Fixture.store()
        let t = try Fixture.ticket(store, p, body: String(repeating: "word ", count: 1000))
        let prompt = IrisPrompt.make(try VettingRequest.build(store: store, ticketId: t.id))
        XCTAssertTrue(prompt.contains("characters cut"))
        XCTAssertLessThan(prompt.count, 6500)
    }
}

final class IrisApplierTests: XCTestCase {
    var store: HatchStore!
    var project: Project!
    var t: Ticket!

    override func setUpWithError() throws {
        (store, project) = try Fixture.store()
        t = try Fixture.ticket(store, project, type: .bug, title: "Toast broken", body: "It looks wrong.", status: .draft)
        try store.move(t.id, to: .checking, actor: .owner)
    }

    func status() throws -> Status { try store.ticket(id: t.id)!.status }

    func testQuestionsGoToTheOwner() throws {
        let out = try IrisApplier.apply(VettingResult(questions: [.init(text: "Which toast?", suggestions: ["A", "B"]), .init(text: "Which OS?")]), to: t.id, store: store)
        XCTAssertEqual(out.questionsAsked, 2)
        XCTAssertEqual(try status(), .needsAnswers)
        let qs = try store.questions(ticketId: t.id)
        XCTAssertEqual(qs.map(\.askedBy), ["Iris", "Iris"])
        XCTAssertEqual(qs[0].suggestions, ["A", "B"])
    }

    func testNothingToSayMovesToReadyByHatch() throws {
        let out = try IrisApplier.apply(VettingResult(), to: t.id, store: store)
        XCTAssertEqual(out.status, .ready)
        let move = try store.events(ticketId: t.id, kinds: ["status"]).last!
        XCTAssertEqual(move.actor, "hatch")
    }

    func testIrisFilesWhatSheIsSureOf() throws {
        let other = try Fixture.ticket(store, project, type: .bug, title: "Toast timer", body: "x", status: .draft)
        var r = VettingResult(rewrite: .init(title: "Toast clipped at large text", body: "Steps: ...", changes: ["structure"]),
                              related: ["new-\(other.id)"], specTouches: ["NOTIF-1.2"])
        r.path = .bug
        r.area = "notifications"
        r.priority = "high"
        let out = try IrisApplier.apply(r, to: t.id, store: store)
        XCTAssertEqual(out.status, .ready, "nothing to ask: filed and on its way (WF-T1)")
        let after = try store.ticket(id: t.id)!
        XCTAssertEqual(after.title, "Toast clipped at large text")
        XCTAssertEqual(after.originalTitle, "Toast broken", "the owner's words stay")
        XCTAssertEqual(after.path, .bug)
        XCTAssertEqual(after.verify, .preview)
        XCTAssertEqual(after.area, "Notifications")
        XCTAssertEqual(after.priority, TicketPriority.high)
        XCTAssertEqual(try store.links(ticketId: t.id).map { $0.link.kind }, [.related])
        let filed = try XCTUnwrap(try store.lastFiling(ticketId: t.id))
        XCTAssertEqual(filed.by, "Iris")
        XCTAssertEqual(filed.fields["path"]?["to"]?.stringValue, "bug")
        XCTAssertEqual(filed.fields["priority"]?["to"]?.stringValue, "High")
    }

    func testThePathSetsTheType() throws {
        var r = VettingResult()
        r.path = .investigate
        try IrisApplier.apply(r, to: t.id, store: store)
        XCTAssertEqual(try store.ticket(id: t.id)?.type, .bug)
        XCTAssertEqual(try store.ticket(id: t.id)?.verify, .numbers)
        let t2 = try Fixture.ticket(store, project, type: .question, title: "Pool", body: "Actors?", status: .draft)
        try store.move(t2.id, to: .checking, actor: .owner)
        var r2 = VettingResult()
        r2.path = .approaches
        try IrisApplier.apply(r2, to: t2.id, store: store)
        XCTAssertEqual(try store.ticket(id: t2.id)?.type, .proposal)
        XCTAssertEqual(try store.ticket(id: t2.id)?.verify, .ci)
    }

    func testAnUnsureAreaIsAskedWithHerGuessFirstAndAppliedOnTheAnswer() throws {
        var r = VettingResult()
        r.path = .bug
        r.area = "Notifications"
        r.confidence = ["area": 0.4]
        let out = try IrisApplier.apply(r, to: t.id, store: store)
        XCTAssertEqual(out.questionsAsked, 1)
        let q = try store.questions(ticketId: t.id)[0]
        XCTAssertEqual(q.purpose, QuestionPurpose.area)
        XCTAssertEqual(q.suggestions.first, "Notifications", "her guess is first (WF-T3)")
        try store.update(t.id, actor: .owner, area: .some(nil))
        let after = try store.answer(questionId: q.id, text: "Notifications")
        XCTAssertEqual(after.area, "Notifications")
        XCTAssertEqual(after.status, .ready, "only field questions: filed without a second check")
    }

    func testAnUnsurePathIsAsked() throws {
        var r = VettingResult()
        r.path = .investigate
        r.confidence = ["path": 0.5]
        try IrisApplier.apply(r, to: t.id, store: store)
        let q = try store.questions(ticketId: t.id)[0]
        XCTAssertEqual(q.purpose, QuestionPurpose.path)
        XCTAssertEqual(q.suggestions.first, WorkPath.investigate.displayName)
        XCTAssertNil(try store.ticket(id: t.id)?.path, "not filed until answered")
        let after = try store.answer(questionId: q.id, text: WorkPath.bug.displayName)
        XCTAssertEqual(after.path, .bug)
    }

    func testAPlainDuplicateIsClosedOntoTheOriginal() throws {
        let original = try Fixture.ticket(store, project, type: .bug, title: "Toast clipped", body: "x", status: .draft)
        var r = VettingResult(duplicateOf: "new-\(original.id)")
        r.duplicateSure = true
        let out = try IrisApplier.apply(r, to: t.id, store: store)
        XCTAssertEqual(out.status, .dropped, "WF-T5")
        XCTAssertEqual(try store.links(ticketId: t.id).map { $0.link.kind }, [.duplicates])
        XCTAssertTrue(try store.notes(ticketId: original.id).contains { $0.body.contains("It looks wrong.") }, "the prompt is kept on the original")
        XCTAssertEqual(try store.move(t.id, to: .draft, actor: .owner).status, .draft, "Reopen undoes it")
    }

    func testALikelyDuplicateIsAsked() throws {
        let original = try Fixture.ticket(store, project, type: .bug, title: "Toast clipped", body: "x", status: .draft)
        try IrisApplier.apply(VettingResult(duplicateOf: "new-\(original.id)"), to: t.id, store: store)
        let q = try store.questions(ticketId: t.id)[0]
        XCTAssertEqual(q.purpose, QuestionPurpose.duplicate)
        XCTAssertEqual(q.suggestions, [IrisChoices.duplicateYes, IrisChoices.duplicateNo])
        XCTAssertEqual(try store.answer(questionId: q.id, text: IrisChoices.duplicateYes).status, .dropped)

        let t2 = try Fixture.ticket(store, project, type: .bug, title: "Toast clipped again", body: "y", status: .draft)
        try store.move(t2.id, to: .checking, actor: .owner)
        try IrisApplier.apply(VettingResult(duplicateOf: "new-\(original.id)"), to: t2.id, store: store)
        let q2 = try store.questions(ticketId: t2.id)[0]
        XCTAssertEqual(try store.answer(questionId: q2.id, text: IrisChoices.duplicateNo).status, .ready, "kept, and filed")
    }

    func testASplitIsConfirmedAndMakesAThemeWithChildren() throws {
        var r = VettingResult()
        r.path = .split
        r.split = [FilingChild(title: "Tabs", path: .visual), FilingChild(title: "History", path: .question), FilingChild(title: "Pinned columns", path: .visual)]
        try IrisApplier.apply(r, to: t.id, store: store)
        let q = try store.questions(ticketId: t.id)[0]
        XCTAssertEqual(q.purpose, QuestionPurpose.split)
        XCTAssertTrue(q.text.contains("Tabs; History; Pinned columns"))
        let theme = try store.answer(questionId: q.id, text: IrisChoices.splitYes)
        XCTAssertEqual(theme.type, .theme)
        XCTAssertEqual(theme.status, .draft)
        let children = try store.tickets(TicketFilter(parentId: t.id))
        XCTAssertEqual(children.map(\.title).sorted(), ["History", "Pinned columns", "Tabs"])
        XCTAssertTrue(children.allSatisfy { $0.status == .checking }, "each child goes to Iris on its own")
    }

    func testAClashWithADecisionOrComponentIsAQuestionAndTheAnswerGoesBackToIris() throws {
        var r = VettingResult(questions: [.init(text: "This changes PrimaryButton, used in 14 places. Change it everywhere?",
                                                suggestions: ["Change it everywhere", "Add a variant here", "Keep the component"], about: "component PrimaryButton")])
        r.path = .visual
        try IrisApplier.apply(r, to: t.id, store: store)
        let q = try store.questions(ticketId: t.id)[0]
        XCTAssertEqual(q.purpose, QuestionPurpose.conflict)
        XCTAssertEqual(q.payload?["about"]?.stringValue, "component PrimaryButton")
        XCTAssertEqual(try store.answer(questionId: q.id, text: "Add a variant here").status, .checking, "Iris files it with the answer")
    }

    func testAtMostThreeQuestions() throws {
        var r = VettingResult(questions: [.init(text: "A?"), .init(text: "B?"), .init(text: "C?")])
        r.path = .bug
        r.area = "Notifications"
        r.confidence = ["area": 0.2]
        XCTAssertEqual(try IrisApplier.apply(r, to: t.id, store: store).questionsAsked, 3)
    }

    func testOpenQuestionsKeepTheTicketWaitingAndTheRewriteIsApplied() throws {
        try IrisApplier.apply(VettingResult(questions: [.init(text: "Q?")], rewrite: .init(title: "N", body: "B")), to: t.id, store: store)
        let after = try store.ticket(id: t.id)!
        XCTAssertEqual(after.status, .needsAnswers)
        XCTAssertEqual(after.title, "N")
        try store.answer(questionId: try store.questions(ticketId: t.id)[0].id, text: "yes")
        XCTAssertEqual(try status(), .checking, "Iris checks again with the answer (WF-Q2)")
    }

    func testASecondCheckSeesTheAnswersAndAThirdRoundAsksNothing() throws {
        try IrisApplier.apply(VettingResult(questions: [.init(text: "Which toast?", suggestions: ["Error", "Info"])]), to: t.id, store: store)
        try store.answer(questionId: try store.questions(ticketId: t.id)[0].id, text: "Error")
        XCTAssertEqual(try status(), .checking)
        let request = try VettingRequest.build(store: store, ticketId: t.id)
        XCTAssertEqual(request.answered, [.init(question: "Which toast?", answer: "Error")])
        XCTAssertTrue(IrisPrompt.make(request).contains("Which toast? → Error"))

        try IrisApplier.apply(VettingResult(questions: [.init(text: "Light or dark?")]), to: t.id, store: store)
        try store.answer(questionId: try store.questions(ticketId: t.id, openOnly: true)[0].id, text: "Dark")
        XCTAssertEqual(try status(), .checking)
        let third = try IrisApplier.apply(VettingResult(questions: [.init(text: "Which size?")]), to: t.id, store: store)
        XCTAssertEqual(third.questionsAsked, 0, "at most two rounds (WF-Q1)")
        XCTAssertEqual(try status(), .ready)
    }

    // Older suggestions, still decided with Accept, Edit and Keep mine.

    func seedSuggestion(_ s: VettingSuggestion) throws {
        try store.recordSuggestion(ticketId: t.id, s, by: "Iris")
        try store.move(t.id, to: .needsAnswers, actor: .agent)
    }

    func testAcceptAppliesAnOlderRewriteAndKeepsTheOriginal() throws {
        try seedSuggestion(VettingSuggestion(rewrite: .init(title: "Toast clipped", body: "Steps...", changes: []), typeSuggestion: .init(type: .question, reason: "r")))
        let after = try IrisApplier.accept(ticketId: t.id, store: store)
        XCTAssertEqual(after.title, "Toast clipped")
        XCTAssertEqual(after.originalTitle, "Toast broken")
        XCTAssertEqual(after.type, .bug, "the type changes only when the owner accepts it")
        XCTAssertEqual(after.status, .ready)
        XCTAssertNil(try store.pendingSuggestion(ticketId: t.id))
    }

    func testKeepMineAndEditOnAnOlderSuggestion() throws {
        try seedSuggestion(VettingSuggestion(rewrite: .init(title: "Other", body: "Other body", changes: [])))
        let kept = try IrisApplier.keepMine(ticketId: t.id, store: store)
        XCTAssertEqual(kept.title, "Toast broken")
        XCTAssertEqual(kept.status, .ready)
    }

    func testUnknownDuplicateIsIgnored() throws {
        let out = try IrisApplier.apply(VettingResult(duplicateOf: "#99999"), to: t.id, store: store)
        XCTAssertEqual(out.questionsAsked, 0)
        XCTAssertEqual(out.status, .ready)
    }

    func testApplyingToATicketNotInCheckingFails() throws {
        try store.move(t.id, to: .ready, actor: .hatch)
        XCTAssertThrowsError(try IrisApplier.apply(VettingResult(), to: t.id, store: store))
    }

    func testDecisionWithoutSuggestionFails() {
        XCTAssertThrowsError(try IrisApplier.accept(ticketId: t.id, store: store))
    }
}
