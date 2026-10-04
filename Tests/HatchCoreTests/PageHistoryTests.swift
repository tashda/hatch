import XCTest
@testable import HatchCore

final class PageHistoryTests: XCTestCase {
    func testVisitBackForward() {
        var h = PageHistory(start: "desk")
        XCTAssertFalse(h.canGoBack)
        h.visit("tickets"); h.visit("board")
        XCTAssertEqual(h.current, "board")
        XCTAssertEqual(h.backPage, "tickets")
        XCTAssertEqual(h.goBack(), "tickets")
        XCTAssertEqual(h.forwardPage, "board")
        XCTAssertEqual(h.goForward(), "board")
        XCTAssertFalse(h.canGoForward)
    }

    func testVisitingTheSamePageChangesNothing() {
        var h = PageHistory(start: 1)
        XCTAssertFalse(h.visit(1))
        XCTAssertFalse(h.canGoBack)
    }

    func testANewVisitClearsForward() {
        var h = PageHistory(start: "a")
        h.visit("b"); h.goBack()
        XCTAssertTrue(h.canGoForward)
        h.visit("c")
        XCTAssertFalse(h.canGoForward)
        XCTAssertEqual(h.backPage, "a")
    }

    func testGoingBackAtTheStartDoesNothing() {
        var h = PageHistory(start: "a")
        XCTAssertNil(h.goBack())
        XCTAssertNil(h.goForward())
        XCTAssertEqual(h.current, "a")
    }

    func testHistoryIsBounded() {
        var h = PageHistory(start: 0)
        for i in 1...(PageHistory<Int>.limit + 20) { h.visit(i) }
        XCTAssertEqual(h.backStack.count, PageHistory<Int>.limit)
        XCTAssertEqual(h.backStack.last, PageHistory<Int>.limit + 19)
    }

    func testReplaceCurrentKeepsHistory() {
        var h = PageHistory(start: "a")
        h.visit("b")
        h.replaceCurrent(with: "c")
        XCTAssertEqual(h.current, "c")
        XCTAssertEqual(h.backPage, "a")
    }
}
