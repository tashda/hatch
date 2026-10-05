import XCTest
@testable import HatchCore

/// The app's own components in the system (CM16 to CM18): accepted from Hatch's proposal, consolidated, split, replaced
/// by the native option, given usage rules, made a setting or redesigned. Fixtures are Hatch's own chips.
final class ComponentOwnTests: XCTestCase {
    let chips = AppComponentProposal(id: "chip", title: "Chip", family: "chip", interactive: false,
                                     members: ["HXChip", "PlainChip", "HXProblemChip", "HXIssueSample"],
                                     variants: [], sizes: [.init(name: "small", members: ["HXIssueSample"], note: nil),
                                                           .init(name: "medium", members: ["HXChip", "PlainChip", "HXProblemChip"], note: "weights differ")],
                                     uses: 21, why: "")

    private func system() throws -> ComponentSystem {
        var s = ComponentTemplates.native.system(name: "Hatch")
        try s.change(.accept(chips))
        return s
    }

    func testAcceptingTakesTheProposedSizesAsVariants() throws {
        let s = try system()
        XCTAssertEqual(s.own.map(\.id), ["chip"])
        XCTAssertEqual(s.own[0].variants.map(\.name), ["small", "medium"])
        XCTAssertEqual(s.ownComponent(containing: "PlainChip")?.id, "chip")
        XCTAssertThrowsError(try { var t = s; try t.change(.accept(chips)) }(), "accepted once")
        XCTAssertTrue(s.problems().isEmpty, s.problems().joined(separator: "; "))
    }

    func testMovingConsolidatesSizesAndEmptyVariantsGo() throws {
        var s = try system()
        try s.change(.move(views: ["HXIssueSample"], component: "chip", variant: "medium"))
        XCTAssertEqual(s.own[0].variants.map(\.name), ["medium"], "small is empty, so it goes")
        XCTAssertEqual(Set(s.own[0].variants[0].views), ["HXChip", "PlainChip", "HXProblemChip", "HXIssueSample"])
    }

    func testSplittingMakesAComponentOfItsOwn() throws {
        var s = try system()
        try s.change(.split(views: ["HXProblemChip"], from: "chip", title: "Problem chip"))
        XCTAssertEqual(s.own.map(\.id), ["chip", "chip.problem-chip"])
        XCTAssertEqual(s.ownComponent(containing: "HXProblemChip")?.title, "Problem chip")
        XCTAssertFalse(s.own[0].views.contains("HXProblemChip"))
        XCTAssertTrue(s.problems().isEmpty)
    }

    func testAViewIsInOneComponentOnly() throws {
        var s = try system()
        s.own.append(OwnComponent(id: "label", title: "Label", family: "label", variants: [.init(name: "standard", views: ["PlainChip"])]))
        XCTAssertTrue(s.problems().contains { $0.contains("PlainChip") })
    }

    func testNativeUsageRulesSettingsAndRedesign() throws {
        var s = try system()
        try s.change(.native(component: "chip", element: "badge"))
        XCTAssertEqual(s.own("chip")?.native, "badge")
        try s.change(.use(component: "chip", variant: "medium", text: "A status or a project in a row"))
        XCTAssertEqual(s.own("chip")?.variants[1].use, "A status or a project in a row")
        let setting = try s.makeOwnSetting(component: "chip", variant: "medium")
        XCTAssertEqual(setting.type, .proposal)
        XCTAssertNotNil(s.own("chip")?.variants[1].setting)
        let redesign = try s.redesignOwn(component: "chip", what: "Calmer chips.")
        XCTAssertTrue(redesign.body.contains("specimens in the Stage") && redesign.body.contains("native option"))
        XCTAssertEqual(s.own("chip")?.redesign, redesign.title)
        // Agents read the components and their rules in the README.
        XCTAssertTrue(s.readme().contains("A status or a project in a row"))
        XCTAssertTrue(s.readme().contains("use SwiftUI's badge instead"))
    }

