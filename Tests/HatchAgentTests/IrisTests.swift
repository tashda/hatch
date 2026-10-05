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
    func testTheNewShapeFillsTheReadingAssumptionsAndReasons() throws {
        let r = try IrisResult.parse(##"{"path":"visual","title":"Specs empty state","reading":"What: narrow card.","assumed":["the card is meant to be wide"],"related":[{"ticket":"#4","why":"same empty state"},{"ticket":"#9"},"#11"],"duplicateOf":"#4","duplicateSure":true,"duplicateWhy":"same screen, same problem","questions":[{"text":"Q?","suggestions":["a","b"],"stakes":"low","rerun":true}]}"##)
        XCTAssertEqual(r.rewrite, .init(title: "Specs empty state", body: "What: narrow card."))
        XCTAssertEqual(r.assumed, ["the card is meant to be wide"])
        XCTAssertEqual(r.related, ["#4", "#9", "#11"])
        XCTAssertEqual(r.relatedWhy, ["#4": "same empty state"], "a link with no reason carries none, so it is not made")
        XCTAssertEqual(r.duplicateWhy, "same screen, same problem")
        XCTAssertEqual(r.questions.first?.stakes, QuestionStakes.low)
        XCTAssertEqual(r.questions.first?.rerun, true)
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
    func testThePromptStatesTheRulesAndNeverAssumesRedMarks() throws {
        let (store, p) = try Fixture.store()
        let t = try Fixture.ticket(store, p, title: "Panel odd", body: "Looks odd.")
        let prompt = IrisPrompt.make(try VettingRequest.build(store: store, ticketId: t.id))
        XCTAssertTrue(prompt.contains("Never invent a fact"))
        XCTAssertTrue(prompt.contains("At most one question"))
        XCTAssertTrue(prompt.contains("Never ask how to build"))
        XCTAssertTrue(prompt.contains("never high or urgent"))
        XCTAssertFalse(prompt.contains("red marks point at what matters"))
    }
    func testASecondCheckStartsFromTheOwnersWordsNotHerEarlierReading() throws {
        let (store, p) = try Fixture.store()
        let t = try Fixture.ticket(store, p, title: "Panel odd", body: "Looks odd.")
        try store.update(t.id, body: IrisReading.compose(words: "Looks odd.", reading: "What: invented detail.", assumed: []), actor: .agent)
        let request = try VettingRequest.build(store: store, ticketId: t.id)
        XCTAssertEqual(request.ticket.body, "Looks odd.")
    }
    func testAParentAndItsPartsAreNotEachOthersCandidates() throws {
        let (store, p) = try Fixture.store()
        let parent = try Fixture.ticket(store, p, type: .theme, title: "Footer hover is unstable", body: "Footer hover circles jump", status: .draft)
        let a = try store.createTicket(projectId: p.id, type: .bug, title: "Footer hover circles jump", body: "Footer hover circles jump", parentId: parent.id, status: .checking, actor: .hatch)
        _ = try store.createTicket(projectId: p.id, type: .bug, title: "Footer hover log redraws", body: "Footer hover log", parentId: parent.id, status: .checking, actor: .hatch)
        let request = try VettingRequest.build(store: store, ticketId: a.id)
        XCTAssertTrue(request.similar.isEmpty, "IR6: it would otherwise ask 'same as \(parent.displayNumber)?' about its own parent")
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

    /// A small app: a Toast screen, a Footer screen, and a Decide screen that shows "Needs a sitting".
    var anchors: SourceAnchors {
        SourceAnchors(files: [
            ("App/Screens/ToastView.swift", "struct ToastView: View {}"),
            ("App/Components/FooterParts.swift", "struct FooterLog: View {}"),
            ("App/Screens/DecideView.swift", "struct DecideView: View { Text(\"Needs a sitting\") }"),
        ])
    }


    func testOneQuestionAtMostGoesToTheOwner() throws {
        let out = try IrisApplier.apply(VettingResult(questions: [.init(text: "Which toast?", suggestions: ["A", "B"]), .init(text: "Which OS?")]), to: t.id, store: store)
        XCTAssertEqual(out.questionsAsked, 1, "IR10: one question at most")
        XCTAssertEqual(try status(), .needsAnswers)
        let qs = try store.questions(ticketId: t.id)
        XCTAssertEqual(qs.map(\.askedBy), ["Iris"])
        XCTAssertEqual(qs[0].suggestions, ["A", "B"])
        XCTAssertTrue(qs[0].text.hasSuffix("I will wait for your answer."), "a question with no stakes named waits, and says so")
    }

    func testNothingToSayMovesToReadyByHatch() throws {
        let out = try IrisApplier.apply(VettingResult(), to: t.id, store: store)
        XCTAssertEqual(out.status, .ready)
        let move = try store.events(ticketId: t.id, kinds: ["status"]).last!
        XCTAssertEqual(move.actor, "hatch")
    }

    func testIrisFilesWhatSheDecidesAndNeverSetsHighPriority() throws {
        let other = try Fixture.ticket(store, project, type: .bug, title: "Toast timer", body: "The toast disappears too fast.", status: .draft)
        var r = VettingResult(rewrite: .init(title: "Toast clipped at large text", body: "Steps: ...", changes: []),
                              related: ["new-\(other.id)"], specTouches: ["NOTIF-1.2"])
        r.relatedWhy = ["new-\(other.id)": "her own reason"]
        r.assumed = ["the toast is the notification toast"]
        r.path = .bug
        r.area = "notifications"
        r.priority = "urgent"
        r.project = "echo-tools"
        let out = try IrisApplier.apply(r, to: t.id, store: store, candidates: [other.id], anchors: anchors)
        XCTAssertEqual(out.status, .ready, "nothing to ask: filed and on its way (WF-T1)")
        let after = try store.ticket(id: t.id)!
        XCTAssertEqual(after.title, "Toast clipped at large text")
        XCTAssertEqual(after.originalTitle, "Toast broken", "the owner's words stay")
        XCTAssertEqual(after.path, .bug)
        XCTAssertEqual(after.verify, .preview)
        XCTAssertEqual(after.area, "Notifications")
        XCTAssertEqual(after.priority, TicketPriority.normal, "IR4: never High or Urgent; the owner sets those")
        XCTAssertEqual(after.projectId, project.id, "IR4: she never moves a ticket to another project")
        XCTAssertEqual(try store.links(ticketId: t.id).map { $0.link.kind }, [.related])
        let filed = try XCTUnwrap(try store.lastFiling(ticketId: t.id))
        XCTAssertEqual(filed.by, "Iris")
        XCTAssertEqual(filed.fields["path"]?["to"]?.stringValue, "bug")
        XCTAssertEqual(filed.fields["relatedWhy"]?["\(other.id)"]?.stringValue, "both name the toast screen", "the reason is Hatch's, from what both tickets name, not hers")
        let link = try XCTUnwrap(try store.events(ticketId: t.id, kinds: ["link"]).first)
        XCTAssertEqual(link.actor, "Iris", "IR8: history says who linked")
        XCTAssertFalse(try store.events(ticketId: other.id, kinds: ["link"]).isEmpty, "the reason is recorded on both tickets")
    }

    func testTheOwnersWordsStayTheTicketAndHerReadingIsALabelledSection() throws {
        var r = VettingResult(rewrite: .init(title: "Toast clipped", body: "What: the toast is cut off.", changes: []))
        r.assumed = ["it happens at large text sizes"]
        try IrisApplier.apply(r, to: t.id, store: store)
        let body = try XCTUnwrap(try store.ticket(id: t.id)?.body)
        let parts = IrisReading.split(body)
        XCTAssertEqual(parts.words, "Toast broken\n\nIt looks wrong.", "IR2: the owner's words, as written")
        XCTAssertEqual(parts.reading, "What: the toast is cut off.\n\nAssumed: it happens at large text sizes")
        XCTAssertEqual(IrisReading.ownerWords(title: "Whenever I go to Specs it looks odd", body: ""), "Whenever I go to Specs it looks odd")
        XCTAssertEqual(IrisReading.ownerWords(title: "In components I have a bottom…", body: "In components I have a bottom bar"), "In components I have a bottom bar")
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

    func testAnUnsureAreaOrPathIsFiledNotAsked() throws {
        var r = VettingResult()
        r.path = .investigate
        r.area = "Notifications"
        r.confidence = ["path": 0.4, "area": 0.4]
        let out = try IrisApplier.apply(r, to: t.id, store: store)
        XCTAssertEqual(out.questionsAsked, 0, "IR3: she never asks the owner to pick a category")
        XCTAssertEqual(out.status, .ready)
        let after = try store.ticket(id: t.id)!
        XCTAssertEqual(after.path, .investigate)
        XCTAssertEqual(after.area, "Notifications")
        let filed = try XCTUnwrap(try store.events(ticketId: t.id, kinds: ["filed"]).last)
        XCTAssertEqual(filed.payload["guessed"]?.arrayValue?.compactMap(\.stringValue), ["path"], "a weak guess is marked, so the owner can check it")
    }

    func testOnlyTicketsSheWasShownCanBeClosedOnto() throws {
        let hidden = try Fixture.ticket(store, project, type: .bug, title: "Toast broken", body: "It looks wrong.", status: .draft)
        var r = VettingResult(duplicateOf: "new-\(hidden.id)")
        r.duplicateSure = true; r.duplicateWhy = "same screen, same problem"
        let out = try IrisApplier.apply(r, to: t.id, store: store, candidates: [], anchors: anchors)
        XCTAssertEqual(out.status, .ready, "IR8: a ticket she was not shown is not closed onto, even when the words match")
        XCTAssertTrue(try store.links(ticketId: t.id).isEmpty)
    }

    func testAtMostTwoRelatedLinksTheStrongestFirst() throws {
        let weak = try Fixture.ticket(store, project, type: .bug, title: "Toast odd", body: "A toast.", status: .draft)
        let strong = try Fixture.ticket(store, project, type: .bug, title: "Toast timer", body: "The \"Needs a sitting\" toast.", status: .draft)
        let third = try Fixture.ticket(store, project, type: .bug, title: "Toast again", body: "Another toast.", status: .draft)
        let mine = try Fixture.ticket(store, project, type: .bug, title: "Toast broken", body: "The toast says \"Needs a sitting\" and looks wrong.", status: .draft)
        try store.move(mine.id, to: .checking, actor: .owner)
        try IrisApplier.apply(VettingResult(), to: mine.id, store: store, candidates: [weak.id, third.id, strong.id], anchors: anchors)
        let linked = try store.links(ticketId: mine.id).map(\.link.toId)
        XCTAssertEqual(linked.count, 2, "IR9: two at most")
        XCTAssertTrue(linked.contains(strong.id), "a shared quoted label outranks a shared screen word")
    }

    func testAShortcutWordAloneNeverLinksTwoTickets() throws {
        let unlike = try Fixture.ticket(store, project, type: .tweak, title: "Another shortcut", body: "Add a keyboard shortcut to open the page.", status: .draft)
        let mine = try Fixture.ticket(store, project, type: .tweak, title: "Jump to it", body: "I want a keyboard shortcut to jump straight to the page.", status: .draft)
        try store.move(mine.id, to: .checking, actor: .owner)
        try IrisApplier.apply(VettingResult(related: ["new-\(unlike.id)"]), to: mine.id, store: store, candidates: [unlike.id], anchors: anchors)
        XCTAssertTrue(try store.links(ticketId: mine.id).isEmpty, "everyday words prove nothing; only a named screen, a file or a quoted label does")
    }

    func testARepeatIsClosedOnlyWhenHatchCanCorroborateIt() throws {
        let original = try Fixture.ticket(store, project, type: .bug, title: "Toast clipped", body: "The toast is cut off at the edge.", status: .draft)
        var r = VettingResult(duplicateOf: "new-\(original.id)")
        r.duplicateSure = true
        let noReason = try IrisApplier.apply(r, to: t.id, store: store, candidates: [original.id], anchors: anchors)
        XCTAssertEqual(noReason.status, .ready, "IR7: sure, but she cannot say which screen and problem: not closed")

        let t2 = try Fixture.ticket(store, project, type: .bug, title: "Footer log slow", body: "The footer log lags.", status: .draft)
        try store.move(t2.id, to: .checking, actor: .owner)
        r.duplicateWhy = "same screen, same problem"
        let uncorroborated = try IrisApplier.apply(r, to: t2.id, store: store, candidates: [original.id], anchors: anchors)
        XCTAssertEqual(uncorroborated.status, .ready, "her reason alone does not close a ticket: the two do not name one screen or use the same words")

        let t3 = try Fixture.ticket(store, project, type: .bug, title: "Toast clipped again", body: "The toast is cut off at the edge.", status: .draft)
        try store.move(t3.id, to: .checking, actor: .owner)
        let out = try IrisApplier.apply(r, to: t3.id, store: store, candidates: [original.id], anchors: anchors)
        XCTAssertEqual(out.status, .dropped, "WF-T5")
        XCTAssertEqual(try store.links(ticketId: t3.id).map { $0.link.kind }, [.duplicates])
        XCTAssertTrue(try store.notes(ticketId: original.id).contains { $0.body.contains("cut off at the edge") }, "the prompt is kept on the original")
        XCTAssertEqual(try store.events(ticketId: t3.id, kinds: ["duplicate"]).last?.payload["why"]?.stringValue, "same screen, same problem")
        XCTAssertEqual(try store.move(t3.id, to: .draft, actor: .owner).status, .draft, "Reopen undoes it")
    }

    func testALikelyDuplicateIsLinkedNotAsked() throws {
        let original = try Fixture.ticket(store, project, type: .bug, title: "Toast clipped", body: "It looks wrong.", status: .draft)
        let out = try IrisApplier.apply(VettingResult(duplicateOf: "new-\(original.id)"), to: t.id, store: store, candidates: [original.id], anchors: anchors)
        XCTAssertEqual(out.questionsAsked, 0)
        XCTAssertEqual(out.status, .ready)
        XCTAssertEqual(try store.links(ticketId: t.id).map { $0.link.kind }, [.related], "linked, because both name the toast screen")
    }

    func testASplitHappensAtOnceIntoSeparateTicketsAndThePartsAreNotCheckedAgain() throws {
        try store.update(t.id, actor: .owner, area: .some("Notifications"))
        var r = VettingResult()
        r.path = .split
        r.split = [FilingChild(title: "Tabs", path: .visual), FilingChild(title: "History", path: .question), FilingChild(title: "Pinned columns", path: .visual)]
        let out = try IrisApplier.apply(r, to: t.id, store: store)
        XCTAssertEqual(out.questionsAsked, 0, "IR5: no question")
        XCTAssertEqual(out.split.count, 3)
        let original = try store.ticket(id: t.id)!
        XCTAssertEqual(original.status, .dropped, "SW3: the prompt's ticket closes; each thing is its own ticket")
        XCTAssertNotEqual(original.type, .theme, "there is no parent Theme any more")
        XCTAssertTrue(try store.notes(ticketId: t.id).contains { $0.author == "Iris" && $0.body.hasPrefix("Split into") }, "one line says so")
        let parts = try out.split.map { try XCTUnwrap(try store.ticket(id: $0)) }
        XCTAssertEqual(parts.map(\.title).sorted(), ["History", "Pinned columns", "Tabs"])
        XCTAssertTrue(parts.allSatisfy { $0.status == .ready && $0.path != nil && $0.area == "Notifications" && $0.parentId == nil }, "IR6: filed from the split, area from the prompt's ticket, no second vetting")
        XCTAssertTrue(try store.links(ticketId: parts[0].id).contains { $0.link.kind == .related }, "each part says where it came from")
        XCTAssertTrue(try store.events(ticketId: parts[0].id, kinds: ["question"]).isEmpty)
        XCTAssertEqual(try store.splitFamily(of: parts[0].id), Set(parts.dropFirst().map(\.id)).union([t.id]), "a part is never compared with its siblings")
    }

    func testUndoSplitPutsItBackAndIrisIsToldNotToSplitAgain() throws {
        var r = VettingResult()
        r.path = .split
        r.split = [FilingChild(title: "Tabs", path: .visual), FilingChild(title: "History", path: .question)]
        let out = try IrisApplier.apply(r, to: t.id, store: store)
        let back = try store.undoSplit(t.id)
        XCTAssertEqual(back.status, .checking)
        XCTAssertNil(back.path)
        XCTAssertTrue(try out.split.allSatisfy { try store.ticket(id: $0)?.status == .dropped })
        let request = try VettingRequest.build(store: store, ticketId: t.id)
        XCTAssertEqual(request.noSplit, true)
        XCTAssertTrue(IrisPrompt.make(request).contains("do not use path split"))
    }

    func testASplitCannotBeUndoneOnceAPartHasStarted() throws {
        var r = VettingResult()
        r.path = .split
        r.split = [FilingChild(title: "Tabs", path: .visual), FilingChild(title: "History", path: .question)]
        let out = try IrisApplier.apply(r, to: t.id, store: store)
        try store.setTakenBy(out.split[0], "Agent on \(out.split[0])")
        XCTAssertThrowsError(try store.undoSplit(t.id))
    }

    func testAClashWithADecisionOrComponentWaitsAndTheAnswerOnlyReRunsIrisWhenItCouldChangeTheWork() throws {
        var r = VettingResult(questions: [.init(text: "This changes PrimaryButton, used in 14 places. Change it everywhere?",
                                                suggestions: ["Change it everywhere", "Add a variant here", "Keep the component"], about: "component PrimaryButton")])
        r.path = .visual
        try IrisApplier.apply(r, to: t.id, store: store)
        let q = try store.questions(ticketId: t.id)[0]
        XCTAssertEqual(q.purpose, QuestionPurpose.conflict)
        XCTAssertEqual(q.payload?["about"]?.stringValue, "component PrimaryButton")
        XCTAssertEqual(q.payload?["stakes"]?.stringValue, QuestionStakes.high)
        XCTAssertEqual(try store.answer(questionId: q.id, text: "Add a variant here").status, .ready, "IR13: applied here; no second model call")

        let t2 = try Fixture.ticket(store, project, type: .bug, title: "Toast odd", body: "x", status: .draft)
        try store.move(t2.id, to: .checking, actor: .owner)
        try IrisApplier.apply(VettingResult(questions: [.init(text: "A bug or a redesign?", suggestions: ["Bug", "Redesign"], rerun: true)]), to: t2.id, store: store)
        let q2 = try store.questions(ticketId: t2.id)[0]
        XCTAssertEqual(try store.answer(questionId: q2.id, text: "Redesign").status, .checking, "an answer that changes what the ticket is runs her again")
    }

    func testALowStakesQuestionCarriesADefaultAndIsAnsweredWhenItLapses() throws {
        let out = try IrisApplier.apply(VettingResult(questions: [.init(text: "Show the count on the Dock too?", suggestions: ["Yes", "No"], stakes: QuestionStakes.low)]), to: t.id, store: store)
        XCTAssertEqual(out.status, .needsAnswers)
        let q = try store.questions(ticketId: t.id)[0]
        XCTAssertTrue(q.text.contains("I will go ahead with \u{201C}Yes\u{201D}"))
        XCTAssertEqual(try store.answerLapsedAssumptions(), 0, "not yet")
        XCTAssertEqual(try store.answerLapsedAssumptions(at: Date().addingTimeInterval(Double(QuestionStakes.waitSeconds) + 5)), 1)
        let after = try store.ticket(id: t.id)!
        XCTAssertEqual(after.status, .ready)
        XCTAssertEqual(try store.questions(ticketId: t.id)[0].answer, "Yes")
        XCTAssertTrue(try store.notes(ticketId: t.id).contains { $0.author == "Iris" && $0.body.contains("Iris assumed") })
        XCTAssertEqual(try store.events(ticketId: t.id, kinds: ["answer"]).last?.actor, "hatch", "history does not say the owner answered")
    }

    func testAHighStakesQuestionIsNeverAnsweredForTheOwner() throws {
        try IrisApplier.apply(VettingResult(questions: [.init(text: "Replace decision #4?", suggestions: ["Keep it", "Replace it"], about: "decision #4", stakes: QuestionStakes.low)]), to: t.id, store: store)
        XCTAssertEqual(try store.answerLapsedAssumptions(at: Date().addingTimeInterval(86_400)), 0, "a clash with a decision always waits")
        XCTAssertEqual(try status(), .needsAnswers)
    }

    func testOpenQuestionsKeepTheTicketWaitingAndTheReadingIsApplied() throws {
        try IrisApplier.apply(VettingResult(questions: [.init(text: "Q?")], rewrite: .init(title: "N", body: "B")), to: t.id, store: store)
        let after = try store.ticket(id: t.id)!
        XCTAssertEqual(after.status, .needsAnswers)
        XCTAssertEqual(after.title, "N")
        try store.answer(questionId: try store.questions(ticketId: t.id)[0].id, text: "yes")
        XCTAssertEqual(try status(), .ready, "IR13: no second check unless the answer could change the work")
    }

    func testASecondCheckSeesTheAnswersAndAThirdRoundAsksNothing() throws {
        try IrisApplier.apply(VettingResult(questions: [.init(text: "Which toast?", suggestions: ["Error", "Info"], rerun: true)]), to: t.id, store: store)
        try store.answer(questionId: try store.questions(ticketId: t.id)[0].id, text: "Error")
        XCTAssertEqual(try status(), .checking)
        let request = try VettingRequest.build(store: store, ticketId: t.id)
        XCTAssertEqual(request.answered, [.init(question: "Which toast?", answer: "Error")])
        XCTAssertTrue(IrisPrompt.make(request).contains("Which toast? → Error"))

        try IrisApplier.apply(VettingResult(questions: [.init(text: "Light or dark?", rerun: true)]), to: t.id, store: store)
        try store.answer(questionId: try store.questions(ticketId: t.id, openOnly: true)[0].id, text: "Dark")
        XCTAssertEqual(try status(), .checking)
        let third = try IrisApplier.apply(VettingResult(questions: [.init(text: "Which size?")]), to: t.id, store: store)
        XCTAssertEqual(third.questionsAsked, 0, "at most two rounds (WF-Q1)")
        XCTAssertEqual(try status(), .ready)
    }

    func testTheSecondOpinionRunIsRetired() {
        XCTAssertFalse(AgentRole.allCases.contains(.irisUnsure), "IR14: Settings no longer offers it")
        XCTAssertEqual(AgentRole(rawValue: "irisUnsure"), .irisUnsure, "old runs and saved settings still read")
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
