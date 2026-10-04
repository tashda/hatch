import XCTest
@testable import HatchCore

final class QuestionDigestTests: XCTestCase {
    /// The question from #5 that showed the problem: one long paragraph with the ask in the middle.
    let long = "I can't prepare #5 yet. My only workspace is the notebook. It has no app checkout, so I can't read the real Iris/Echo launch notice view that the first specimen has to be drawn from. It also has no specimens folder and no manifest example, so I don't know the manifest format. Can you give me access to a tashda/hatch workspace on this ticket's branch, or point me to the manifest schema? My recommendation: give me the app workspace. I'd then draw Echo-today from the real Iris notice code and propose three launch notices. A guess made without the real code would cost you a specimen that doesn't match Echo."

    func testLongQuestionIsSplit() {
        let d = QuestionDigest(long)
        XCTAssertTrue(d.isLong)
        XCTAssertEqual(d.lead, "I can't prepare #5 yet.")
        XCTAssertEqual(d.ask, "Can you give me access to a tashda/hatch workspace on this ticket's branch, or point me to the manifest schema?")
        XCTAssertEqual(d.recommendation, "Give me the app workspace")
        XCTAssertEqual(d.acceptAnswer, "Go with your recommendation: give me the app workspace.")
    }

    func testShortQuestionStaysWhole() {
        let d = QuestionDigest("Which area does this belong to? I recommend Settings.")
        XCTAssertFalse(d.isLong)
        XCTAssertNil(d.lead)
        XCTAssertEqual(d.ask, "Which area does this belong to? I recommend Settings.")
        XCTAssertEqual(d.recommendation, "Settings")
    }

    func testNoQuestionMarkFallsBackToFirstSentence() {
        let text = String(repeating: "The agent needs the schema to go on. ", count: 8) + "Tell it where the schema is."
        let d = QuestionDigest(text)
        XCTAssertTrue(d.isLong)
        XCTAssertEqual(d.ask, "The agent needs the schema to go on.")
        XCTAssertNil(d.recommendation)
    }

    func testSentencesKeepNamesWithDots() {
        XCTAssertEqual(QuestionDigest.sentences("Use v1.2 here. Then ask again?"), ["Use v1.2 here.", "Then ask again?"])
    }
}