    private func two() throws -> ComponentSystem {
        var s = ComponentTemplates.native.system(name: "Hatch")
        try s.change(.accept(.init(id: "chip.HXChip", title: "Chip", family: "chip", interactive: false, members: ["HXChip", "HXProblemChip"],
                                   variants: [], sizes: [], uses: 12, why: "")))
        try s.change(.accept(.init(id: "chip.PlainChip", title: "Plain chip", family: "chip", interactive: false, members: ["PlainChip"],
                                   variants: [], sizes: [], uses: 7, why: "")))
        return s
    }

    /// The owner can merge a whole group (Tag) into another (Status chip).
    func testMergingAGroupIntoAnother() throws {
        var s = try two()
        try s.change(.merge(from: "chip.PlainChip", into: "chip.HXChip"))
        XCTAssertEqual(s.own.map(\.id), ["chip.HXChip"])
        XCTAssertEqual(Set(s.own[0].views), ["HXChip", "HXProblemChip", "PlainChip"])
        XCTAssertThrowsError(try s.change(.merge(from: "chip.HXChip", into: "chip.HXChip")))
    }

    func testDecidingNamesItKeepsALookAndDraftsTheTicket() throws {
        var s = try two()
        let draft = try s.decideOwn(component: "chip.HXChip", title: "Status chip", codeName: "StatusChip", look: "HXChip")
        XCTAssertEqual(s.own("chip.HXChip")?.status, .agreed)
        XCTAssertEqual(s.own("chip.HXChip")?.codeName, "StatusChip")
        XCTAssertEqual(draft?.type, .tweak)
        XCTAssertEqual(draft?.title, "Make HXChip and HXProblemChip one StatusChip")
        XCTAssertTrue(draft!.body.contains("Keep the look of `HXChip`"))
        // One view keeping its own name: nothing to change in the code.
        XCTAssertNil(try s.decideOwn(component: "chip.PlainChip", title: "Tag", codeName: "PlainChip", look: nil))
        XCTAssertThrowsError(try s.decideOwn(component: "chip.PlainChip", title: "Tag", codeName: "plain chip", look: nil), "a Swift type name")
        // A view moved in later makes it a decision again.
        try s.change(.move(views: ["PlainChip"], component: "chip.HXChip", variant: "standard"))
        XCTAssertEqual(s.own("chip.HXChip")?.status, .provisional)
    }

    func testKeepingApartAndNotAComponent() throws {
        var s = try two()
        try s.change(.apart(component: "chip.HXChip"))
        XCTAssertEqual(Set(s.own.map(\.id)), ["chip.HXChip", "chip.HXProblemChip", "chip.PlainChip"])
        XCTAssertTrue(s.own.filter { $0.id != "chip.PlainChip" }.allSatisfy { $0.status == .agreed && $0.views.count == 1 })
        try s.change(.notComponent(views: ["PlainChip"]))
        XCTAssertNil(s.ownComponent(containing: "PlainChip"))
        XCTAssertEqual(s.ownExcluded, ["PlainChip"])
        XCTAssertEqual(try JSONDecoder().decode(ComponentSystem.self, from: s.encoded()).ownExcluded, ["PlainChip"])
    }

    func testOlderSystemFilesStillLoad() throws {
        var s = ComponentTemplates.native.system(name: "Hatch")
        let data = try s.encoded()
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "own")
        let old = try JSONDecoder().decode(ComponentSystem.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.own.isEmpty)
        try s.change(.accept(chips))
        let round = try JSONDecoder().decode(ComponentSystem.self, from: s.encoded())
        XCTAssertEqual(round.own, s.own)
    }

    func testTheAPIBodyIsParsed() throws {
        let body: [String: JSONValue] = ["op": .string("move"), "component": .string("chip"), "variant": .string("small"),
                                         "views": .array([.string("HXChip")])]
        XCTAssertEqual(try OwnChange.parse(body) { _ in nil }, .move(views: ["HXChip"], component: "chip", variant: "small"))
        XCTAssertThrowsError(try OwnChange.parse(["op": .string("accept"), "component": .string("nope")]) { _ in nil })
    }
}
