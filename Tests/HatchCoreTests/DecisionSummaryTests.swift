import XCTest
@testable import HatchCore

final class DecisionSummaryTests: XCTestCase {
    func testQuestionsOfEveryKindCountTogetherInAFixedOrder() {
        let kinds: [PendingDecision.Kind] = [.verify, .pick, .iris, .verify, .answer, .judge, .plan]
        XCTAssertEqual(PendingDecision.summary(of: kinds), "3 questions · 1 plan to approve · 1 to judge · 2 to verify")
    }

    func testSingularAndEmpty() {
        XCTAssertEqual(PendingDecision.summary(of: [.submit]), "1 draft")
        XCTAssertEqual(PendingDecision.summary(of: [.plan, .plan, .submit, .submit]), "2 plans to approve · 2 drafts")
        XCTAssertEqual(PendingDecision.summary(of: []), "")
    }
}
