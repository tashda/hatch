import XCTest
@testable import HatchCore

final class SourceAnchorsTests: XCTestCase {
    let anchors = SourceAnchors(files: [
        ("App/Screens/DecideView.swift", "struct DecideView: View { Text(\"Needs a sitting\"); Text(\"Open the Stage\") }"),
        ("App/Screens/DecideLab.swift", "struct DecideLab { let a = \"Needs a sitting\" }"),
        ("App/Screens/SpecsView.swift", "struct SpecsView: View { Text(\"The Spec is empty\") }"),
        ("App/Components/FooterParts.swift", "struct FooterLog: View {}"),
        ("App/Screens/IrisPanel.swift", "struct IrisPanel: View {}"),
        ("App/A.swift", "let x = \"Add item\""), ("App/B.swift", "let x = \"Add item\""), ("App/C.swift", "let x = \"Add item\""), ("App/D.swift", "let x = \"Add item\""),
    ])

    func testAQuotedLabelFoundInTheSourcePointsAtItsFiles() {
        XCTAssertEqual(anchors.files(in: "Why is the \"Open the Stage\" button there?"), ["App/Screens/DecideView.swift"])
        XCTAssertEqual(anchors.files(in: "The card says \u{201C}Needs a sitting\u{201D}"), ["App/Screens/DecideView.swift", "App/Screens/DecideLab.swift"])
    }

    func testALabelFoundInManyFilesOrNotAtAllPointsAtNothing() {
        XCTAssertTrue(anchors.files(in: "The \"Add item\" button").isEmpty, "four files: too common to say which")
        XCTAssertTrue(anchors.files(in: "The \"Imaginary label\" button").isEmpty)
        XCTAssertTrue(anchors.files(in: "The \"Add\" button").isEmpty, "too short to be a label")
    }

    func testARealTypeOrFileNamePointsAtItsFile() {
        XCTAssertEqual(anchors.files(in: "DecideView is crowded"), ["App/Screens/DecideView.swift"])
        XCTAssertEqual(anchors.files(in: "FooterLog is flaky"), ["App/Components/FooterParts.swift"])
        XCTAssertTrue(anchors.files(in: "SomethingInvented is crowded").isEmpty)
    }

    func testAScreenNamedInPlainWordsIsFoundButTheProductsOwnNamesAreNot() {
        XCTAssertEqual(anchors.screens(in: "In Decide the buttons jump"), ["decide"])
        XCTAssertEqual(anchors.screens(in: "Whenever I go to Specs it looks odd"), ["spec"], "stored without the plural, so Spec and Specs both match")
        XCTAssertEqual(anchors.screens(in: "The footers hover is odd"), ["footer"], "a plural still names it")
        XCTAssertTrue(anchors.screens(in: "Iris asks too much").isEmpty, "Iris is in nearly every ticket, so it says nothing about where")
    }

    func testTwoTicketsAreRelatedOnlyWhenTheyNameTheSameThing() throws {
        let both = try XCTUnwrap(anchors.shared("In Decide the footer jumps", "Decide should show options"))
        XCTAssertEqual(both.why, "both name the decide screen")
        let file = try XCTUnwrap(anchors.shared("What is the \"Open the Stage\" button?", "Remove the \"Open the Stage\" button"))
        XCTAssertTrue(file.why.hasPrefix("both point at DecideView.swift"))
        XCTAssertGreaterThan(file.weight, both.weight, "a shared file proves more than a shared screen word")
        XCTAssertNil(anchors.shared("Add a keyboard shortcut to jump to the page", "Keyboard shortcut for the other page"), "everyday words are not evidence")
        XCTAssertNil(anchors.shared("Iris buttons differ", "Iris notice at launch"), "the persona is not a screen")
    }

    func testNearlyIdenticalWordsAreARepeat() {
        XCTAssertGreaterThanOrEqual(TextLikeness.overlap("The toast is cut off at the edge.", "The toast is cut off at the edge!"), TextLikeness.repeatThreshold)
        XCTAssertLessThan(TextLikeness.overlap("The toast is cut off at the edge.", "The footer log lags when hovered."), TextLikeness.repeatThreshold)
    }
}
